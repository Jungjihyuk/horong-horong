import SwiftUI

struct CompanionPage: View {
    @AppStorage(Constants.AppStorageKey.companionEnabled)
    private var isEnabled: Bool = Constants.defaultCompanionEnabled
    @AppStorage(Constants.AppStorageKey.companionSelectedIdentifier)
    private var selectedIdentifier: String = Constants.defaultCompanionIdentifier
    @AppStorage(Constants.AppStorageKey.companionRoamingRegion)
    private var roamingRegionRaw: String = ""
    @AppStorage(Constants.AppStorageKey.companionHideDuringFocus)
    private var hidesDuringFocus: Bool = Constants.defaultCompanionHideDuringFocus
    @AppStorage(Constants.AppStorageKey.companionBriefingEnabled)
    private var isBriefingEnabled: Bool = Constants.defaultCompanionBriefingEnabled
    @AppStorage(Constants.AppStorageKey.companionBriefingHour)
    private var briefingHour: Int = Constants.defaultCompanionBriefingHour
    @AppStorage(Constants.AppStorageKey.companionBriefingMinute)
    private var briefingMinute: Int = Constants.defaultCompanionBriefingMinute

    var body: some View {
        SettingsPageScroll {
            SettingsPageHeader(title: SettingsTab.companion.label, subtitle: SettingsTab.companion.subtitle)

            SettingsGroupCard("루미롱") {
                SettingsRow(
                    "루미롱 사용",
                    subtitle: "화면 위에 컴패니언을 띄웁니다. 투명 영역의 클릭은 아래 창으로 그대로 통과합니다."
                ) {
                    Toggle("", isOn: $isEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                SettingsRow(
                    "컴패니언",
                    subtitle: CompanionRegistry.character(for: selectedIdentifier).tagline
                ) {
                    Picker("", selection: $selectedIdentifier) {
                        ForEach(CompanionRegistry.all) { character in
                            Text(character.displayName).tag(character.id)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!isEnabled)
                }
            }

            SettingsGroupCard("활동") {
                SettingsRow(
                    "활동 영역",
                    subtitle: "지정한 사각형 안을 가로·세로로 자유롭게 돌아다닙니다. 지정하지 않으면 화면 전체를 씁니다."
                ) {
                    Text(CompanionRoamingRegion.description(for: roamingRegion))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Button("영역 지정…") {
                        CompanionRegionPicker.shared.begin { rect in
                            guard let rect else { return }
                            roamingRegionRaw = CompanionRoamingRegion.storageValue(for: rect)
                        }
                    }
                    .controlSize(.small)
                    .disabled(!isEnabled)

                    Button("화면 전체") {
                        roamingRegionRaw = ""
                    }
                    .controlSize(.small)
                    .disabled(!isEnabled || roamingRegion == nil)
                }

                SettingsRow(
                    "집중 중에는 숨기기",
                    subtitle: "포모도로 집중이 시작되면 사라지고, 쉬는 시간이나 세션이 끝나면 다시 나타납니다."
                ) {
                    Toggle("", isOn: $hidesDuringFocus)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(!isEnabled)
                }
            }

            SettingsGroupCard("일정 브리핑") {
                SettingsRow(
                    "오늘 일정 브리핑",
                    subtitle: "정해진 시각이 지난 뒤 컴패니언이 처음 나타날 때 오늘 할 일을 하루 한 번 알려줍니다."
                ) {
                    Toggle("", isOn: $isBriefingEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(!isEnabled)
                }

                SettingsRow(
                    "브리핑 시간",
                    subtitle: "집중 중이라면 집중이 끝난 뒤로 미뤄집니다."
                ) {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { briefingTime },
                            set: { updateBriefingTime($0) }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .datePickerStyle(.stepperField)
                    .fixedSize()
                    .disabled(!isEnabled || !isBriefingEnabled)
                }
            }

            SettingsGroupCard("AI 대화") {
                SettingsRow(
                    "대화 공급자",
                    subtitle: isLocalModelReady
                        ? "캐릭터를 클릭하면 이 모델과 대화합니다."
                        : "이 기기에서는 온디바이스 모델을 쓸 수 없어 고정 응답으로 답합니다. "
                            + "Apple Intelligence를 지원하는 기기와 macOS 26 이상이 필요합니다."
                ) {
                    Text(chatProviderName)
                        .font(.callout)
                        .foregroundStyle(isLocalModelReady ? .primary : .secondary)
                }

                SettingsRow(
                    "개인정보",
                    subtitle: "대화 내용과 추론은 이 기기 안에서만 처리되며 외부로 전송되지 않습니다."
                ) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                }
            }

            SettingsGroupCard("준비 중") {
                SettingsRow(
                    "음성 입력·출력",
                    subtitle: "말로 걸고 목소리로 답하는 기능은 이후에 제공될 예정입니다.",
                    comingSoon: true
                )
            }
        }
        .onAppear(perform: normalizeValues)
    }

    private var roamingRegion: CGRect? {
        CompanionRoamingRegion.rect(fromStorageValue: roamingRegionRaw)
    }

    private var chatProvider: CompanionChatProvider {
        CompanionChatProviderFactory.make()
    }

    private var chatProviderName: String { chatProvider.displayName }

    /// 고정 응답 공급자로 떨어졌는지 여부. 안내 문구를 바꾸는 데 쓴다.
    private var isLocalModelReady: Bool {
        !(chatProvider is ScriptedCompanionChatProvider)
    }

    private var briefingTime: Date {
        var components = DateComponents()
        components.hour = CompanionBriefingSchedule.normalizedHour(briefingHour)
        components.minute = CompanionBriefingSchedule.normalizedMinute(briefingMinute)
        return Calendar.current.date(from: components) ?? Date()
    }

    private func updateBriefingTime(_ date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        briefingHour = components.hour ?? Constants.defaultCompanionBriefingHour
        briefingMinute = components.minute ?? Constants.defaultCompanionBriefingMinute
    }

    private func normalizeValues() {
        briefingHour = CompanionBriefingSchedule.normalizedHour(briefingHour)
        briefingMinute = CompanionBriefingSchedule.normalizedMinute(briefingMinute)
    }
}
