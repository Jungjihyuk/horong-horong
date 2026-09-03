import SwiftUI

/// Ollama 모델 후보 목록 + 다운로드 UI. 뉴스·루미롱 설정에서 함께 쓴다.
struct OllamaModelPicker: View {
    @Binding var model: String
    let endpoint: String
    let dataBasePath: String

    /// 설치된 모델과 그 크기. 지우기 전에 얼마나 비는지 보여주려고 크기까지 들고 있는다.
    @State private var installedModels: [String: Int64] = [:]
    @State private var isLoading = false
    @State private var installingModel: String?
    @State private var installingStatus: String?
    @State private var installingProgress: Double?
    /// 지우기 확인을 기다리는 모델. 수 GB 를 되돌릴 수 없이 지우므로 한 번 물어본다.
    @State private var deletionTarget: Constants.NewsOllamaModelOption?
    @State private var actionMessage: String?
    @State private var page = 0
    @State private var customModelInput = ""
    
    @State private var verifyTask: Task<Void, Never>?
    @State private var isVerifying = false
    @State private var verifiedModelExists = false

    private let modelsPerPage = 5
    private let pipelineService = NewsPipelineService()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(isLoading ? "설치 목록 확인 중..." : "사용 가능 후보")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("M칩 통합 메모리 \(Constants.newsHardwareMemoryGB)GB 기준")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer()
                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(isLoading || installingModel != nil)
                .help("설치 상태 새로고침")
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("목록에 없는 로컬 모델 이름 입력 (예: llama3.1:70b)", text: $customModelInput)
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

            if let installingModel {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(installingModel) 준비 중")
                        .font(.caption.weight(.medium))
                    if let installingProgress {
                        ProgressView(value: installingProgress, total: 1.0)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                    if let installingStatus {
                        Text(installingStatus)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.top, 2)
            } else if let installingStatus {
                Text(installingStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            movePage(to: model)
            await refresh()
        }
        .onChange(of: endpoint) { _, _ in
            Task { await refresh() }
        }
        .confirmationDialog(
            "설치된 모델을 지울까요?",
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
    }

    private var allOptions: [Constants.NewsOllamaModelOption] {
        var options = Constants.availableNewsOllamaModelOptions
        let hardcodedNames = Set(options.map(\.name))
        
        let customInstalled = installedModels.keys
            // `latest` 는 같은 모델의 기본 태그 별칭이라, 버전·크기 태그와 함께 보이면 중복된다.
            .filter { !hardcodedNames.contains($0) && !$0.hasSuffix(":latest") }
            .sorted()
        
        for name in customInstalled {
            options.append(
                Constants.NewsOllamaModelOption(
                    name: name,
                    label: name,
                    detail: "사용자가 직접 설치한 커스텀 모델.",
                    availability: .local,
                    isRecommended: false
                )
            )
        }
        
        let query = customModelInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            options = options.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.label.localizedCaseInsensitiveContains(query) }
            
            if !options.contains(where: { $0.name.lowercased() == query.lowercased() }) {
                let detail: String
                if isVerifying {
                    detail = "설치 가능 여부 확인 중..."
                } else if verifiedModelExists {
                    detail = "설치 가능한 커스텀 모델."
                } else {
                    detail = "Ollama 레지스트리에서 찾을 수 없는 모델입니다."
                }

                options.insert(
                    Constants.NewsOllamaModelOption(
                        name: query,
                        label: query,
                        detail: detail,
                        availability: .local,
                        isRecommended: false
                    ),
                    at: 0
                )
            }
        }
        
        return options
    }

    private var pagedOptions: [Constants.NewsOllamaModelOption] {
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

    private func optionRow(_ option: Constants.NewsOllamaModelOption) -> some View {
        let isSelected = model == option.name
        let recommendationKind = Constants.newsOllamaRecommendationKinds()[option.name]
        let isUnsupported = recommendationKind == .unsupported
        let isCloud = option.availability == .cloud
        let isInstalled = isCloud || installedModels[option.name] != nil
        let isInstalling = installingModel == option.name
        let isCustomUnverified = !isInstalled && !Constants.availableNewsOllamaModelOptions.contains(where: { $0.name == option.name }) && !verifiedModelExists && !isVerifying

        let (desc, ramInfo) = formatOptionDetail(option.detail)

        return HStack(spacing: 8) {
            Button {
                guard !isUnsupported else {
                    installingStatus = "\(option.name)은 현재 RAM \(Constants.newsHardwareMemoryGB)GB 기준으로 로컬 실행을 권장하지 않습니다."
                    return
                }
                model = option.name
                if isCloud {
                    installingStatus = "클라우드 모델은 로컬 다운로드 없이 선택됩니다. Ollama 계정/클라우드 사용 가능 여부를 확인해주세요."
                }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(option.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(option.name)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        if let recommendationKind {
                            Text(recommendationKind.rawValue)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(recommendationForegroundColor(for: recommendationKind))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    recommendationBackgroundColor(for: recommendationKind),
                                    in: RoundedRectangle(cornerRadius: 4)
                                )
                        }
                        if let ramInfo {
                            Text(ramInfo)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    Text(desc)
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

            if isCloud {
                Image(systemName: "cloud")
                    .foregroundStyle(.secondary)
                    .help("Ollama 클라우드 모델")
            } else if isInstalled {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
                    .help("설치됨")
                Button {
                    deletionTarget = option
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(installingModel != nil)
                .help("\(option.name) 지우기")
            } else {
                Button {
                    Task {
                        if isInstalling {
                            await cancelInstall()
                        } else {
                            await install(option)
                        }
                    }
                } label: {
                    if isInstalling {
                        Image(systemName: "stop.circle")
                            .foregroundStyle(.orange)
                    } else {
                        Image(systemName: "arrow.down.circle")
                    }
                }
                .buttonStyle(.borderless)
                .disabled((installingModel != nil && !isInstalling) || isUnsupported || isCustomUnverified || isVerifying)
                .help(isUnsupported ? "현재 PC 사양에서는 권장하지 않음" : (isInstalling ? "\(option.name) 내려받기 취소" : "\(option.name) 다운로드"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .opacity(isUnsupported || isCustomUnverified ? 0.62 : 1)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func formatOptionDetail(_ detail: String) -> (String, String?) {
        if let range = detail.range(of: " 권장 RAM: ") {
            let desc = String(detail[..<range.lowerBound])
            let ram = String(detail[range.upperBound...])
            return (desc, "권장 RAM: " + ram)
        }
        return (detail, nil)
    }

    private func recommendationForegroundColor(for kind: Constants.NewsOllamaRecommendationKind) -> Color {
        switch kind {
        case .primary:
            return .white
        case .lightweight, .quality, .caution:
            return recommendationAccentColor(for: kind)
        case .unsupported:
            return .red
        }
    }

    private func recommendationBackgroundColor(for kind: Constants.NewsOllamaRecommendationKind) -> Color {
        switch kind {
        case .primary:
            return recommendationAccentColor(for: kind)
        case .lightweight, .quality, .caution:
            return recommendationAccentColor(for: kind).opacity(0.12)
        case .unsupported:
            return Color.red.opacity(0.12)
        }
    }

    private func recommendationAccentColor(for kind: Constants.NewsOllamaRecommendationKind) -> Color {
        switch kind {
        case .primary:
            return Color.accentColor
        case .lightweight:
            return .green
        case .quality:
            return .purple
        case .caution:
            return .orange
        case .unsupported:
            return .red
        }
    }

    private func movePage(to model: String) {
        let opts = allOptions
        guard let index = opts.firstIndex(where: { $0.name == model }) else {
            return
        }
        page = index / modelsPerPage
    }

    @MainActor
    private func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            installedModels = try await pipelineService.installedOllamaModelSizes(endpoint: endpoint)
            if installingModel == nil {
                installingStatus = nil
            }
        } catch {
            installedModels = [:]
            installingStatus = "Ollama 설치 목록을 불러오지 못했습니다. Ollama 앱 또는 서버 실행 상태를 확인해주세요."
        }
    }

    private func deletionMessage(for option: Constants.NewsOllamaModelOption) -> String {
        let size = installedModels[option.name] ?? 0
        let sizeText = size > 0
            ? " (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))"
            : ""
        return "\(option.name)\(sizeText)를 Ollama 에서 지웁니다. 다시 쓰려면 내려받아야 합니다."
    }

    /// Ollama 서버에서 모델을 지운다. 지우고 나면 같은 자리에 내려받기 버튼이 다시 나온다.
    @MainActor
    private func delete(_ option: Constants.NewsOllamaModelOption) async {
        deletionTarget = nil
        do {
            try await pipelineService.deleteOllamaModel(model: option.name, endpoint: endpoint)
            installedModels.removeValue(forKey: option.name)
            installingStatus = "\(option.name) 을(를) 지웠습니다."
        } catch {
            installingStatus = error.localizedDescription
        }
    }

    @State private var installTask: Task<Void, Never>?

    @MainActor
    private func cancelInstall() async {
        installTask?.cancel()
        installTask = nil
        installingModel = nil
        installingProgress = nil
        installingStatus = "다운로드를 취소했습니다."
    }

    @MainActor
    private func install(_ option: Constants.NewsOllamaModelOption) async {
        if Constants.newsOllamaRecommendationKinds()[option.name] == .unsupported {
            model = Constants.defaultNewsOllamaModel
            installingStatus = "\(option.name)은 현재 RAM \(Constants.newsHardwareMemoryGB)GB 기준으로 로컬 실행을 권장하지 않습니다."
            return
        }

        guard option.availability == .local else {
            model = option.name
            installingStatus = "클라우드 모델은 로컬 다운로드 없이 선택됩니다."
            return
        }

        model = option.name
        installingModel = option.name
        installingStatus = "다운로드 준비 중..."
        installingProgress = nil

        let task = Task {
            do {
                try await pipelineService.installOllamaModel(
                    model: option.name,
                    dataBasePath: dataBasePath,
                    progress: { progress in
                        if !Task.isCancelled {
                            installingStatus = progress.message
                            installingProgress = progress.fraction
                        }
                    }
                )
                if !Task.isCancelled {
                    await refresh()   // 크기까지 실제 값으로 다시 읽는다
                    installingStatus = "\(option.name) 설치가 완료되었습니다."
                }
            } catch is CancellationError {
                // Cancelled explicitly
            } catch {
                if !Task.isCancelled {
                    installingStatus = error.localizedDescription
                }
            }
            if !Task.isCancelled {
                installingModel = nil
                installingProgress = nil
            }
        }
        installTask = task
    }

    private func checkModelExists(_ name: String) async -> Bool {
        let parts = name.split(separator: ":")
        let modelName = String(parts[0])
        let tag = parts.count > 1 ? String(parts[1]) : "latest"
        
        let namespaceParts = modelName.split(separator: "/")
        let namespace = namespaceParts.count > 1 ? String(namespaceParts[0]) : "library"
        let repo = namespaceParts.count > 1 ? String(namespaceParts[1]) : modelName
        
        guard let url = URL(string: "https://registry.ollama.ai/v2/\(namespace)/\(repo)/manifests/\(tag)") else { return false }
        
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
