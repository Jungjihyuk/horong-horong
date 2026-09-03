import Foundation
import SwiftUI

/*
 팝오버 실험실 탭. 관심사 키워드·실행 Agent·계획 일수를 보여주고 실행을 시킨다.

 이 파일의 책임
 - 설정을 `AppStorage` 에 반영하고 화면에 보여준다.
 - 실행 결과를 상태 메시지와 토스트로 알린다.

 이 파일의 책임이 아닌 것
 - 터미널 실행·계획 파일 찾기는 `AgentGateway`(구현: `CLIAgentAdapter`)가 한다.
 - 프롬프트 문장과 계획 파일 파싱은 `Domain/Policies` 의 `AgentPrompt`·`ExperimentPlanText`.
 - 팝오버의 탭 전환·크기·공통 스타일은 `MenuBarPopover`.
 */
struct LabView: View {
    @AppStorage(Constants.AppStorageKey.agentRootDirectoryPath) private var agentRootDirectoryPath = Constants.defaultAgentRootDirectoryPath
    @AppStorage(Constants.AppStorageKey.ideaDirectoryPath) private var legacyIdeaDirectoryPath = ""
    @AppStorage(Constants.AppStorageKey.outputDirectoryPath) private var legacyOutputDirectoryPath = ""
    @AppStorage(Constants.AppStorageKey.interestKeywords) private var interestKeywords = Constants.defaultInterestKeywords
    @AppStorage(Constants.AppStorageKey.selectedAgentType) private var selectedAgentType = Constants.defaultAgentType
    @AppStorage(Constants.AppStorageKey.representativeAgentTypes) private var representativeAgentTypesRaw = Constants.defaultRepresentativeAgentTypesCSV
    @AppStorage(Constants.AppStorageKey.planDayCount) private var planDayCount = Constants.defaultPlanDayCount

    @State private var viewModel: LabViewModel
    @State private var hoveredAgentType: String?

    init(gateway: AgentGateway) {
        _viewModel = State(initialValue: LabViewModel(gateway: gateway))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.horizontal.circle")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(PopoverChrome.accent)
                    Text("실험실")
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
                    Text("실행 도구")
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

                if !viewModel.statusMessage.isEmpty {
                    Text(viewModel.statusMessage)
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

    /// 규칙은 `AgentRootPath` 에 있다. 여기서는 «한 번도 정한 적 없음»(`nil`)과
    /// «빈 값으로 정함»을 구분해 넘기는 일만 한다 — `@AppStorage` 로는 그 둘이 같아 보인다.
    private func applyDefaultAgentRootIfNeeded() {
        agentRootDirectoryPath = AgentRootPath.resolve(
            stored: UserDefaults.standard.object(forKey: Constants.AppStorageKey.agentRootDirectoryPath) as? String,
            legacyIdeaDirectory: legacyIdeaDirectoryPath,
            legacyOutputDirectory: legacyOutputDirectoryPath,
            fallback: Constants.defaultAgentRootDirectoryPath
        )
    }

    // MARK: - 실행

    /// 화면이 든 설정을 한 덩어리로 넘긴다. 뿌리 경로는 넘기기 직전에 확정한다 —
    /// 옛 버전 설정을 되살리는 경우가 있어서다.
    private var settings: LabSettings {
        LabSettings(
            agentRootDirectoryPath: normalizedAgentRootDirectory,
            interestKeywords: interestKeywords,
            agent: AgentKind(rawValue: selectedAgentType) ?? .codex,
            dayCount: planDayCount
        )
    }

    private func runPlanGeneration() {
        applyDefaultAgentRootIfNeeded()
        present(viewModel.generatePlan(settings), successIcon: "🚀", successTitle: "계획 생성 시작", failureTitle: "계획 생성 실패")
    }

    private func runTodayExperiment() {
        applyDefaultAgentRootIfNeeded()
        present(viewModel.runTodayExperiment(settings), successIcon: "🧪", successTitle: "오늘 실험 실행 시작", failureTitle: "오늘 실험 실행 실패")
    }

    private func present(
        _ outcome: LabOutcome,
        successIcon: String,
        successTitle: String,
        failureTitle: String
    ) {
        switch outcome {
        case .planStarted(_, let agent), .experimentStarted(_, let agent):
            ToastPanel.shared.show(
                icon: successIcon,
                title: successTitle,
                subtitle: "\(agent.rawValue) 실행 커맨드를 터미널로 전달했습니다."
            )
        case .failed(let message):
            ToastPanel.shared.show(icon: "⚠️", title: failureTitle, subtitle: message)
        }
    }
}
