import Foundation
import SwiftData

// MARK: - JSON Contract Structures

struct NewsPlaylist: Codable {
    var name: String
    var playlistId: String
}

struct NewsSource: Codable {
    var type: String
    var enabled: Bool
    var channelId: String?
    var channelIds: [String]?
    var playlists: [NewsPlaylist]?
    var keywords: [String]?
    var profiles: [String]?
}

extension NewsSource {
    static let defaultSources: [NewsSource] = [
        NewsSource(type: "youtube", enabled: true, channelId: "UC_x5XG1OV2P6uZZ5FSM9Ttw"),
        NewsSource(type: "google_news", enabled: true, keywords: ["AI", "개발", "생산성", "자동화"]),
        NewsSource(type: "linkedin", enabled: false, profiles: []),
        NewsSource(type: "yozm_it", enabled: true, keywords: ["개발", "생산성", "AI", "자동화"]),
    ]
}

struct NewsJobRequestPayload: Codable {
    var jobId: String
    var requestedAt: String
    var provider: String
    var interestKeywords: [String]
    var maxItemsPerSource: Int
    var dateRangeHours: Int
    var outputDir: String
    var sources: [NewsSource]
}

struct NewsTopItem: Codable {
    var title: String
    var url: String
    var importanceScore: Int
    var category: String
}

struct NewsSourceStats: Codable {
    var fetched: Int
    var used: Int
    var failed: Int
}

struct NewsJobResultPayload: Codable {
    var jobId: String
    var status: String
    var startedAt: String?
    var endedAt: String?
    var reportPath: String?
    var metaPath: String?
    var sourceStats: [String: NewsSourceStats]?
    var topItems: [NewsTopItem]?
    var warnings: [String]?
    var errorCode: String?
    var errorMessage: String?
}

// MARK: - Service

@Observable
final class NewsPipelineService: @unchecked Sendable {
    private(set) var isRunning = false
    private(set) var currentStep = ""
    private(set) var elapsedSeconds = 0
    private(set) var lastJobStatus = ""
    private(set) var lastErrorCode: String?
    private(set) var lastErrorMessage: String?
    private(set) var lastWarnings: [String] = []

    private var process: Process?
    private var elapsedTimer: Timer?
    private var startTime: Date?

    func startJob(
        provider: String,
        runnerPath: String,
        dataBasePath: String,
        interestKeywords: [String],
        youtubeChannelIds: [String] = [],
        context: ModelContext
    ) {
        guard !isRunning else { return }
        guard !runnerPath.isEmpty else {
            lastErrorCode = "E_CONFIG"
            lastErrorMessage = "Runner 경로를 설정해주세요"
            lastJobStatus = "failed"
            return
        }

        let jobId = generateJobId()
        isRunning = true
        currentStep = "queued"
        elapsedSeconds = 0
        lastErrorCode = nil
        lastErrorMessage = nil
        lastWarnings = []
        startTime = Date()

        // Persist job record
        let job = NewsJob(jobId: jobId, provider: provider)
        context.insert(job)
        try? context.save()

        // Build file paths
        let tempDir = FileManager.default.temporaryDirectory.path
        let requestPath = "\(tempDir)/\(jobId)_request.json"
        let resultPath = "\(tempDir)/\(jobId)_result.json"
        let logDir = "\(dataBasePath)/data/logs"
        let logPath = "\(logDir)/job-\(jobId).log"

        // Create directories: <root>/data/reports for .md, <root>/data/logs for logs, <root>/data/meta for .meta.json
        try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(
            atPath: "\(dataBasePath)/data/reports",
            withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            atPath: "\(dataBasePath)/data/meta",
            withIntermediateDirectories: true
        )

        var sources = NewsSource.defaultSources
        if let idx = sources.firstIndex(where: { $0.type == "youtube" }) {
            if !youtubeChannelIds.isEmpty {
                sources[idx].channelIds = youtubeChannelIds
                sources[idx].enabled = true
            }
        }

        // Build and write request.json
        let request = NewsJobRequestPayload(
            jobId: jobId,
            requestedAt: isoString(Date()),
            provider: provider,
            interestKeywords: interestKeywords,
            maxItemsPerSource: 10,
            dateRangeHours: 24,
            outputDir: dataBasePath,
            sources: sources
        )

        guard let encoded = try? JSONEncoder().encode(request) else {
            finishFailed(job: job, context: context, code: "E_REQUEST_WRITE", message: "request.json 인코딩 실패")
            return
        }
        do {
            try encoded.write(to: URL(fileURLWithPath: requestPath))
        } catch {
            finishFailed(job: job, context: context, code: "E_REQUEST_WRITE", message: error.localizedDescription)
            return
        }

        job.startedAt = Date()
        job.status = "running"
        try? context.save()

        // Start elapsed timer on main thread
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let start = self.startTime else { return }
            self.elapsedSeconds = Int(Date().timeIntervalSince(start))
        }

        let runnerDir = URL(fileURLWithPath: runnerPath).deletingLastPathComponent().path
        let proc = Process()
        self.process = proc
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.currentDirectoryURL = URL(fileURLWithPath: runnerDir)
        proc.arguments = [
            "uv", "run", "python3", runnerPath,
            "--request", requestPath,
            "--result", resultPath,
            "--log", logPath,
        ]
        proc.environment = enrichedEnvironment()

        let stdoutPipe = Pipe()
        proc.standardOutput = stdoutPipe
        let stderrPipe = Pipe()
        proc.standardError = stderrPipe

        // Read STEP: lines from stdout for progress
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("STEP:") else { continue }
                let step = String(trimmed.dropFirst(5))
                DispatchQueue.main.async { [weak self] in
                    self?.currentStep = step
                }
            }
        }

        do {
            try proc.run()
        } catch {
            finishFailed(job: job, context: context, code: "E_PROVIDER_EXEC", message: error.localizedDescription)
            return
        }

        // Wait for process on background thread, then handle result on main.
        // Swift 6 strict concurrency: job(@Model) / context(ModelContext) 는 Sendable 아님.
        // 실제로는 background 에선 전혀 건드리지 않고 main 으로 다시 호핑한 뒤에만 사용하므로
        // nonisolated(unsafe) 로 캡처를 명시해 컴파일러 검사 우회.
        let capturedResultPath = resultPath
        let capturedLogPath = logPath
        let capturedDataBasePath = dataBasePath
        nonisolated(unsafe) let capturedJob = job
        nonisolated(unsafe) let capturedContext = context
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            proc.waitUntilExit()
            DispatchQueue.main.async {
                self?.handleCompletion(
                    resultPath: capturedResultPath,
                    logPath: capturedLogPath,
                    dataBasePath: capturedDataBasePath,
                    job: capturedJob,
                    context: capturedContext
                )
            }
        }
    }

    func cancelJob() {
        process?.terminate()
        cleanup()
        isRunning = false
        currentStep = ""
        lastJobStatus = "cancelled"
    }

    // MARK: - Private

    private func handleCompletion(
        resultPath: String,
        logPath: String,
        dataBasePath: String,
        job: NewsJob,
        context: ModelContext
    ) {
        defer { cleanup() }

        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: resultPath)),
            let result = try? JSONDecoder().decode(NewsJobResultPayload.self, from: data)
        else {
            finishFailed(job: job, context: context, code: "E_RESULT_INVALID", message: "result.json 파싱 실패")
            return
        }

        job.endedAt = Date()
        job.status = result.status
        job.logPath = logPath
        job.errorCode = result.errorCode
        job.errorMessage = result.errorMessage
        try? context.save()

        // Index report on success or partial_success
        if result.status == "success" || result.status == "partial_success" {
            if let reportRel = result.reportPath, let metaRel = result.metaPath {
                let reportFull = "\(dataBasePath)/\(reportRel)"
                let metaFull = "\(dataBasePath)/\(metaRel)"
                let topTitle = result.topItems?.first?.title ?? "제목 없음"
                let itemCount = result.topItems?.count ?? 0
                let index = NewsReportIndex(
                    jobId: result.jobId,
                    reportDate: Date(),
                    reportPath: reportFull,
                    metaPath: metaFull,
                    topTitle: topTitle,
                    itemCount: itemCount
                )
                context.insert(index)
                try? context.save()
            }
        }

        lastJobStatus = result.status
        lastErrorCode = result.errorCode
        lastErrorMessage = result.errorMessage
        lastWarnings = result.warnings ?? []
        currentStep = result.status
        isRunning = false
    }

    private func finishFailed(job: NewsJob, context: ModelContext, code: String, message: String) {
        job.status = "failed"
        job.errorCode = code
        job.errorMessage = message
        job.endedAt = Date()
        try? context.save()

        lastJobStatus = "failed"
        lastErrorCode = code
        lastErrorMessage = message
        cleanup()
        currentStep = "failed"
        isRunning = false
    }

    private func cleanup() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        startTime = nil
        if let pipe = process?.standardOutput as? Pipe {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
        process = nil
    }

    private func enrichedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = env["HOME"] ?? NSHomeDirectory()
        let extraPaths = [
            "\(home)/.local/bin",
            "\(home)/.cargo/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]
        let current = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let merged = (extraPaths + [current])
            .filter { !$0.isEmpty }
            .joined(separator: ":")
        env["PATH"] = merged
        return env
    }

    private func generateJobId() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let datePart = formatter.string(from: Date())
        let randomPart = String(UUID().uuidString.prefix(4).lowercased())
        return "\(datePart)_\(randomPart)"
    }

    private func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
