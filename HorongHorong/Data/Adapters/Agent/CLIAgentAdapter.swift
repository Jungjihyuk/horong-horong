import Foundation

/// `AgentGateway` 의 구현. 터미널을 띄워 CLI Agent 에게 프롬프트를 건넨다.
///
/// **여기 있는 것은 바깥과 닿는 일뿐이다** — 폴더 확인·파일 찾기·명령 조립·프로세스 실행.
/// 프롬프트 문장과 계획 파일 파싱은 `Domain/Policies` 에 있고 이 타입은 그것을 부르기만 한다.
@MainActor
struct CLIAgentAdapter: AgentGateway {
    private let fileManager: FileManager
    private let now: () -> Date

    init(fileManager: FileManager = .default, now: @escaping () -> Date = Date.init) {
        self.fileManager = fileManager
        self.now = now
    }

    func generatePlan(_ request: AgentPlanRequest) throws -> AgentPlanLaunchResult {
        let ideaDir = try preparedDirectory(request.ideaDirectoryPath, emptyMessage: "아이디어 폴더가 비어 있습니다.")
        let outputDir = try preparedDirectory(request.outputDirectoryPath, emptyMessage: "출력 폴더가 비어 있습니다.")

        let fileName = ExperimentPlanText.outputFileName(on: now(), dayCount: request.dayCount)
        let prompt = AgentPrompt.plan(
            ideaDirectoryPath: ideaDir,
            outputFilePath: outputDir + "/" + fileName,
            interestKeywords: request.interestKeywords,
            agent: request.agent,
            dayCount: request.dayCount,
            now: now()
        )

        let workspace = ExperimentPlanText.workspaceDirectory(
            ideaDirectoryPath: ideaDir,
            outputDirectoryPath: outputDir
        )
        // 출력 폴더를 명령 안에서 한 번 더 만든다. 여기서 만든 뒤 사용자가 지웠을 수 있다.
        try runInTerminal(
            "cd \(Self.shellQuote(workspace)); mkdir -p \(Self.shellQuote(outputDir)); "
                + Self.command(for: request.agent, prompt: prompt)
        )

        return AgentPlanLaunchResult(outputFileName: fileName)
    }

    func runTodayExperiment(_ request: TodayExperimentRequest) throws -> TodayExperimentRunResult {
        let outputDir = try preparedDirectory(request.outputDirectoryPath, emptyMessage: "출력 폴더가 비어 있습니다.")

        let today = ExperimentPlanText.isoDate(now())
        let planFileURL = try planFile(in: outputDir, today: today)
        guard let content = try? String(contentsOf: planFileURL, encoding: .utf8) else {
            throw AgentRunError.fileReadFailed(planFileURL.lastPathComponent)
        }
        guard let section = ExperimentPlanText.todaySection(in: content, today: today) else {
            throw AgentRunError.todaySectionNotFound(planFileURL.lastPathComponent)
        }

        let prompt = AgentPrompt.todayExperiment(
            interestKeywords: request.interestKeywords,
            today: today,
            todaySection: section
        )
        let workspace = ExperimentPlanText.parentDirectory(of: outputDir)
        try runInTerminal(
            "cd \(Self.shellQuote(workspace)); " + Self.command(for: request.agent, prompt: prompt)
        )

        return TodayExperimentRunResult(planFileName: planFileURL.lastPathComponent)
    }

    // MARK: - 파일

    private func preparedDirectory(_ path: String, emptyMessage: String) throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AgentRunError.invalidDirectory(emptyMessage) }
        try fileManager.createDirectory(atPath: trimmed, withIntermediateDirectories: true)
        guard fileManager.fileExists(atPath: trimmed) else { throw AgentRunError.invalidDirectory(trimmed) }
        return trimmed
    }

    /// 오늘 몫이 든 계획 파일. **이름에 오늘 날짜가 붙은 것을 먼저 보고**, 없으면 최근에 고친
    /// 순서로 본문을 뒤진다 — 어제 만든 5일치 계획 안에 오늘이 들어 있을 수 있다.
    private func planFile(in directory: String, today: String) throws -> URL {
        let directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        guard let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw AgentRunError.planFileNotFound(directory)
        }

        let candidates = files
            .filter { $0.pathExtension.lowercased() == "md" && $0.lastPathComponent.contains("_experiment_plan_") }
            .sorted {
                let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
        guard !candidates.isEmpty else { throw AgentRunError.planFileNotFound(directory) }

        if let named = candidates.first(where: { $0.lastPathComponent.hasPrefix("\(today)_experiment_plan_") }) {
            return named
        }
        for file in candidates {
            let matches = ExperimentPlanText.containsPlan(
                for: today,
                fileName: file.lastPathComponent,
                content: try? String(contentsOf: file, encoding: .utf8)
            )
            if matches { return file }
        }
        throw AgentRunError.planFileNotFound(directory)
    }

    // MARK: - 실행

    /// 터미널 앱에 명령을 건네고 활성화한다.
    ///
    /// **결과를 기다리지 않는다** — `do script` 는 명령을 띄우기만 하고 바로 돌아온다.
    /// 사용자가 진행 상황을 터미널에서 직접 본다.
    private func runInTerminal(_ command: String) throws {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", "tell application \"Terminal\" to activate",
            "-e", "tell application \"Terminal\" to do script \"\(escaped)\"",
        ]

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                throw AgentRunError.scriptExecutionFailed("종료 코드 \(process.terminationStatus)")
            }
        } catch let error as AgentRunError {
            throw error
        } catch {
            throw AgentRunError.scriptExecutionFailed(error.localizedDescription)
        }
    }

    /// Agent 별 CLI 명령. **여기가 유일하게 실제 실행 파일 이름을 아는 곳이다.**
    static func command(for agent: AgentKind, prompt: String) -> String {
        let quoted = shellQuote(prompt)
        switch agent {
        case .codex: return "codex \(quoted)"
        case .claude: return "claude \(quoted)"
        case .antigravity: return "agy --prompt-interactive \(quoted)"
        case .opencode: return "opencode run \(quoted)"
        case .hermes: return "hermes chat send \(quoted)"
        }
    }

    /// 작은따옴표로 감싸고, 안의 작은따옴표는 `'"'"'` 로 끊어 잇는다.
    /// 프롬프트에 사용자가 쓴 문장이 그대로 들어가므로 이스케이프가 새면 명령이 깨진다.
    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
