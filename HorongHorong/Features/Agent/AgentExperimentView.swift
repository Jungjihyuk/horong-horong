import Foundation
import SwiftUI

/*
 팝오버 Agent 탭의 실험 설정 화면과 로컬 Agent 실행 연결을 담당한다.

 이 파일의 책임
 - 관심사 키워드·실행 Agent·계획 일수를 표시하고 `AppStorage` 설정에 반영한다.
 - 계획 생성과 오늘 실험 실행 요청을 만들고, 실행 결과를 상태 메시지와 토스트로 보여준다.
 - 실행 경로와 계획 파일을 확인하고, Agent별 터미널 명령을 구성해 전달한다.

 이 파일의 책임이 아닌 것
 - 팝오버의 탭 전환·크기·공통 화면 스타일은 `MenuBarPopover`가 담당한다.
 - 전달된 프롬프트를 해석하고 실제 작업을 수행하는 것은 선택된 외부 Agent가 담당한다.

 현재는 화면과 실행 보조 타입이 한 파일에 함께 있다. MVVM 전환 시 화면 상태와 사용자 입력은
 ViewModel로, 파일 시스템·터미널 실행은 Gateway 또는 Service로 옮기고 이 View에는 표현만 남긴다.
 */

struct AgentExperimentView: View {
    @AppStorage(Constants.AppStorageKey.agentRootDirectoryPath) private var agentRootDirectoryPath = Constants.defaultAgentRootDirectoryPath
    @AppStorage(Constants.AppStorageKey.ideaDirectoryPath) private var legacyIdeaDirectoryPath = ""
    @AppStorage(Constants.AppStorageKey.outputDirectoryPath) private var legacyOutputDirectoryPath = ""
    @AppStorage(Constants.AppStorageKey.interestKeywords) private var interestKeywords = Constants.defaultInterestKeywords
    @AppStorage(Constants.AppStorageKey.selectedAgentType) private var selectedAgentType = Constants.defaultAgentType
    @AppStorage(Constants.AppStorageKey.representativeAgentTypes) private var representativeAgentTypesRaw = Constants.defaultRepresentativeAgentTypesCSV
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
                    Image(PopoverChrome.focusOnImageName)
                        .resizable()
                        .interpolation(PopoverChrome.isGamePixel ? .none : .high)
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
                    planDayControl
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
                    .background(PopoverChrome.surfaceAlt, in: RoundedRectangle(cornerRadius: PopoverChrome.controlRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: PopoverChrome.controlRadius, style: .continuous)
                            .stroke(PopoverChrome.divider, lineWidth: 1)
                    )
            }
        }
    }

    private var planDayControl: some View {
        VStack(spacing: 0) {
            Button {
                updatePlanDayCount(by: 1)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 30, height: 15)
                    .contentShape(Rectangle())
            }
            .disabled(planDayCount >= 30)
            .help("계획 일수 늘리기")
            .contentShape(Rectangle())

            Rectangle()
                .fill(PopoverChrome.divider)
                .frame(width: 18, height: 1)

            Button {
                updatePlanDayCount(by: -1)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 30, height: 15)
                    .contentShape(Rectangle())
            }
            .disabled(planDayCount <= 1)
            .help("계획 일수 줄이기")
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(PopoverChrome.inkSecondary)
        .background(PopoverChrome.surfaceAlt.opacity(0.9), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous)
                .stroke(PopoverChrome.divider, lineWidth: PopoverChrome.borderWidth)
        )
    }

    private var agentSelector: some View {
        HStack(spacing: 6) {
            ForEach(representativeAgentTypes, id: \.self) { agent in
                Button {
                    selectedAgentType = agent
                } label: {
                    Text(agent)
                        .font(.system(size: 12.5, weight: selectedAgentType == agent ? .bold : .medium, design: .rounded))
                        .foregroundStyle(selectedAgentType == agent ? PopoverChrome.selectionInk : PopoverChrome.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous)
                                .fill(agentTypeFill(for: agent))
                        )
                        .shadow(
                            color: PopoverChrome.isGamePixel ? .clear : (selectedAgentType == agent ? PopoverChrome.accent.opacity(0.28) : .clear),
                            radius: PopoverChrome.isGamePixel ? 0 : 8,
                            x: 0,
                            y: PopoverChrome.isGamePixel ? 0 : 4
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .onHover { isHovering in
                    hoveredAgentType = isHovering ? agent : nil
                }
            }
        }
        .padding(4)
        .background(PopoverChrome.surfaceAlt.opacity(0.82), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(13), style: .continuous))
    }

    private var representativeAgentTypes: [String] {
        Constants.normalizedRepresentativeAgentTypes(from: representativeAgentTypesRaw)
    }

    private func updatePlanDayCount(by delta: Int) {
        planDayCount = min(30, max(1, planDayCount + delta))
    }

    private func agentTypeFill(for agent: String) -> Color {
        if selectedAgentType == agent {
            return PopoverChrome.selectionFill
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
        let workspaceDir = workspaceDirectoryPath(ideaDirectoryPath: ideaDir, outputDirectoryPath: outputDir)
        let shellCommand = "cd \(shellQuote(workspaceDir)); mkdir -p \(shellQuote(outputDir)); \(agentCommand)"
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
        let workspaceDir = parentDirectoryPath(for: outputDir)
        let shellCommand = "cd \(shellQuote(workspaceDir)); \(agentCommand)"
        try runTerminalCommand(shellCommand)

        return TodayExperimentRunResult(planFileName: planFileURL.lastPathComponent)
    }

    private static func buildAgentCommand(agentName: String, prompt: String) throws -> String {
        switch agentName {
        case "Codex":
            return "codex \(shellQuote(prompt))"
        case "Claude":
            return "claude \(shellQuote(prompt))"
        case "Antigravity":
            return "agy --prompt-interactive \(shellQuote(prompt))"
        case "Opencode":
            return "opencode run \(shellQuote(prompt))"
        case "Hermes":
            return "hermes chat send \(shellQuote(prompt))"
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

    private static func workspaceDirectoryPath(ideaDirectoryPath: String, outputDirectoryPath: String) -> String {
        let ideaParent = parentDirectoryPath(for: ideaDirectoryPath)
        let outputParent = parentDirectoryPath(for: outputDirectoryPath)
        return ideaParent == outputParent ? ideaParent : ideaDirectoryPath
    }

    private static func parentDirectoryPath(for path: String) -> String {
        URL(fileURLWithPath: path).deletingLastPathComponent().path
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
