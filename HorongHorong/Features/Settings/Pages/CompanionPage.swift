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
    @AppStorage(Constants.AppStorageKey.companionMLXModel)
    private var mlxModel: String = Constants.defaultCompanionMLXModel
    @AppStorage(Constants.AppStorageKey.companionBubbleSize)
    private var bubbleSize: String = Constants.defaultCompanionBubbleSize

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

                SettingsRow(
                    "말풍선 크기",
                    subtitle: Constants.CompanionBubbleSize(rawValue: bubbleSize)?.detail ?? ""
                ) {
                    Picker("", selection: $bubbleSize) {
                        ForEach(Constants.CompanionBubbleSize.allCases) { size in
                            Text(size.label).tag(size.rawValue)
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
                        + "여기 적은 것은 대화하는 내내 항상 적용됩니다. \"~할 때 ~라고 해줘\" 같은 조건부 지시는 "
                        + "조건과 무관하게 튀어나오므로, 집중이 흐트러졌을 때 해줄 말은 설정 → 몰입에 적어주세요.")
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
                            EmptyView()
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

                if chatProviderKind == Constants.CompanionChatProviderKind.ollama.rawValue,
                   isOllamaReachable {
                    OllamaModelPicker(
                        model: $ollamaModel,
                        endpoint: normalizedOllamaEndpoint,
                        dataBasePath: Constants.defaultNewsDataBasePath
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }

                if chatProviderKind == Constants.CompanionChatProviderKind.mlx.rawValue {
                    SettingsRow(
                        "MLX 를 쓰면 좋은 점",
                        subtitle: Self.mlxAdvantages
                    ) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.secondary)
                    }

                    // 카드 목록이라 SettingsRow 의 오른쪽 슬롯에 넣으면 잘린다. 전체 폭을 쓴다.
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("MLX 모델").font(.callout)
                            Text("늘 떠 있는 컴패니언이라 가벼운 쪽을 권합니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        MLXModelPicker(
                            model: $mlxModel,
                            options: Constants.availableCompanionMLXModelOptions,
                            isEnabled: isEnabled && isMLXSupported
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    // 내려받기는 모델 목록의 각 행이 맡는다. 여기서는 아예 못 쓰는 맥에만 그 사실을 알린다.
                    if !isMLXSupported {
                        SettingsRow(
                            "모델 준비",
                            subtitle: "이 맥에는 MLX 를 돌릴 Apple Silicon 칩이 없습니다. 다른 공급자를 골라 주세요."
                        ) {
                            Text("사용 불가")
                                .font(.callout)
                                .foregroundStyle(.secondary)
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
            guard newValue != oldValue else { return }
            if oldValue == Constants.CompanionChatProviderKind.ollama.rawValue {
                Task { await unloadOllamaModel(ollamaModel) }
            } else if newValue == Constants.CompanionChatProviderKind.ollama.rawValue,
                      !ollamaModel.isEmpty {
                Task { await OllamaChatClient.preload(endpoint: normalizedOllamaEndpoint, model: ollamaModel) }
            }
            // MLX 모델은 앱 메모리를 그대로 차지하므로, 공급자를 떠날 때 반드시 내린다.
            // 반대로 MLX 로 들어올 때 자동으로 내려받지는 않는다 — 수 GB 다운로드는
            // 화면을 둘러본 결과가 아니라 사용자가 누른 결과여야 한다.
            if oldValue == Constants.CompanionChatProviderKind.mlx.rawValue {
                Task { await unloadMLX() }
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
        // Ollama 와 같이, 모델을 바꾸면 이전 모델을 메모리에서 내리고 새 모델을 올린다.
        .onChange(of: mlxModel) { oldValue, newValue in
            guard chatProviderKind == Constants.CompanionChatProviderKind.mlx.rawValue,
                  oldValue != newValue else { return }
            Task { await switchMLXModel(to: newValue) }
        }
    }

    private func unloadOllamaModel(_ model: String) async {
        guard !model.isEmpty else { return }
        await OllamaChatClient.unload(endpoint: normalizedOllamaEndpoint, model: model)
    }

    private func unloadMLX() async {
        #if canImport(MLXLLM)
        await MLXModelStore.shared.unload()
        #endif
    }

    /// 고른 모델로 메모리를 갈아 끼운다. Ollama 모델을 바꿀 때와 같은 동작이다.
    ///
    /// 다만 **이미 받아 둔 모델일 때만** 올린다. MLX 는 올리는 것이 곧 내려받는 것이라,
    /// 목록을 눌러 보기만 해도 수 GB 가 받아지면 안 된다. 안 받은 모델을 고르면
    /// 이전 모델을 내리기만 하고, 내려받기는 사용자가 ⬇ 를 누를 때 시작한다.
    private func switchMLXModel(to model: String) async {
        #if canImport(MLXLLM)
        guard !model.isEmpty, MLXModelStore.isSupported else { return }
        guard MLXModelStore.isKnownPrepared(model) else {
            await MLXModelStore.shared.unload()
            return
        }
        // 이전 모델은 여기서 자동으로 내려간다 — 보관소가 한 번에 하나만 붙잡는다.
        _ = try? await MLXModelStore.shared.container(for: model)
        #endif
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

    /// 설정 화면에서 MLX 를 고를 때 무엇이 좋아지는지 그대로 읽어 알 수 있게 쓴다.
    private static let mlxAdvantages = """
    · 따로 깔 프로그램이 없습니다. 터미널을 열 일도, 서버를 켜 둘 일도 없습니다.
    · 모델을 한 번만 내려받으면 그 뒤로는 인터넷 없이도 대화할 수 있습니다.
    · 앱이 직접 돌려서 중간에 거치는 단계가 없어 답이 더 빨리 시작됩니다.
    · Apple 온디바이스 모델보다 큰 모델을 골라 쓸 수 있어 말귀를 더 잘 알아듣습니다.
    알아둘 점 — Apple Silicon 맥에서만 되고, 고른 모델 크기만큼 이 앱이 메모리를 씁니다.
    """

    private var isMLXSupported: Bool {
        #if canImport(MLXLLM)
        return MLXModelStore.isSupported
        #else
        return false
        #endif
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

/// MLX 모델의 준비 상태. `MLXModelStore` 는 actor 라 화면에서 바로 읽을 수 없어
/// 화면에 보여줄 값만 여기에 옮겨 둔다.
///
/// 옵셔널 세 개를 조합하지 않고 하나의 enum 으로 둔 이유는, 그래야 "받는 중인데 실패도 한"
/// 같은 있을 수 없는 상태가 애초에 표현되지 않기 때문이다.
@MainActor
@Observable
final class MLXModelState {
    enum Phase: Equatable {
        case idle
        case preparing(received: Int64, total: Int64)
        /// 사용자가 멈춘 상태. 받은 만큼은 디스크에 남아 있어 다시 시작하면 이어받는다.
        case paused(received: Int64, total: Int64)
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// 받은 양이 마지막으로 늘어난 시각. 이게 한동안 안 바뀌면 정체로 본다.
    private(set) var lastAdvance = Date()
    /// 초당 바이트. 직전 표본과 비교해 구한다.
    private(set) var bytesPerSecond: Double?

    /// 늦게 도착한 이전 요청의 콜백을 버리기 위한 표. 요청마다 하나씩 발급한다.
    private var sequence = 0
    private var sample: (at: Date, received: Int64)?
    /// 정체 문구를 다시 그리기 위한 시계. 값이 바뀌어야 뷰가 갱신된다.
    private(set) var now = Date()

    /// 15 초간 한 바이트도 안 늘면 멈춘 것으로 본다.
    var isStalled: Bool {
        guard case .preparing = phase else { return false }
        return now.timeIntervalSince(lastAdvance) > 15
    }

    /// 새 요청을 시작하고 표를 발급한다. 이 시점부터 이전 표는 무효다.
    func begin() -> Int {
        sequence += 1
        phase = .preparing(received: 0, total: 0)
        lastAdvance = Date()
        bytesPerSecond = nil
        sample = nil
        return sequence
    }

    func advance(_ token: Int, received: Int64, total: Int64) {
        guard token == sequence else { return }  // 취소된 옛 다운로드의 콜백은 버린다
        if case .preparing(let previous, _) = phase, received > previous {
            lastAdvance = Date()
            updateSpeed(received: received)
        }
        phase = .preparing(received: received, total: total)
    }

    func finish(_ token: Int, phase newPhase: Phase) {
        guard token == sequence else { return }
        phase = newPhase
        bytesPerSecond = nil
        sample = nil
    }

    /// 받던 자리를 기억한 채 멈춘다. 어디까지 왔는지 보여줘야 다시 누르기가 덜 불안하다.
    func pause(_ token: Int) {
        guard token == sequence, case .preparing(let received, let total) = phase else { return }
        phase = .paused(received: received, total: total)
        bytesPerSecond = nil
        sample = nil
    }

    /// 모델을 바꾸는 등 상태를 처음으로 되돌릴 때. 진행 중이던 요청의 표도 무효가 된다.
    func reset(to newPhase: Phase = .idle) {
        sequence += 1
        phase = newPhase
        bytesPerSecond = nil
        sample = nil
    }

    /// 정체 판정을 다시 계산하도록 시계를 민다.
    func tick() {
        guard case .preparing = phase else { return }
        now = Date()
    }

    private func updateSpeed(received: Int64) {
        let at = Date()
        defer { sample = (at, received) }
        guard let sample else { return }
        let seconds = at.timeIntervalSince(sample.at)
        guard seconds >= 1 else { return }
        bytesPerSecond = Double(received - sample.received) / seconds
    }
}
