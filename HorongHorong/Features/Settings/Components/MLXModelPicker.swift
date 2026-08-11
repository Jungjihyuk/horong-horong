import SwiftUI

/// MLX 모델 선택기. `OllamaModelPicker` 와 같은 카드 목록 형태로 맞춰
/// 설정 화면에서 공급자를 바꿔도 고르는 방식이 달라지지 않게 한다.
///
/// 받지 않은 모델은 Ollama 쪽처럼 행에서 바로 내려받고, 받아 둔 모델은 행에서 지운다.
/// 컴패니언 설정처럼 «모델 준비» 행을 따로 둔 화면은 진행률이 두 곳에 그려지지 않도록
/// `showsDownloadAction: false` 로 내려받기만 끈다 — 지우기는 그 행에 없으니 그대로 둔다.
struct MLXModelPicker: View {
    @Binding var model: String
    let options: [Constants.CompanionMLXModelOption]
    var isEnabled: Bool = true
    var showsDownloadAction: Bool = true
    var showsDeleteAction: Bool = true
    /// 지운 뒤 화면 밖의 준비 상태 표시를 다시 맞출 기회. 컴패니언 설정의 «모델 준비» 행이 쓴다.
    var onModelsChanged: () -> Void = {}

    @State private var downloadState = MLXModelState()
    /// 지금 받고 있거나 마지막으로 받은 모델. 진행 상황 문구가 어느 모델 것인지 밝히는 데 쓴다.
    @State private var downloadTarget: String?
    /// 지우기 확인을 기다리는 모델. 수 GB 를 되돌릴 수 없이 지우므로 한 번 물어본다.
    @State private var deletionTarget: Constants.CompanionMLXModelOption?
    /// 지운 뒤 남기는 안내. 이 값이 바뀌어야 «받음» 배지도 다시 그려진다.
    @State private var actionMessage: String?
    @State private var page = 0
    @State private var customModelInput = ""
    
    @State private var verifyTask: Task<Void, Never>?
    @State private var isVerifying = false
    @State private var verifiedModelExists = false

    private let modelsPerPage = 5

    private var memoryGB: Int {
        Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("사용 가능 후보")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("M칩 통합 메모리 \(memoryGB)GB 기준")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer()
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("모델 검색 또는 HuggingFace 레포지토리 입력 (예: mlx-community/Phi-3...)", text: $customModelInput)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .onChange(of: customModelInput) { _, newValue in
                        let query = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        verifyTask?.cancel()
                        if query.isEmpty {
                            verifiedModelExists = false
                            isVerifying = false
                            return
                        }
                        isVerifying = true
                        verifiedModelExists = false
                        verifyTask = Task {
                            do { try await Task.sleep(nanoseconds: 500_000_000) } catch { return }
                            if Task.isCancelled { return }
                            let exists = await checkModelExists(query)
                            if Task.isCancelled { return }
                            verifiedModelExists = exists
                            isVerifying = false
                        }
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))

            VStack(spacing: 6) {
                ForEach(pagedOptions) { option in
                    optionRow(option)
                }
            }

            if pageCount > 1 {
                pagination
            }

            if let actionMessage {
                statusText(actionMessage)
            } else {
                downloadStatus
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(!isEnabled)
        .confirmationDialog(
            "받아 둔 모델을 지울까요?",
            isPresented: Binding(
                get: { deletionTarget != nil },
                set: { isPresented in
                    if !isPresented { deletionTarget = nil }
                }
            ),
            presenting: deletionTarget
        ) { option in
            Button("지우기", role: .destructive) {
                Task { await delete(option) }
            }
            Button("취소", role: .cancel) {}
        } message: { option in
            Text(deletionMessage(for: option))
        }
        // 정체 판정은 «마지막으로 늘어난 시각» 과 지금을 견주므로, 시계를 밀어 줘야 다시 그려진다.
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            downloadState.tick()
        }
        .task {
            movePage(to: model)
        }
    }

    private var allOptions: [Constants.CompanionMLXModelOption] {
        var opts = options
        let hardcodedNames = Set(opts.map(\.name))
        
        let preparedModels = UserDefaults.standard.stringArray(forKey: Constants.AppStorageKey.companionMLXPreparedModels) ?? []
        let customInstalled = preparedModels.filter { !hardcodedNames.contains($0) }.sorted()
        
        for name in customInstalled {
            opts.append(
                Constants.CompanionMLXModelOption(
                    name: name,
                    label: name.components(separatedBy: "/").last ?? name,
                    detail: "사용자가 직접 설치한 커스텀 모델.",
                    minimumMemoryGB: 0
                )
            )
        }
        
        let query = customModelInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            opts = opts.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.label.localizedCaseInsensitiveContains(query) }
            
            if !opts.contains(where: { $0.name.lowercased() == query.lowercased() }) {
                let detail: String
                if isVerifying {
                    detail = "설치 가능 여부 확인 중..."
                } else if verifiedModelExists {
                    detail = "설치 가능한 커스텀 모델."
                } else {
                    detail = "HuggingFace에서 찾을 수 없거나 권한이 필요한 모델입니다."
                }

                opts.insert(
                    Constants.CompanionMLXModelOption(
                        name: query,
                        label: query.components(separatedBy: "/").last ?? query,
                        detail: detail,
                        minimumMemoryGB: 0
                    ),
                    at: 0
                )
            }
        }
        
        return opts
    }

    private var pagedOptions: [Constants.CompanionMLXModelOption] {
        let opts = allOptions
        let start = page * modelsPerPage
        guard start < opts.count else {
            return Array(opts.prefix(modelsPerPage))
        }
        let end = min(start + modelsPerPage, opts.count)
        return Array(opts[start..<end])
    }

    private var pageCount: Int {
        max(1, (allOptions.count + modelsPerPage - 1) / modelsPerPage)
    }

    private var pagination: some View {
        HStack(spacing: 6) {
            Text("\(page + 1) / \(pageCount)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)

            ForEach(0..<pageCount, id: \.self) { candidate in
                Button {
                    page = candidate
                } label: {
                    Text("\(candidate + 1)")
                        .font(.caption2.weight(.semibold))
                        .frame(width: 22, height: 22)
                        .background(
                            Circle()
                                .fill(candidate == page ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                        )
                        .overlay(
                            Circle()
                                .stroke(candidate == page ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.10), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(candidate == page ? Color.accentColor : Color.secondary)
                .help("\(candidate + 1)번째 모델 후보 페이지")
            }

            Spacer()
        }
        .padding(.top, 2)
    }

    private func movePage(to model: String) {
        let opts = allOptions
        guard let index = opts.firstIndex(where: { $0.name == model }) else {
            return
        }
        page = index / modelsPerPage
    }

    private func optionRow(_ option: Constants.CompanionMLXModelOption) -> some View {
        let isSelected = model == option.name
        let isPrepared = UserDefaults.standard.stringArray(forKey: Constants.AppStorageKey.companionMLXPreparedModels)?.contains(option.name) == true
        let isTooLarge = option.minimumMemoryGB > memoryGB
        let isCustomUnverified = !isPrepared && !options.contains(where: { $0.name == option.name }) && !verifiedModelExists && !isVerifying

        return HStack(spacing: 8) {
            Button {
                guard !isTooLarge else {
                    actionMessage = "메모리가 부족해 이 맥에서는 돌릴 수 없습니다."
                    return
                }
                model = option.name
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(option.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(option.name.replacingOccurrences(of: "mlx-community/", with: ""))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        badge(for: option, isTooLarge: isTooLarge, isPrepared: isPrepared)
                        Text("권장 RAM: \(option.minimumMemoryGB)GB+")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    }
                    Text(option.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .help("현재 선택된 모델")
            }

            if isPrepared {
                if showsDeleteAction {
                    deleteButton(for: option)
                }
            } else if showsDownloadAction, !isTooLarge {
                downloadButton(for: option)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.08),
                    lineWidth: 0.5
                )
        )
        .opacity(isTooLarge || isCustomUnverified ? 0.62 : 1)
    }

    private func downloadButton(for option: Constants.CompanionMLXModelOption) -> some View {
        let isDownloadingThis = isDownloading && downloadTarget == option.name
        let isPrepared = UserDefaults.standard.stringArray(forKey: Constants.AppStorageKey.companionMLXPreparedModels)?.contains(option.name) == true
        let isCustomUnverified = !isPrepared && !options.contains(where: { $0.name == option.name }) && !verifiedModelExists && !isVerifying

        return Button {
            Task {
                if isDownloadingThis {
                    await cancelDownload()
                } else {
                    await download(option.name)
                }
            }
        } label: {
            if isDownloadingThis {
                Image(systemName: "stop.circle")
                    .foregroundStyle(.orange)
            } else {
                Image(systemName: "arrow.down.circle")
            }
        }
        .buttonStyle(.borderless)
        .disabled(!MLXModelStore.isSupported || (isDownloading && !isDownloadingThis) || isCustomUnverified || isVerifying)
        .help(downloadButtonHelp(for: option, isDownloadingThis: isDownloadingThis))
    }

    private func downloadButtonHelp(
        for option: Constants.CompanionMLXModelOption,
        isDownloadingThis: Bool
    ) -> String {
        guard MLXModelStore.isSupported else {
            return "MLX 는 Apple Silicon 맥에서만 쓸 수 있습니다."
        }
        return isDownloadingThis ? "내려받기 중지" : "\(option.name) 내려받기"
    }

    private func deleteButton(for option: Constants.CompanionMLXModelOption) -> some View {
        Button {
            deletionTarget = option
        } label: {
            Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .disabled(isDownloading)
        .help("\(option.name) 지우기")
    }

    private func deletionMessage(for option: Constants.CompanionMLXModelOption) -> String {
        let sizeText = MLXModelStore.cachedWeightsSize(for: option.name)
            .map { " (\(ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)))" } ?? ""
        return "\(shortName(option.name)) 가중치\(sizeText)를 디스크에서 지웁니다. "
            + "다시 쓰려면 내려받아야 합니다."
    }

    /// 받는 중에는 진행률을, 멈추거나 실패했을 때는 이어받을 수 있다는 사실을 알린다.
    @ViewBuilder
    private var downloadStatus: some View {
        switch downloadState.phase {
        case .idle:
            EmptyView()
        case .preparing(let received, let total):
            VStack(alignment: .leading, spacing: 4) {
                statusText(preparingText(received: received, total: total))
                if total > 0 {
                    ProgressView(value: Double(received), total: Double(total))
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        case .paused(let received, let total):
            statusText(
                "\(targetName) 내려받기를 멈췄습니다 — \(Self.byteText(received, of: total)). "
                    + "다시 누르면 그 지점부터 이어받습니다."
            )
        case .ready:
            statusText("\(targetName) 준비됐습니다.")
        case .failed(let message):
            statusText("내려받지 못했습니다: \(message) — 다시 눌러도 받은 만큼은 이어받습니다.")
        }
    }

    private func statusText(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isDownloading: Bool {
        if case .preparing = downloadState.phase { return true }
        return false
    }

    private var targetName: String {
        shortName(downloadTarget ?? model)
    }

    private func shortName(_ name: String) -> String {
        name.replacingOccurrences(of: "mlx-community/", with: "")
    }

    /// 가중치를 지운다. 지우고 나면 배지가 «받음» 에서 «다운로드 필요» 로 돌아가고
    /// 같은 자리에 내려받기 버튼이 다시 나온다.
    private func delete(_ option: Constants.CompanionMLXModelOption) async {
        deletionTarget = nil
        do {
            try await MLXModelStore.shared.removeCachedWeights(for: option.name)
            downloadState.reset()
            actionMessage = "\(shortName(option.name)) 가중치를 지웠습니다."
            onModelsChanged()
        } catch {
            actionMessage = "지우지 못했습니다: \(error.localizedDescription)"
        }
    }

    /// 가중치를 내려받아 메모리에 올린다. 이미 받아 둔 모델이면 내려받지 않고 바로 끝난다.
    private func download(_ name: String) async {
        guard MLXModelStore.isSupported else { return }
        actionMessage = nil
        downloadTarget = name
        let state = downloadState
        // 이 표를 들고 있는 동안만 상태를 쓴다. 도중에 다른 모델을 받기 시작하면 표가 무효가 되어
        // 취소된 다운로드의 뒤늦은 콜백이 화면을 덮어쓰지 못한다.
        let token = state.begin()
        do {
            _ = try await MLXModelStore.shared.container(for: name) { progress in
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
    }

    /// 받는 중인 다운로드만 멈춘다. 받은 만큼은 디스크에 남아 다시 누르면 이어받는다.
    private func cancelDownload() async {
        await MLXModelStore.shared.cancelLoading()
    }

    /// 받는 동안 보여줄 문구. 속도와 남은 시간이 있어야 "멈춘 건지 느린 건지" 를 판단할 수 있고,
    /// 한동안 한 바이트도 안 늘면 그 사실을 그대로 알린다.
    private func preparingText(received: Int64, total: Int64) -> String {
        if downloadState.isStalled {
            return "\(targetName) — \(Self.byteText(received, of: total)) 에서 멈춘 것 같습니다. "
                + "네트워크를 확인해 주세요. 받은 만큼은 남아 있어 다시 받으면 이어받습니다."
        }
        var text = "\(targetName) 내려받는 중 — \(Self.byteText(received, of: total))"
        if let speed = downloadState.bytesPerSecond, speed > 0 {
            text += " · \(Self.speedText(speed))"
            if total > received {
                text += " · 약 \(Self.remainingText(seconds: Double(total - received) / speed)) 남음"
            }
        }
        return text
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

    private static func byteText(_ received: Int64, of total: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let receivedText = formatter.string(fromByteCount: received)
        guard total > 0 else { return receivedText }
        let percent = Int((Double(received) / Double(total) * 100).rounded())
        return "\(receivedText) / \(formatter.string(fromByteCount: total)) (\(percent)%)"
    }

    @ViewBuilder
    private func badge(
        for option: Constants.CompanionMLXModelOption,
        isTooLarge: Bool,
        isPrepared: Bool
    ) -> some View {
        if let kind = recommendationKind(for: option) {
            tag(kind.rawValue, foreground: recommendationForegroundColor(for: kind), background: recommendationBackgroundColor(for: kind))
        }
    }

    private func recommendationKind(for option: Constants.CompanionMLXModelOption) -> Constants.NewsOllamaRecommendationKind? {
        if option.minimumMemoryGB == 0 {
            return nil
        } else if option.minimumMemoryGB > memoryGB {
            return .unsupported
        } else if memoryGB - option.minimumMemoryGB < 8 {
            return .caution
        } else if memoryGB >= option.minimumMemoryGB * 3 {
            return .lightweight
        } else {
            return .primary
        }
    }

    private func tag(_ text: String, foreground: Color, background: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(background, in: RoundedRectangle(cornerRadius: 4))
    }

    private func recommendationBackgroundColor(for kind: Constants.NewsOllamaRecommendationKind) -> Color {
        switch kind {
        case .primary, .quality: return Color.accentColor.opacity(0.12)
        case .lightweight: return Color.green.opacity(0.15)
        case .caution: return Color.orange.opacity(0.15)
        case .unsupported: return Color.red.opacity(0.15)
        }
    }

    private func recommendationForegroundColor(for kind: Constants.NewsOllamaRecommendationKind) -> Color {
        switch kind {
        case .primary, .quality: return Color.accentColor
        case .lightweight: return Color.green
        case .caution: return Color.orange
        case .unsupported: return Color.red
        }
    }

    private func checkModelExists(_ name: String) async -> Bool {
        guard let url = URL(string: "https://huggingface.co/api/models/\(name)") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
        } catch {
            return false
        }
        return false
    }
}
