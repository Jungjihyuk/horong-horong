import Darwin
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
    var providerOptions: NewsProviderOptionsPayload?
    var interestKeywords: [String]
    var maxItemsPerSource: Int
    var dateRangeHours: Int
    var outputDir: String
    var sources: [NewsSource]
}

struct NewsProviderOptionsPayload: Codable {
    var model: String?
    var endpoint: String?
    var timeout: Double?
}

struct OllamaTagsResponse: Decodable {
    var models: [OllamaModelTag]
}

struct OllamaModelTag: Decodable {
    var name: String
    var model: String?
}

struct OllamaModelInstallProgress: Sendable {
    var message: String
    var fraction: Double?
}

private final class ProcessOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    func append(_ value: String) {
        lock.lock()
        defer { lock.unlock() }
        text += value
    }

    func snapshot() -> String {
        lock.lock()
        defer { lock.unlock() }
        return text
    }
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

struct NewsProviderCLIResolution {
    let provider: String
    let command: String
    let executablePath: String
    let environment: [String: String]
}

enum NewsProviderCLIResolverError: Error, Equatable {
    case unsupportedProvider(String)
    case notFound(provider: String, command: String)
    case notExecutable(provider: String, path: String)

    var message: String {
        switch self {
        case .unsupportedProvider(let provider):
            return "'\(provider)' 뉴스 Provider는 지원하지 않습니다."
        case .notFound(let provider, let command):
            return "\(provider) Provider 실행 파일 '\(command)'을 찾을 수 없습니다. 터미널에서 '\(command) --version'이 동작하는지 확인한 뒤 앱을 다시 실행해주세요."
        case .notExecutable(let provider, let path):
            return "\(provider) Provider 실행 파일을 찾았지만 실행할 수 없습니다: \(path)"
        }
    }
}

struct NewsProviderCLIResolver {
    typealias CommandRunner = (_ executablePath: String, _ arguments: [String], _ environment: [String: String]) -> String?
    typealias ExecutabilityChecker = (_ path: String) -> Bool
    typealias UserShellProvider = () -> String?

    private let environment: [String: String]
    private let commandRunner: CommandRunner
    private let isExecutable: ExecutabilityChecker
    private let userShellProvider: UserShellProvider

    init(
        environment: [String: String],
        commandRunner: @escaping CommandRunner = NewsProviderCLIResolver.commandOutput,
        isExecutable: @escaping ExecutabilityChecker = { FileManager.default.isExecutableFile(atPath: $0) },
        userShellProvider: @escaping UserShellProvider = NewsProviderCLIResolver.currentUserShellPath
    ) {
        self.environment = environment
        self.commandRunner = commandRunner
        self.isExecutable = isExecutable
        self.userShellProvider = userShellProvider
    }

    func resolve(provider: String) -> Result<NewsProviderCLIResolution, NewsProviderCLIResolverError> {
        guard let command = Self.command(for: provider) else {
            return .failure(.unsupportedProvider(provider))
        }

        let candidates = [
            lookup(command: command, shellPath: "/bin/sh", arguments: ["-lc", "command -v \(command)"]),
            loginShellLookup(command: command),
        ]
        let executablePath = candidates.compactMap { $0 }.first

        guard let executablePath else {
            return .failure(.notFound(provider: provider, command: command))
        }
        guard isExecutable(executablePath) else {
            return .failure(.notExecutable(provider: provider, path: executablePath))
        }

        return .success(NewsProviderCLIResolution(
            provider: provider,
            command: command,
            executablePath: executablePath,
            environment: environment(prependingExecutableDirectoryFor: executablePath)
        ))
    }

    static func command(for provider: String) -> String? {
        switch provider {
        case "ollama": return "ollama"
        case "codex": return "codex"
        case "claude": return "claude"
        case "gemini": return "gemini"
        case "opencode": return "opencode"
        case "antigravity": return "agy"
        default: return nil
        }
    }

    static func currentUserShellPath() -> String? {
        guard let passwd = getpwuid(getuid()),
              let shell = passwd.pointee.pw_shell else {
            return nil
        }
        let path = String(cString: shell).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    private func loginShellLookup(command: String) -> String? {
        for shell in loginShellCandidates() {
            if let result = lookup(command: command, shellPath: shell, arguments: ["-lic", "command -v \(command)"]) {
                return result
            }
        }
        return nil
    }

    private func loginShellCandidates() -> [String] {
        var candidates = [
            environment["SHELL"],
            userShellProvider(),
            "/bin/zsh",
            "/bin/bash",
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        candidates = candidates.filter { seen.insert($0).inserted }
        return candidates
    }

    private func lookup(command: String, shellPath: String, arguments: [String]) -> String? {
        guard let output = commandRunner(shellPath, arguments, environment) else { return nil }
        return Self.executablePath(for: command, in: output)
    }

    static func executablePath(for command: String, in output: String) -> String? {
        for token in output.components(separatedBy: .whitespacesAndNewlines) {
            var searchStart = token.startIndex
            while let slashIndex = token[searchStart...].firstIndex(of: "/") {
                let rawCandidate = String(token[slashIndex...])
                let candidate = sanitizedPathCandidate(rawCandidate)
                if URL(fileURLWithPath: candidate).lastPathComponent == command {
                    return candidate
                }
                searchStart = token.index(after: slashIndex)
            }
        }
        return nil
    }

    private static func sanitizedPathCandidate(_ raw: String) -> String {
        let scalars = raw.unicodeScalars.prefix { scalar in
            scalar.value > 32 && scalar.value != 127
        }
        return String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`,;"))
    }

    private func environment(prependingExecutableDirectoryFor executablePath: String) -> [String: String] {
        var resolved = environment
        let directory = URL(fileURLWithPath: executablePath).deletingLastPathComponent().path
        let currentPath = resolved["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        var components = [directory]
        components.append(contentsOf: currentPath.components(separatedBy: ":"))

        var seen = Set<String>()
        resolved["PATH"] = components
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
            .joined(separator: ":")
        return resolved
    }

    private static func commandOutput(
        executablePath: String,
        arguments: [String],
        environment: [String: String]
    ) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executablePath)
        proc.arguments = arguments
        proc.environment = environment

        let stdoutPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = Pipe()

        do {
            try proc.run()
            let semaphore = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .utility).async {
                proc.waitUntilExit()
                semaphore.signal()
            }
            if semaphore.wait(timeout: .now() + 5) == .timedOut {
                proc.terminate()
                return nil
            }
            guard proc.terminationStatus == 0 else { return nil }
            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
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
        providerOptions: NewsProviderOptionsPayload? = nil,
        runnerPath: String,
        dataBasePath: String,
        interestKeywords: [String],
        youtubeChannelIds: [String] = [],
        maxItemsPerSource: Int = 10,
        context: ModelContext
    ) {
        guard !isRunning else { return }

        lastErrorCode = nil
        lastErrorMessage = nil
        lastWarnings = []

        guard !runnerPath.isEmpty,
              FileManager.default.fileExists(atPath: runnerPath) else {
            finishConfigurationFailed(code: "E_CONFIG", message: Constants.newsRunnerMissingMessage)
            return
        }

        var environment = enrichedEnvironment(newsDataBasePath: dataBasePath)
        guard commandSucceeds(["uv", "--version"], environment: environment) else {
            finishConfigurationFailed(
                code: "E_ENV",
                message: "뉴스 리포트 기능을 사용하려면 uv가 필요합니다. uv를 설치한 뒤 앱을 다시 실행해주세요."
            )
            return
        }
        guard commandSucceeds(["python3", "--version"], environment: environment) else {
            finishConfigurationFailed(
                code: "E_ENV",
                message: "뉴스 리포트 기능을 사용하려면 Python 3가 필요합니다. Python 3를 설치한 뒤 앱을 다시 실행해주세요."
            )
            return
        }
        if provider != "ollama" {
            let providerResolution = NewsProviderCLIResolver(environment: environment).resolve(provider: provider)
            switch providerResolution {
            case .success(let resolution):
                environment = resolution.environment
            case .failure(let error):
                finishConfigurationFailed(code: "E_PROVIDER_CLI", message: error.message)
                return
            }
        }

        let jobId = generateJobId()
        isRunning = true
        currentStep = "queued"
        elapsedSeconds = 0
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

        // 설정 창의 NewsSourceStore 에서 사용자가 등록한 소스를 그대로 받아온다.
        // 사용자 interest_keywords 를 google_news / yozm_it 의 검색어로 전파해 fetch 범위가 키워드에 따라 달라지게 한다.
        var sources = NewsSourceStore.shared.toPipelineSources(interestKeywords: interestKeywords)

        // 호환성: 팝오버 NewsView 가 전달하는 youtubeChannelIds(legacy CSV 기반) 가 있고,
        // NewsSourceStore 에 등록된 YouTube 항목이 없다면 그 채널들로 채워 넣는다.
        if !youtubeChannelIds.isEmpty,
           !sources.contains(where: { $0.type == "youtube" }) {
            sources.append(NewsSource(
                type: "youtube",
                enabled: true,
                channelIds: youtubeChannelIds
            ))
        }

        // 그래도 비어있으면 (사용자가 아무 소스도 등록 안 한 첫 사용자) 디폴트 소스로 폴백.
        if sources.isEmpty {
            sources = NewsSource.defaultSources
        }

        // Build and write request.json
        let request = NewsJobRequestPayload(
            jobId: jobId,
            requestedAt: isoString(Date()),
            provider: provider,
            providerOptions: providerOptions,
            interestKeywords: interestKeywords,
            maxItemsPerSource: max(1, maxItemsPerSource),
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
        proc.environment = environment

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

    func isOllamaModelInstalled(model: String, endpoint: String) async throws -> Bool {
        let installedModels = try await installedOllamaModelNames(endpoint: endpoint)
        return installedModels.contains(model)
    }

    func installedOllamaModelNames(endpoint: String) async throws -> Set<String> {
        let tagsURL = try ollamaURL(endpoint: endpoint, path: "/api/tags")
        let (data, response) = try await URLSession.shared.data(from: tagsURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw OllamaModelError.serverUnavailable
        }

        let tags = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        return Set(tags.models.flatMap { tag in
            [tag.name, tag.model].compactMap { $0 }
        })
    }

    func installOllamaModel(
        model: String,
        dataBasePath: String,
        progress: (@MainActor @Sendable (OllamaModelInstallProgress) -> Void)? = nil
    ) async throws {
        var environment = enrichedEnvironment(newsDataBasePath: dataBasePath)
        let providerResolution = NewsProviderCLIResolver(environment: environment).resolve(provider: "ollama")
        switch providerResolution {
        case .success(let resolution):
            environment = resolution.environment
        case .failure(let error):
            throw OllamaModelError.commandUnavailable(error.message)
        }

        try await runCommand(["ollama", "pull", model], environment: environment, progress: progress)
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

    private func finishConfigurationFailed(code: String, message: String) {
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

    private func enrichedEnvironment(newsDataBasePath: String) -> [String: String] {
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
        let trimmedDataBasePath = newsDataBasePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDataBasePath.isEmpty {
            env["UV_PROJECT_ENVIRONMENT"] = URL(fileURLWithPath: trimmedDataBasePath, isDirectory: true)
                .appendingPathComponent(".venv", isDirectory: true)
                .path
        }
        return env
    }

    private func commandSucceeds(_ arguments: [String], environment: [String: String]) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = arguments
        proc.environment = environment
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()

        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func runCommand(
        _ arguments: [String],
        environment: [String: String],
        progress: (@MainActor @Sendable (OllamaModelInstallProgress) -> Void)? = nil
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                proc.arguments = arguments
                proc.environment = environment

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                proc.standardOutput = stdoutPipe
                proc.standardError = stderrPipe

                let outputBuffer = ProcessOutputBuffer()

                let handleData: @Sendable (Data) -> Void = { [weak self] data in
                    guard !data.isEmpty,
                          let text = String(data: data, encoding: .utf8) else {
                        return
                    }
                    outputBuffer.append(text)
                    if let progressEvent = self?.ollamaInstallProgress(from: text) {
                        Task { @MainActor in
                            progress?(progressEvent)
                        }
                    }
                }

                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    handleData(handle.availableData)
                }
                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    handleData(handle.availableData)
                }

                do {
                    Task { @MainActor in
                        progress?(OllamaModelInstallProgress(message: "다운로드 시작 중...", fraction: nil))
                    }
                    try proc.run()
                    proc.waitUntilExit()

                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil

                    if proc.terminationStatus == 0 {
                        Task { @MainActor in
                            progress?(OllamaModelInstallProgress(message: "설치 완료", fraction: 1.0))
                        }
                        continuation.resume(returning: ())
                    } else {
                        let output = outputBuffer.snapshot()
                        let stderr = output.trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(throwing: OllamaModelError.pullFailed(stderr.isEmpty ? "ollama pull 실패" : stderr))
                    }
                } catch {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func ollamaInstallProgress(from text: String) -> OllamaModelInstallProgress? {
        let cleaned = text.replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*[A-Za-z]",
            with: "",
            options: .regularExpression
        )
        let lines = cleaned
            .components(separatedBy: CharacterSet(charactersIn: "\r\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let line = lines.last else { return nil }

        let message = line.count > 90 ? String(line.prefix(90)) : line
        return OllamaModelInstallProgress(
            message: message,
            fraction: percentageFraction(in: line)
        )
    }

    private func percentageFraction(in text: String) -> Double? {
        guard let range = text.range(of: #"\d{1,3}%"#, options: .regularExpression) else {
            return nil
        }
        let rawPercent = text[range].dropLast()
        guard let percent = Double(rawPercent) else { return nil }
        return min(max(percent, 0), 100) / 100
    }

    private func ollamaURL(endpoint: String, path: String) throws -> URL {
        let normalizedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !normalizedEndpoint.isEmpty,
              let url = URL(string: normalizedEndpoint + path) else {
            throw OllamaModelError.invalidEndpoint(endpoint)
        }
        return url
    }

    private func generateJobId() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        let datePart = formatter.string(from: Date())
        return "\(datePart)-KST"
    }

    private func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

enum OllamaModelError: LocalizedError {
    case invalidEndpoint(String)
    case serverUnavailable
    case commandUnavailable(String)
    case pullFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint(let endpoint):
            return "Ollama endpoint가 올바르지 않습니다: \(endpoint)"
        case .serverUnavailable:
            return "Ollama 서버에 연결할 수 없습니다. Ollama 앱 또는 `ollama serve`가 실행 중인지 확인해주세요."
        case .commandUnavailable(let message):
            return message
        case .pullFailed(let message):
            return "Ollama 모델 다운로드에 실패했습니다. \(message)"
        }
    }
}
