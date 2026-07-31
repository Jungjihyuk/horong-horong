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

    @State private var isOllamaReachable = false
    @State private var mlxState = MLXModelState()

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

                if chatProviderKind == Constants.CompanionChatProviderKind.mlx.rawValue {
                    SettingsRow(
                        "MLX 를 쓰면 좋은 점",
                        subtitle: Self.mlxAdvantages
                    ) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.secondary)
                    }

                    SettingsRow(
                        "MLX 모델",
                        subtitle: selectedMLXOption.map {
                            "\($0.detail) 권장 메모리: \($0.minimumMemoryGB)GB+."
                        } ?? ""
                    ) {
                        Picker("", selection: $mlxModel) {
                            ForEach(Constants.availableCompanionMLXModelOptions) { option in
                                Text(option.label).tag(option.name)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .disabled(!isEnabled || !isMLXSupported)
                    }

                    SettingsRow("모델 준비", subtitle: mlxPreparationSubtitle) {
                        if !isMLXSupported {
                            Text("사용 불가")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            switch mlxState.phase {
                            case .preparing(let received, let total):
                                ProgressView(value: total > 0 ? Double(received) / Double(total) : 0)
                                    .progressViewStyle(.linear)
                                    .frame(width: 120)
                                Button("중지") {
                                    Task { await cancelMLXDownload() }
                                }
                                .controlSize(.small)
                            case .paused:
                                Button("이어받기") {
                                    Task { await prepareMLX(mlxModel) }
                                }
                                .controlSize(.small)
                            case .ready:
                                Label("준비됨", systemImage: "checkmark.circle.fill")
                                    .font(.callout)
                                    .foregroundStyle(.green)
                            case .idle:
                                Button("내려받기") {
                                    Task { await prepareMLX(mlxModel) }
                                }
                                .controlSize(.small)
                            case .failed:
                                Button("다시 시도") {
                                    Task { await prepareMLX(mlxModel) }
                                }
                                .controlSize(.small)
                            }
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
            Task { await refreshMLXResidency() }
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
            } else if newValue == Constants.CompanionChatProviderKind.mlx.rawValue {
                Task { await refreshMLXResidency() }
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
        // 모델을 고르는 것은 고르는 것일 뿐이다. 내려받기는 사용자가 버튼을 눌러야 시작한다.
        // (예전에는 여기서 바로 받기 시작해서, 둘러보기만 해도 다운로드가 걸리고
        //  이전 다운로드와 경합해 진행률이 엉뚱한 모델 것을 그리는 문제가 있었다.)
        .onChange(of: mlxModel) { oldValue, newValue in
            guard oldValue != newValue else { return }
            mlxState.reset()
            Task { await refreshMLXResidency() }
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            mlxState.tick()
        }
    }

    private func unloadOllamaModel(_ model: String) async {
        guard !model.isEmpty else { return }
        await OllamaChatClient.unload(endpoint: normalizedOllamaEndpoint, model: model)
    }

    /// 이전 모델을 내리고 고른 모델을 메모리에 올린다. 처음 쓰는 모델이면 여기서 내려받는다.
    private func prepareMLX(_ model: String) async {
        #if canImport(MLXLLM)
        guard !model.isEmpty, MLXModelStore.isSupported else { return }
        let state = mlxState
        // 이 표를 들고 있는 동안만 상태를 쓴다. 도중에 모델이 바뀌면 표가 무효가 되어
        // 취소된 다운로드의 뒤늦은 콜백이 화면을 덮어쓰지 못한다.
        let token = state.begin()
        do {
            _ = try await MLXModelStore.shared.container(for: model) { progress in
                Task { @MainActor in
                    state.advance(token, received: progress.received, total: progress.total)
                }
            }
            state.finish(token, phase: .ready)
        } catch is CancellationError {
            state.pause(token)   // 사용자가 멈춘 것이지 실패가 아니다
        } catch let error as URLError where error.code == .cancelled {
            // URLSession 은 취소를 CancellationError 가 아니라 이 코드로 알린다.
            state.pause(token)
        } catch {
            state.finish(token, phase: .failed(error.localizedDescription))
        }
        #endif
    }

    /// 받는 중인 다운로드만 멈춘다. 받은 만큼은 남아 있어 «이어받기» 로 되돌아온다.
    private func cancelMLXDownload() async {
        #if canImport(MLXLLM)
        await MLXModelStore.shared.cancelLoading()
        #endif
    }

    private func unloadMLX() async {
        #if canImport(MLXLLM)
        await MLXModelStore.shared.unload()
        mlxState.reset()
        #endif
    }

    /// 화면을 다시 열었을 때 실제로 메모리에 올라와 있는 모델과 표시를 맞춘다.
    private func refreshMLXResidency() async {
        #if canImport(MLXLLM)
        guard case .preparing = mlxState.phase else {
            let resident = await MLXModelStore.shared.residentModel
            mlxState.reset(to: resident == mlxModel ? .ready : .idle)
            return
        }
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

    private var selectedMLXOption: Constants.CompanionMLXModelOption? {
        Constants.availableCompanionMLXModelOptions.first { $0.name == mlxModel }
    }

    private var mlxPreparationSubtitle: String {
        guard isMLXSupported else {
            return "이 맥에는 MLX 를 돌릴 Apple Silicon 칩이 없습니다. 다른 모델을 골라 주세요."
        }
        switch mlxState.phase {
        case .failed(let message):
            return "모델을 준비하지 못했습니다: \(message) — 다시 시도해도 받은 만큼은 이어받습니다."
        case .preparing(let received, let total):
            if mlxState.isStalled {
                return "\(Self.byteText(received, of: total)) 에서 멈춘 것 같습니다. "
                    + "네트워크를 확인해 주세요. 받은 만큼은 남아 있어 다시 시도하면 이어받습니다."
            }
            var text = "내려받는 중 — \(Self.byteText(received, of: total))"
            if let speed = mlxState.bytesPerSecond, speed > 0 {
                text += " · \(Self.speedText(speed))"
                if total > received {
                    text += " · 약 \(Self.remainingText(seconds: Double(total - received) / speed)) 남음"
                }
            }
            return text + ". 받는 동안 다른 작업을 해도 됩니다."
        case .paused(let received, let total):
            return "\(Self.byteText(received, of: total)) 에서 멈췄습니다. "
                + "받은 만큼은 남아 있어 이어받기를 누르면 그 지점부터 계속됩니다."
        case .ready:
            return "모델이 메모리에 올라와 있어 바로 답할 수 있습니다. 다른 공급자로 바꾸면 자동으로 내려갑니다."
        case .idle:
            return "아직 준비되지 않았습니다. 내려받기를 누르면 시작합니다. "
                + "이미 받아둔 모델이면 내려받지 않고 바로 준비됩니다."
        }
    }

    private static func byteText(_ received: Int64, of total: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let receivedText = formatter.string(fromByteCount: received)
        guard total > 0 else { return receivedText }
        let percent = Int((Double(received) / Double(total) * 100).rounded())
        return "\(receivedText) / \(formatter.string(fromByteCount: total)) (\(percent)%)"
    }

    private static func speedText(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
    }

    private static func remainingText(seconds: Double) -> String {
        seconds < 90
            ? "\(Int(seconds.rounded()))초"
            : "\(Int((seconds / 60).rounded()))분"
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
