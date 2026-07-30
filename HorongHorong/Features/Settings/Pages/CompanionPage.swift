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
    @AppStorage(Constants.AppStorageKey.companionUserNickname)
    private var userNickname: String = ""
    @AppStorage(Constants.AppStorageKey.companionUserNote)
    private var userNote: String = ""
    @AppStorage(Constants.AppStorageKey.companionChatProvider)
    private var chatProviderKind: String = Constants.defaultCompanionChatProvider
    @AppStorage(Constants.AppStorageKey.companionOllamaModel)
    private var ollamaModel: String = Constants.defaultCompanionOllamaModel
    @AppStorage(Constants.NewsStorageKey.ollamaEndpoint)
    private var ollamaEndpoint: String = Constants.defaultNewsOllamaEndpoint

    @State private var isOllamaReachable = false

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
            .companionHighlight("settings.companionBasics")


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
            .companionHighlight("settings.activity")


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
            .companionHighlight("settings.briefing")

            SettingsGroupCard("호로롱이 알아둘 것") {
                SettingsRow(
                    "부를 이름",
                    subtitle: "대화와 브리핑에서 이렇게 불러줍니다. 비워두면 부르지 않습니다."
                ) {
                    TextField("", text: $userNickname, prompt: Text("예: 지혁님"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .disabled(!isEnabled)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("알아줬으면 하는 것")
                        .font(.callout)
                    Text("대화할 때 참고할 배경을 적어주세요. 예: \"AI 엔지니어 취업 준비 중\", \"야근이 잦아요\"\n"
                        + "\"~할 때 ~라고 해줘\" 같은 조건부 지시는 아직 지켜지지 않습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TextEditor(text: $userNote)
                        .font(.system(size: 12))
                        .frame(height: 64)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(0.06))
                        )
                        .disabled(!isEnabled)

                    HStack {
                        Text("할일·집중 기록은 앱이 이미 알고 있어 여기에 적지 않아도 됩니다.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer(minLength: 8)
                        Text("\(userNote.count)/\(Constants.companionUserNoteMaxLength)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(
                                userNote.count > Constants.companionUserNoteMaxLength
                                    ? AnyShapeStyle(Color.red)
                                    : AnyShapeStyle(.tertiary)
                            )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .companionHighlight("settings.profile")


            SettingsGroupCard("AI 대화") {
                SettingsRow(
                    "모델",
                    subtitle: Constants.CompanionChatProviderKind(rawValue: chatProviderKind)?.detail ?? ""
                ) {
                    Picker("", selection: $chatProviderKind) {
                        ForEach(Constants.CompanionChatProviderKind.allCases) { kind in
                            Text(kind.label).tag(kind.rawValue)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!isEnabled)
                }

                if chatProviderKind == Constants.CompanionChatProviderKind.ollama.rawValue {
                    SettingsRow(
                        "Ollama 모델",
                        subtitle: isOllamaReachable
                            ? "설치된 모델은 체크 표시, 미설치 로컬 모델은 다운로드 버튼으로 표시합니다."
                            : "Ollama 서버에 연결하지 못했습니다. 터미널에서 ollama serve 로 켜주세요."
                    ) {
                        if isOllamaReachable {
                            OllamaModelPicker(
                                model: $ollamaModel,
                                endpoint: normalizedOllamaEndpoint,
                                dataBasePath: Constants.defaultNewsDataBasePath
                            )
                        } else {
                            Text("연결 안 됨")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Button("새로고침") {
                                Task { await refreshOllama() }
                            }
                            .controlSize(.small)
                        }
                    }
                }

                SettingsRow(
                    "현재 공급자",
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
            .companionHighlight("settings.chat")


            SettingsGroupCard("준비 중") {
                SettingsRow(
                    "음성 입력·출력",
                    subtitle: "말로 걸고 목소리로 답하는 기능은 이후에 제공될 예정입니다.",
                    comingSoon: true
                )
            }
        }
        .onAppear {
            normalizeValues()
            Task { await refreshOllama() }
        }
        .onChange(of: chatProviderKind) { oldValue, newValue in
            Task { await refreshOllama() }
            if oldValue == Constants.CompanionChatProviderKind.ollama.rawValue,
               newValue != oldValue {
                Task { await unloadOllamaModel(ollamaModel) }
            } else if newValue == Constants.CompanionChatProviderKind.ollama.rawValue,
                      newValue != oldValue, !ollamaModel.isEmpty {
                Task { await OllamaChatClient.preload(endpoint: normalizedOllamaEndpoint, model: ollamaModel) }
            }
        }
        .onChange(of: ollamaModel) { oldValue, newValue in
            guard chatProviderKind == Constants.CompanionChatProviderKind.ollama.rawValue,
                  oldValue != newValue else { return }
            if !oldValue.isEmpty {
                Task { await unloadOllamaModel(oldValue) }
            }
            if !newValue.isEmpty {
                Task { await OllamaChatClient.preload(endpoint: normalizedOllamaEndpoint, model: newValue) }
            }
        }
    }

    private func unloadOllamaModel(_ model: String) async {
        guard !model.isEmpty else { return }
        await OllamaChatClient.unload(endpoint: normalizedOllamaEndpoint, model: model)
    }

    private var roamingRegion: CGRect? {
        CompanionRoamingRegion.rect(fromStorageValue: roamingRegionRaw)
    }

    private var chatProvider: CompanionChatProvider {
        CompanionChatProviderFactory.make(ollamaReachable: isOllamaReachable)
    }

    /// 서버가 살아 있는지 확인한다. 설치된 모델 목록은 OllamaModelPicker 가 직접 확인한다.
    private func refreshOllama() async {
        guard chatProviderKind == Constants.CompanionChatProviderKind.ollama.rawValue else {
            isOllamaReachable = false
            return
        }
        isOllamaReachable = await OllamaChatClient.isReachable(endpoint: ollamaEndpoint)
    }

    private var normalizedOllamaEndpoint: String {
        let trimmed = ollamaEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Constants.defaultNewsOllamaEndpoint : trimmed
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

        let profile = CompanionUserProfile.normalized(nickname: userNickname, note: userNote)
        if profile.nickname != userNickname { userNickname = profile.nickname }
        if profile.note != userNote { userNote = profile.note }
    }
}
