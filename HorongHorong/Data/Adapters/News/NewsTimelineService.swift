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

    var providerDisplayName: String { providerPlan().displayName }

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

    func buildTimeline(label: String, axisLimit: Int, dataBasePath: String) async throws {
        buildingLabel = label
        lastErrorMessage = nil
        defer { buildingLabel = nil }

        do {
            _ = try await run(
                arguments: [
                    "--category", label,
                    "--axis-limit", String(min(5, max(1, axisLimit))),
                ] + providerArguments(),
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

    /// 이 실행에 쓸 provider 와 옵션.
    ///
    /// **기본은 리포트 설정 상속(`inherit`)이다.** 갈라 쓸 이유가 있을 때만 나뉜다 —
    /// 리포트는 기사마다 수십 회를 부르고, 타임라인은 실행당 1~2회로 한 달치를 종합한다.
    /// 그래서 타임라인만 더 좋은(비싼) 모델을 써도 총액이 작다.
    struct TimelineProviderPlan {
        let provider: String
        let options: NewsProviderOptionsPayload?
        /// 사용자에게 보여줄 한 줄. 「무엇으로 만들어지는지」를 누르기 전에 알린다.
        var displayName: String {
            if let model = options?.model, !model.isEmpty { return "\(provider) · \(model)" }
            if let effort = options?.effort, !effort.isEmpty { return "\(provider) · \(effort)" }
            return provider
        }
    }

    func providerPlan() -> TimelineProviderPlan {
        let reportConfiguration = NewsPipelineLaunchConfiguration.current(defaults: defaults)
        let stored = defaults.string(forKey: Constants.NewsStorageKey.timelineProvider)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let provider = (stored.isEmpty || stored == Constants.newsTimelineInheritProvider)
            ? reportConfiguration.provider
            : stored

        var options = NewsPipelineLaunchConfiguration.options(for: provider, defaults: defaults)

        // 타임라인 전용 값이 있으면 그것만 덮어쓴다. endpoint·timeout 은 리포트와 공유해도
        // 무방하므로 설정을 두 벌로 늘리지 않는다.
        if provider == "ollama",
           let model = defaults.string(forKey: Constants.NewsStorageKey.timelineOllamaModel)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !model.isEmpty {
            options?.model = model
        }
        if provider == "antigravity" {
            // **리포트 값을 물려받지 않는다.** 리포트는 기사마다 수십 회를 불러 low 가
            // 기본이지만, 타임라인은 월별 1회 + 개요 1회뿐이라 한 단계 높여도 총액이 작다.
            let stored = defaults.string(forKey: Constants.NewsStorageKey.timelineAntigravityEffort)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            options?.effort = stored.isEmpty
                ? Constants.defaultNewsTimelineAntigravityEffort
                : stored
        }

        return TimelineProviderPlan(provider: provider, options: options)
    }

    private func providerArguments() -> [String] {
        let plan = providerPlan()
        var arguments = ["--provider", plan.provider]
        if let options = plan.options {
            if let model = options.model { arguments += ["--model", model] }
            if let endpoint = options.endpoint { arguments += ["--endpoint", endpoint] }
            // 러너의 `--timeout` 은 정수만 받는다. Double 을 그대로 넣으면 "120.0" 이 되어 거부된다.
            if let timeout = options.timeout { arguments += ["--timeout", String(Int(timeout))] }
            if let effort = options.effort { arguments += ["--effort", effort] }
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
        let reportCount: Int?
        let monthCount: Int?
        let dateFrom: String?
        let dateTo: String?
        let alreadyExists: Bool?
        let estimatedCalls: Int?
        let hasUpdates: Bool?

        var toDomain: NewsTimelineSuggestion {
            NewsTimelineSuggestion(
                label: label,
                headings: headings ?? [],
                eventCount: eventCount ?? 0,
                reportCount: reportCount ?? 0,
                monthCount: monthCount ?? 0,
                dateFrom: dateFrom ?? "",
                dateTo: dateTo ?? "",
                alreadyExists: alreadyExists ?? false,
                estimatedCalls: estimatedCalls ?? 0,
                hasUpdates: hasUpdates ?? true
            )
        }
    }

    let suggestions: [Item]
}
