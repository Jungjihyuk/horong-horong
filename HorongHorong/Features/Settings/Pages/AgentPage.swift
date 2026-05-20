import SwiftUI
import AppKit

struct AgentPage: View {
    @AppStorage(Constants.AppStorageKey.agentRootDirectoryPath)
    private var agentRootDirectoryPath: String = Constants.defaultAgentRootDirectoryPath
    @AppStorage(Constants.AppStorageKey.selectedAgentType)
    private var selectedAgentType: String = Constants.defaultAgentType
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

    // MARK: - 관심사 카드 (뉴스 탭과 값 공유)

    private var keywordCard: some View {
        SettingsGroupCard("관심사") {
            VStack(alignment: .leading, spacing: 10) {
                Text("관심사를 칩으로 관리하세요. 뉴스 탭과 같은 값을 공유합니다.")
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
