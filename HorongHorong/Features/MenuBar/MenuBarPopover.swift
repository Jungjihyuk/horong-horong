import SwiftUI
import AppKit
import Foundation

enum PopoverTab: String, CaseIterable, Identifiable {
    case timer = "타이머"
    case memo = "메모"
    case stats = "통계"
    case news = "뉴스"
    case agent = "Agent"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .timer: return "timer"
        case .memo: return "note.text"
        case .stats: return "chart.bar"
        case .news: return "newspaper"
        case .agent: return "bolt.horizontal.circle"
        }
    }
}

struct MenuBarPopover: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    @State private var selectedTab: PopoverTab = .timer
    var timerManager: TimerManager

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            tabContent
                .id(selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 8)
            bottomBar
        }
        .frame(width: Constants.popoverWidth, height: Constants.popoverMaxHeight, alignment: .top)
        .background(PopoverChrome.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(PopoverChrome.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 30, x: 0, y: 18)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(PopoverTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: .medium))
                        Text(tab.rawValue)
                            .font(.system(size: 11.5, weight: selectedTab == tab ? .semibold : .regular))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(selectedTab == tab ? PopoverChrome.accent : PopoverChrome.inkSecondary)
                    .background(selectedTab == tab ? PopoverChrome.accentSoft : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(PopoverChrome.surfaceAlt)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PopoverChrome.divider)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .timer:
            TimerView(timerManager: timerManager)
        case .memo:
            MemoListView()
        case .stats:
            StatsSummaryView()
        case .news:
            NewsView()
        case .agent:
            AgentExperimentView()
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
                // openSettings 직후엔 윈도우가 아직 background 일 수 있어 다음 런루프에서 강제 전면화.
                DispatchQueue.main.async {
                    for window in NSApp.windows {
                        let id = window.identifier?.rawValue ?? ""
                        let title = window.title
                        if id.contains("com_apple_SwiftUI_Settings") || title.localizedCaseInsensitiveContains("설정") {
                            window.makeKeyAndOrderFront(nil)
                            window.orderFrontRegardless()
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                    Text("설정")
                        .font(.system(size: 13))
                }
                .foregroundStyle(PopoverChrome.inkSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.primary.opacity(0.00001))
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)

            Rectangle()
                .fill(PopoverChrome.divider)
                .frame(width: 1, height: 20)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 13))
                    Text("종료")
                        .font(.system(size: 13))
                }
                .foregroundStyle(PopoverChrome.inkSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.primary.opacity(0.00001))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(PopoverChrome.surfaceAlt)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(PopoverChrome.divider)
                .frame(height: 1)
        }
    }
}

enum PopoverChrome {
    static let ink = Color(red: 0.23, green: 0.16, blue: 0.10)
    static let inkSecondary = Color(red: 0.48, green: 0.36, blue: 0.27)
    static let inkTertiary = Color(red: 0.64, green: 0.52, blue: 0.39)
    static let surface = Color(red: 1.00, green: 0.965, blue: 0.91)
    static let surfaceAlt = Color(red: 0.996, green: 0.94, blue: 0.86)
    static let card = Color.white.opacity(0.78)
    static let border = Color(red: 0.71, green: 0.47, blue: 0.24).opacity(0.18)
    static let divider = Color(red: 0.71, green: 0.47, blue: 0.24).opacity(0.16)
    static let accent = Color(red: 0.94, green: 0.47, blue: 0.18)
    static let accentSoft = Color(red: 1.00, green: 0.86, blue: 0.70)
    static let accentInk = Color.white
}

struct PopoverCardModifier: ViewModifier {
    var padding: CGFloat = 12
    var radius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(PopoverChrome.border, lineWidth: 1)
            )
            .shadow(color: Color(red: 0.75, green: 0.44, blue: 0.16).opacity(0.08), radius: 6, x: 0, y: 2)
    }
}

extension View {
    func popoverCard(padding: CGFloat = 12, radius: CGFloat = 14) -> some View {
        modifier(PopoverCardModifier(padding: padding, radius: radius))
    }
}

struct LanternPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(PopoverChrome.accentInk)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(PopoverChrome.accent, in: Capsule())
            .shadow(color: PopoverChrome.accent.opacity(configuration.isPressed ? 0.12 : 0.22), radius: 10, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct LanternSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(PopoverChrome.inkSecondary)
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background(Color.white.opacity(configuration.isPressed ? 0.55 : 0.72), in: Capsule())
            .overlay(Capsule().stroke(PopoverChrome.divider, lineWidth: 1))
    }
}

struct AgentExperimentView: View {
    @AppStorage(Constants.AppStorageKey.agentRootDirectoryPath) private var agentRootDirectoryPath = Constants.defaultAgentRootDirectoryPath
    @AppStorage(Constants.AppStorageKey.ideaDirectoryPath) private var legacyIdeaDirectoryPath = ""
    @AppStorage(Constants.AppStorageKey.outputDirectoryPath) private var legacyOutputDirectoryPath = ""
    @AppStorage(Constants.AppStorageKey.interestKeywords) private var interestKeywords = Constants.defaultInterestKeywords
    @AppStorage(Constants.AppStorageKey.selectedAgentType) private var selectedAgentType = Constants.defaultAgentType
    @AppStorage(Constants.AppStorageKey.planDayCount) private var planDayCount = Constants.defaultPlanDayCount

    @State private var statusMessage: String = ""
    @State private var hoveredAgentType: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.horizontal.circle")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(PopoverChrome.accent)
                    Text("Agent 실험")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.ink)
                    Spacer()
                    Image("FocusOnTransparent")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .shadow(color: PopoverChrome.accent.opacity(0.22), radius: 8, x: 0, y: 3)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("관심사 키워드")
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.inkTertiary)
                    if interestKeywordTags.isEmpty {
                        Text("등록된 관심사 없음")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(PopoverChrome.inkTertiary)
                    } else {
                        interestKeywordChips
                    }
                }

                Text("관심사는 설정창에서 수정할 수 있어요.")
                    .font(.caption2)
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .padding(.top, -10)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Agent")
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.inkTertiary)
                    agentSelector
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("계획 일수")
                            .font(.caption)
                            .foregroundStyle(PopoverChrome.inkTertiary)
                        Text("\(planDayCount)일")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(PopoverChrome.ink)
                    }
                    Spacer()
                    Stepper("", value: $planDayCount, in: 1...30)
                        .labelsHidden()
                }
                .popoverCard()

                HStack(spacing: 8) {
                    Button {
                        runPlanGeneration()
                    } label: {
                        Label("계획 생성", systemImage: "sparkles")
                    }
                    .buttonStyle(LanternPrimaryButtonStyle())
                    .frame(maxWidth: .infinity)

                    Button {
                        runTodayExperiment()
                    } label: {
                        Label("오늘 실험 실행", systemImage: "play.fill")
                    }
                    .buttonStyle(LanternSecondaryButtonStyle())
                    .frame(maxWidth: .infinity)
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .popoverCard(padding: 10)
                }
            }
            .padding(.trailing, 12)
        }
        .onAppear {
            applyDefaultAgentRootIfNeeded()
            if !Constants.availableAgentTypes.contains(selectedAgentType) {
                selectedAgentType = Constants.defaultAgentType
            }
        }
    }

    private var interestKeywordChips: some View {
        FlowLayout(spacing: 6) {
            ForEach(interestKeywordTags, id: \.self) { keyword in
                Text(keyword)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(PopoverChrome.surfaceAlt, in: Capsule())
                    .overlay(Capsule().stroke(PopoverChrome.divider, lineWidth: 1))
            }
        }
    }

    private var agentSelector: some View {
        HStack(spacing: 6) {
            ForEach(Constants.availableAgentTypes, id: \.self) { agent in
                Button {
                    selectedAgentType = agent
                } label: {
                    Text(agent)
                        .font(.system(size: 12.5, weight: selectedAgentType == agent ? .bold : .medium, design: .rounded))
                        .foregroundStyle(selectedAgentType == agent ? PopoverChrome.accentInk : PopoverChrome.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(agentTypeFill(for: agent))
                        )
                        .shadow(color: selectedAgentType == agent ? PopoverChrome.accent.opacity(0.28) : .clear, radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .onHover { isHovering in
                    hoveredAgentType = isHovering ? agent : nil
                }
            }
        }
        .padding(4)
        .background(PopoverChrome.surfaceAlt.opacity(0.82), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func agentTypeFill(for agent: String) -> Color {
        if selectedAgentType == agent {
            return PopoverChrome.accent
        }
        if hoveredAgentType == agent {
            return PopoverChrome.card
        }
        return .clear
    }

    private var trimmedInterestKeywords: String {
        interestKeywords.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasInterestKeywords: Bool {
        !trimmedInterestKeywords.isEmpty
    }

    private var interestKeywordTags: [String] {
        trimmedInterestKeywords
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var normalizedAgentRootDirectory: String {
        agentRootDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var ideaDirectoryPath: String {
        Constants.agentIdeaDirectoryPath(for: normalizedAgentRootDirectory)
    }

    private var outputDirectoryPath: String {
        Constants.agentOutputDirectoryPath(for: normalizedAgentRootDirectory)
    }

    private func applyDefaultAgentRootIfNeeded() {
        if UserDefaults.standard.object(forKey: Constants.AppStorageKey.agentRootDirectoryPath) == nil,
           let migratedRoot = legacyAgentRootDirectory() {
            agentRootDirectoryPath = migratedRoot
            return
        }

        if agentRootDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            agentRootDirectoryPath = Constants.defaultAgentRootDirectoryPath
        }
    }

    private func legacyAgentRootDirectory() -> String? {
        let idea = legacyIdeaDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let output = legacyOutputDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !idea.isEmpty, idea == output { return idea }
        if !output.isEmpty { return output }
        if !idea.isEmpty { return idea }
        return nil
    }

    private func runPlanGeneration() {
        do {
            applyDefaultAgentRootIfNeeded()

            let request = AgentPlanRequest(
                ideaDirectoryPath: ideaDirectoryPath,
                outputDirectoryPath: outputDirectoryPath,
                interestKeywords: interestKeywords,
                agentName: selectedAgentType,
                dayCount: planDayCount
            )

            let result = try AgentPlanLauncher.launch(request: request)
            statusMessage = "터미널에서 \(selectedAgentType) 실행 시작. 출력 예정: \(result.outputFileName)"
            ToastPanel.shared.show(
                icon: "🚀",
                title: "계획 생성 시작",
                subtitle: "\(selectedAgentType) 실행 커맨드를 터미널로 전달했습니다."
            )
        } catch {
            statusMessage = "실패: \(error.localizedDescription)"
            ToastPanel.shared.show(
                icon: "⚠️",
                title: "계획 생성 실패",
                subtitle: error.localizedDescription
            )
        }
    }

    private func runTodayExperiment() {
        do {
            applyDefaultAgentRootIfNeeded()

            let request = TodayExperimentRequest(
                outputDirectoryPath: outputDirectoryPath,
                interestKeywords: interestKeywords,
                agentName: selectedAgentType
            )

            let result = try AgentPlanLauncher.runTodayExperiment(request: request)
            statusMessage = "터미널에서 오늘 실험 실행 시작: \(result.planFileName)"
            ToastPanel.shared.show(
                icon: "🧪",
                title: "오늘 실험 실행 시작",
                subtitle: "\(selectedAgentType) 실행 커맨드를 터미널로 전달했습니다."
            )
        } catch {
            statusMessage = "실패: \(error.localizedDescription)"
            ToastPanel.shared.show(
                icon: "⚠️",
                title: "오늘 실험 실행 실패",
                subtitle: error.localizedDescription
            )
        }
    }
}

private struct AgentPlanRequest {
    let ideaDirectoryPath: String
    let outputDirectoryPath: String
    let interestKeywords: String
    let agentName: String
    let dayCount: Int
}

private struct AgentPlanLaunchResult {
    let outputFileName: String
}

private struct TodayExperimentRequest {
    let outputDirectoryPath: String
    let interestKeywords: String
    let agentName: String
}

private struct TodayExperimentRunResult {
    let planFileName: String
}

private enum AgentPlanLaunchError: LocalizedError {
    case invalidDirectory(String)
    case unsupportedAgent(String)
    case scriptExecutionFailed(String)
    case planFileNotFound(String)
    case todaySectionNotFound(String)
    case fileReadFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidDirectory(let path):
            return "경로를 확인하세요: \(path)"
        case .unsupportedAgent(let agent):
            return "지원하지 않는 Agent입니다: \(agent)"
        case .scriptExecutionFailed(let message):
            return "터미널 실행 실패: \(message)"
        case .planFileNotFound(let directory):
            return "계획 파일을 찾을 수 없습니다: \(directory)"
        case .todaySectionNotFound(let file):
            return "오늘 날짜 섹션을 찾을 수 없습니다: \(file)"
        case .fileReadFailed(let file):
            return "파일 읽기 실패: \(file)"
        }
    }
}

private enum AgentPlanLauncher {
    static func launch(request: AgentPlanRequest) throws -> AgentPlanLaunchResult {
        let ideaDir = request.ideaDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let outputDir = request.outputDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ideaDir.isEmpty else { throw AgentPlanLaunchError.invalidDirectory("아이디어 폴더가 비어 있습니다.") }
        guard !outputDir.isEmpty else { throw AgentPlanLaunchError.invalidDirectory("출력 폴더가 비어 있습니다.") }
        try FileManager.default.createDirectory(atPath: ideaDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: ideaDir) else { throw AgentPlanLaunchError.invalidDirectory(ideaDir) }
        guard FileManager.default.fileExists(atPath: outputDir) else { throw AgentPlanLaunchError.invalidDirectory(outputDir) }

        let fileName = makeOutputFileName(dayCount: request.dayCount)
        let outputFilePath = outputDir + "/" + fileName
        let prompt = makePrompt(
            ideaDirectoryPath: ideaDir,
            outputFilePath: outputFilePath,
            interestKeywords: request.interestKeywords,
            agentName: request.agentName,
            dayCount: request.dayCount
        )
        let agentCommand = try buildAgentCommand(agentName: request.agentName, prompt: prompt)
        let shellCommand = "cd \(shellQuote(ideaDir)); mkdir -p \(shellQuote(outputDir)); \(agentCommand)"
        try runTerminalCommand(shellCommand)

        return AgentPlanLaunchResult(outputFileName: fileName)
    }

    static func runTodayExperiment(request: TodayExperimentRequest) throws -> TodayExperimentRunResult {
        let outputDir = request.outputDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !outputDir.isEmpty else { throw AgentPlanLaunchError.invalidDirectory("출력 폴더가 비어 있습니다.") }
        try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: outputDir) else { throw AgentPlanLaunchError.invalidDirectory(outputDir) }

        let today = isoDateString(Date())
        let planFileURL = try resolvePlanFileURL(directory: outputDir, today: today)
        let content = try String(contentsOf: planFileURL, encoding: .utf8)
        let todaySection = try extractTodaySection(content: content, today: today, fileName: planFileURL.lastPathComponent)

        let keywords = request.interestKeywords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Constants.defaultInterestKeywords
            : request.interestKeywords
        let prompt = """
        아래는 오늘 실험 계획입니다.
        이 계획을 바로 실행 시작할 수 있도록:
        1) 지금 바로 할 첫 액션 3개
        2) 실행 체크리스트
        3) 결과 기록 방식(한줄 회고/개선점 작성 가이드)
        를 제시하고 진행하세요.

        관심사 키워드: \(keywords)
        오늘 날짜: \(today)

        [오늘 계획 섹션]
        \(todaySection)
        """

        let agentCommand = try buildAgentCommand(agentName: request.agentName, prompt: prompt)
        let shellCommand = "cd \(shellQuote(outputDir)); \(agentCommand)"
        try runTerminalCommand(shellCommand)

        return TodayExperimentRunResult(planFileName: planFileURL.lastPathComponent)
    }

    private static func buildAgentCommand(agentName: String, prompt: String) throws -> String {
        switch agentName {
        case "Codex":
            return "codex \(shellQuote(prompt))"
        case "Claude":
            return "claude \(shellQuote(prompt))"
        case "Gemini":
            return "gemini \(shellQuote(prompt))"
        default:
            throw AgentPlanLaunchError.unsupportedAgent(agentName)
        }
    }

    private static func runTerminalCommand(_ command: String) throws {
        let appleScriptCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", "tell application \"Terminal\" to activate",
            "-e", "tell application \"Terminal\" to do script \"\(appleScriptCommand)\"",
        ]

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                throw AgentPlanLaunchError.scriptExecutionFailed("종료 코드 \(process.terminationStatus)")
            }
        } catch {
            throw AgentPlanLaunchError.scriptExecutionFailed(error.localizedDescription)
        }
    }

    private static func makeOutputFileName(dayCount: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: Date())
        return "\(dateString)_experiment_plan_\(dayCount)d.md"
    }

    private static func makePrompt(
        ideaDirectoryPath: String,
        outputFilePath: String,
        interestKeywords: String,
        agentName: String,
        dayCount: Int
    ) -> String {
        let keywords = interestKeywords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Constants.defaultInterestKeywords
            : interestKeywords
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd (EEE)"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        let today = Date()
        let dayLines = (0..<dayCount).compactMap { offset -> String? in
            guard let date = Calendar.current.date(byAdding: .day, value: offset, to: today) else { return nil }
            return "- \(dateFormatter.string(from: date))"
        }.joined(separator: "\n")

        return """
        다음 요구사항으로 오늘 기준 \(dayCount)일치 실험 계획 markdown 파일을 생성하세요.
        - 기준 시작일은 오늘입니다.
        - 연속된 날짜로 \(dayCount)일 분량을 작성하세요.
        - 포함할 날짜 목록:
        \(dayLines)
        - 아이디어 참고 폴더: \(ideaDirectoryPath)
        - 관심사 키워드: \(keywords)
        - 출력 파일 경로: \(outputFilePath)
        - 반드시 출력 파일에 직접 저장하고, 완료 후 저장한 경로를 한 줄로 출력하세요.
        - 아래 템플릿 형식을 최대한 그대로 따르세요(항목명/순서/마크다운 스타일 유지).
        - 각 Day 섹션 제목은 실험 주제를 짧게 붙이세요.
        - 형식:
          # \(dayCount)일 실험 계획
          생성일: YYYY-MM-DD
          관심사: \(keywords)
          Agent: \(agentName)

          ## Day 1 (토) - 개인 작업 흐름의 반복 단계 자동화 후보 탐색
          > 날짜: YYYY-MM-DD

          - [ ] 완료
          **목표**: ...
          **작업**: ...
          **산출물**: ...
          **세부 실행 단계**: ...
          **검증 기준**: ...
          **리스크/대응**: ...
          `한줄 회고`:
          `개선점`:

        - Day 2부터 Day N까지도 동일 포맷 반복
        - 요일 표기는 한국어 한 글자(월/화/수/목/금/토/일)로 작성
        - `세부 실행 단계`, `검증 기준`, `리스크/대응`은 기존 형식을 깨지 않는 선에서 상세화를 위해 추가한 필수 항목입니다.
        """
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static func isoDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private static func resolvePlanFileURL(directory: String, today: String) throws -> URL {
        let directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw AgentPlanLaunchError.planFileNotFound(directory)
        }

        let mdFiles = files.filter { $0.pathExtension.lowercased() == "md" && $0.lastPathComponent.contains("_experiment_plan_") }
        guard !mdFiles.isEmpty else { throw AgentPlanLaunchError.planFileNotFound(directory) }

        let sorted = mdFiles.sorted {
            let lhsDate = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }

        if let todayPrefixed = sorted.first(where: { $0.lastPathComponent.hasPrefix("\(today)_experiment_plan_") }) {
            return todayPrefixed
        }

        for file in sorted {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            if content.contains("> 날짜: \(today)") { return file }
        }

        throw AgentPlanLaunchError.planFileNotFound(directory)
    }

    private static func extractTodaySection(content: String, today: String, fileName: String) throws -> String {
        let lines = content.components(separatedBy: .newlines)
        guard let dateLineIndex = lines.firstIndex(where: { $0.contains("> 날짜: \(today)") }) else {
            throw AgentPlanLaunchError.todaySectionNotFound(fileName)
        }

        var startIndex = dateLineIndex
        while startIndex > 0 {
            if lines[startIndex].hasPrefix("## Day ") { break }
            startIndex -= 1
        }

        var endIndex = lines.count
        var cursor = startIndex + 1
        while cursor < lines.count {
            if lines[cursor].hasPrefix("## Day ") {
                endIndex = cursor
                break
            }
            cursor += 1
        }

        let section = lines[startIndex..<endIndex].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !section.isEmpty else { throw AgentPlanLaunchError.fileReadFailed(fileName) }
        return section
    }
}
