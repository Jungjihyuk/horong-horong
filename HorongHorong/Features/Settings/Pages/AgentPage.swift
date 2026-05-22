import SwiftUI
import AppKit

struct AgentPage: View {
    @AppStorage(Constants.AppStorageKey.agentRootDirectoryPath)
    private var agentRootDirectoryPath: String = Constants.defaultAgentRootDirectoryPath
    @AppStorage(Constants.AppStorageKey.selectedAgentType)
    private var selectedAgentType: String = Constants.defaultAgentType
    @AppStorage(Constants.AppStorageKey.representativeAgentTypes)
    private var representativeAgentTypesRaw: String = Constants.defaultRepresentativeAgentTypesCSV
    @AppStorage(Constants.AppStorageKey.planDayCount)
    private var planDayCount: Int = Constants.defaultPlanDayCount
    @AppStorage(Constants.AppStorageKey.interestKeywords)
    private var interestKeywords: String = Constants.defaultInterestKeywords

    @State private var agentConfirm: Bool = true
    @State private var newKeyword: String = ""

    var body: some View {
        SettingsPageScroll {
            SettingsPageHeader(title: SettingsTab.agent.label, subtitle: SettingsTab.agent.subtitle)

            SettingsGroupCard("실행 환경") {
                SettingsRow(
                    "실험 루트 폴더",
                    subtitle: "ideas, outputs 하위 폴더가 자동으로 만들어집니다."
                ) {
                    HStack(spacing: 4) {
                        Text(agentRootDirectoryPath.isEmpty ? Constants.defaultAgentRootDirectoryPath : agentRootDirectoryPath)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 260, alignment: .trailing)
                        Button {
                            if let selected = selectDirectory() {
                                agentRootDirectoryPath = selected
                            }
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.bordered)
                        .help("폴더 변경")
                    }
                }
                SettingsRow(
                    "기본 Agent",
                    subtitle: "계획 생성·실행에 사용할 CLI."
                ) {
                    Picker("", selection: $selectedAgentType) {
                        ForEach(Constants.availableAgentTypes, id: \.self) { agent in
                            Text(agent).tag(agent)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
                SettingsRow(
                    "빠른 선택 Agent",
                    subtitle: "Agent 탭 버튼에 표시할 Agent를 최대 3개까지 고릅니다."
                ) {
                    FlowLayout(spacing: 6) {
                        ForEach(Constants.availableAgentTypes, id: \.self) { agent in
                            Button {
                                toggleRepresentativeAgent(agent)
                            } label: {
                                Text(agent)
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .tint(representativeAgentTypes.contains(agent) ? .accentColor : .secondary)
                            .disabled(!representativeAgentTypes.contains(agent) && representativeAgentTypes.count >= Constants.maxRepresentativeAgentCount)
                        }
                    }
                    .frame(maxWidth: 310, alignment: .trailing)
                }
                SettingsRow(
                    "계획 일수",
                    subtitle: "한 번에 생성할 실험 계획의 일수."
                ) {
                    Stepper("\(planDayCount)일", value: $planDayCount, in: 1...30)
                        .labelsHidden()
                    Text("\(planDayCount)일")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }

            keywordCard

            SettingsGroupCard("안전장치") {
                SettingsRow(
                    "터미널 명령 실행 전 확인",
                    subtitle: "Agent CLI 호출 전 사용자 확인을 받습니다.",
                    comingSoon: true
                ) {
                    Toggle("", isOn: $agentConfirm).labelsHidden()
                }
            }
        }
    }

    // MARK: - 관심사 카드 (뉴스 탭과 *별개*로 저장)

    private var keywordCard: some View {
        SettingsGroupCard("관심사") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Agent 실험 계획에 쓰일 관심사를 칩으로 관리하세요. 뉴스 탭의 관심사와는 별개로 저장됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !keywords.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(keywords, id: \.self) { keyword in
                            KeywordChip(label: keyword) {
                                removeKeyword(keyword)
                            }
                        }
                    }
                }

                HStack(spacing: 6) {
                    TextField("새 키워드 입력 후 Enter", text: $newKeyword)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addKeyword)
                    Button("추가", action: addKeyword)
                        .buttonStyle(.borderedProminent)
                        .disabled(trimmedNewKeyword.isEmpty)
                }
            }
            .padding(14)
        }
    }

    private var keywords: [String] {
        interestKeywords.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var trimmedNewKeyword: String {
        newKeyword.trimmingCharacters(in: .whitespaces)
    }

    private var representativeAgentTypes: [String] {
        Constants.normalizedRepresentativeAgentTypes(from: representativeAgentTypesRaw)
    }

    private func toggleRepresentativeAgent(_ agent: String) {
        var agents = representativeAgentTypes
        if agents.contains(agent) {
            agents.removeAll { $0 == agent }
        } else if agents.count < Constants.maxRepresentativeAgentCount {
            agents.append(agent)
        }
        representativeAgentTypesRaw = agents.joined(separator: ",")
    }

    private func addKeyword() {
        let kw = trimmedNewKeyword
        guard !kw.isEmpty, !keywords.contains(kw) else {
            newKeyword = ""
            return
        }
        var current = keywords
        current.append(kw)
        interestKeywords = current.joined(separator: ", ")
        newKeyword = ""
    }

    private func removeKeyword(_ keyword: String) {
        var current = keywords
        current.removeAll { $0 == keyword }
        interestKeywords = current.joined(separator: ", ")
    }

    private func selectDirectory() -> String? {
        let panel = NSOpenPanel()
        panel.prompt = "선택"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
