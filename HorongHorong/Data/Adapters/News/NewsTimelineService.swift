import Foundation

/// `timeline_runner.py` 를 띄워 주제를 제안받고 타임라인을 만든다.
///
/// **리포트 파이프라인과 완전히 분리된 프로세스다.** 리포트 생성(`NewsPipelineService`)은
/// 예전 그대로 돌고, 타임라인은 사용자가 버튼을 눌렀을 때만 이쪽이 돈다. 리포트 job 이
/// 타임라인 때문에 느려지거나 실패하는 일이 없다.
@MainActor
@Observable
final class NewsTimelineService: NewsTimelineGateway {
    /// 지금 타임라인을 만들고 있는 주제. 비어 있으면 대기 상태다.
    private(set) var buildingLabel: String?
    private(set) var lastErrorMessage: String?

    var isBuilding: Bool { buildingLabel != nil }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - NewsTimelineGateway

    func suggestTopics(dataBasePath: String) async throws -> [NewsTimelineSuggestion] {
        let output = try await run(arguments: ["--suggest"], dataBasePath: dataBasePath)
        guard let data = output.data(using: .utf8) else { throw NewsTimelineError.malformedOutput }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let payload = try? decoder.decode(SuggestionPayload.self, from: data) else {
            throw NewsTimelineError.malformedOutput
        }
        return payload.suggestions.map(\.toDomain)
    }

    func buildTimeline(label: String, dataBasePath: String) async throws {
        buildingLabel = label
        lastErrorMessage = nil
        defer { buildingLabel = nil }

        do {
            _ = try await run(
                arguments: ["--category", label] + providerArguments(),
                dataBasePath: dataBasePath
            )
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - 프로세스

    /// 리포트 러너와 같은 폴더의 `timeline_runner.py`.
    ///
    /// 러너 경로를 따로 설정하게 두지 않는 이유: 두 러너는 같은 패키지 안에 있어서
    /// 갈라지면 파이썬 임포트가 깨진다. 하나만 설정하고 형제 파일을 찾는다.
    static func timelineRunnerPath(reportRunnerPath: String) -> String? {
        let sibling = URL(fileURLWithPath: reportRunnerPath)
            .deletingLastPathComponent()
            .appendingPathComponent("timeline_runner.py")
        return FileManager.default.fileExists(atPath: sibling.path) ? sibling.path : nil
    }

    private func providerArguments() -> [String] {
        let configuration = NewsPipelineLaunchConfiguration.current(defaults: defaults)
        var arguments = ["--provider", configuration.provider]
        if let options = configuration.providerOptions {
            if let model = options.model { arguments += ["--model", model] }
            if let endpoint = options.endpoint { arguments += ["--endpoint", endpoint] }
            // 러너의 `--timeout` 은 정수만 받는다. Double 을 그대로 넣으면 "120.0" 이 되어 거부된다.
            if let timeout = options.timeout { arguments += ["--timeout", String(Int(timeout))] }
        }
        return arguments
    }

    /// 러너를 돌리고 표준 출력을 돌려준다. 실패하면 표준 에러를 담아 던진다.
    private func run(arguments: [String], dataBasePath: String) async throws -> String {
        let configuration = NewsPipelineLaunchConfiguration.current(defaults: defaults)
        guard let runnerPath = Self.timelineRunnerPath(
            reportRunnerPath: configuration.runnerPath
        ) else {
            throw NewsTimelineError.runnerNotFound
        }

        let environment = Self.processEnvironment(dataBasePath: dataBasePath)
        let fullArguments = ["uv", "run", "python3", runnerPath, "--output-dir", dataBasePath]
            + arguments

        return try await withCheckedThrowingContinuation { continuation in
            // 프로세스 대기는 메인 스레드를 막으면 안 된다 — 타임라인 생성은 분 단위다.
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = fullArguments
                process.environment = environment
                // **러너 폴더에서 실행해야 한다.** `uv` 는 CWD 에서 프로젝트를 찾고,
                // 파이썬도 CWD 기준으로 패키지를 임포트한다. 빠뜨리면
                // `ModuleNotFoundError: No module named 'pydantic'` 로 죽는다
                // (`NewsPipelineService` 도 같은 이유로 이 값을 설정한다).
                process.currentDirectoryURL = URL(fileURLWithPath: runnerPath)
                    .deletingLastPathComponent()

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(
                        throwing: NewsTimelineError.runnerFailed(
                            code: -1, message: error.localizedDescription
                        )
                    )
                    return
                }

                // 파이프를 먼저 비워야 한다. 출력이 버퍼를 채우면 프로세스가 멈춰 교착된다.
                let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let stdout = String(data: outData, encoding: .utf8) ?? ""
                if process.terminationStatus == 0 {
                    continuation.resume(returning: stdout)
                } else {
                    let stderr = (String(data: errData, encoding: .utf8) ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(
                        throwing: NewsTimelineError.runnerFailed(
                            code: process.terminationStatus,
                            message: stderr.isEmpty ? stdout : stderr
                        )
                    )
                }
            }
        }
    }

    /// `uv` 와 파이썬을 찾을 수 있도록 PATH 를 넓힌다.
    /// `NewsPipelineService.enrichedEnvironment` 와 같은 이유·같은 값이다.
    nonisolated static func processEnvironment(dataBasePath: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = environment["HOME"] ?? NSHomeDirectory()
        let extraPaths = [
            "\(home)/.local/bin",
            "\(home)/.cargo/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]
        let current = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = (extraPaths + [current]).filter { !$0.isEmpty }.joined(separator: ":")

        let trimmed = dataBasePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            environment["UV_PROJECT_ENVIRONMENT"] = URL(fileURLWithPath: trimmed, isDirectory: true)
                .appendingPathComponent(".venv", isDirectory: true)
                .path
        }
        return environment
    }
}

// MARK: - 디코딩

/// `timeline_runner.py --suggest` 의 출력 모양.
struct SuggestionPayload: Decodable {
    struct Item: Decodable {
        let label: String
        let headings: [String]?
        let eventCount: Int?
        let monthCount: Int?
        let dateFrom: String?
        let dateTo: String?
        let alreadyExists: Bool?
        let estimatedCalls: Int?

        var toDomain: NewsTimelineSuggestion {
            NewsTimelineSuggestion(
                label: label,
                headings: headings ?? [],
                eventCount: eventCount ?? 0,
                monthCount: monthCount ?? 0,
                dateFrom: dateFrom ?? "",
                dateTo: dateTo ?? "",
                alreadyExists: alreadyExists ?? false,
                estimatedCalls: estimatedCalls ?? 0
            )
        }
    }

    let suggestions: [Item]
}
