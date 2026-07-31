import SwiftUI

/// Ollama 모델 후보 목록 + 다운로드 UI. 뉴스·루미롱 설정에서 함께 쓴다.
struct OllamaModelPicker: View {
    @Binding var model: String
    let endpoint: String
    let dataBasePath: String

    @State private var installedModels: Set<String> = []
    @State private var isLoading = false
    @State private var installingModel: String?
    @State private var installingStatus: String?
    @State private var installingProgress: Double?
    @State private var page = 0

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
        .frame(width: 390, alignment: .leading)
        .task {
            movePage(to: model)
            await refresh()
        }
        .onChange(of: endpoint) { _, _ in
            Task { await refresh() }
        }
    }

    private var pagedOptions: [Constants.NewsOllamaModelOption] {
        let start = page * modelsPerPage
        guard start < Constants.availableNewsOllamaModelOptions.count else {
            return Array(Constants.availableNewsOllamaModelOptions.prefix(modelsPerPage))
        }
        let end = min(start + modelsPerPage, Constants.availableNewsOllamaModelOptions.count)
        return Array(Constants.availableNewsOllamaModelOptions[start..<end])
    }

    private var pageCount: Int {
        max(1, (Constants.availableNewsOllamaModelOptions.count + modelsPerPage - 1) / modelsPerPage)
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
        let isInstalled = isCloud || installedModels.contains(option.name)
        let isInstalling = installingModel == option.name

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

            if isCloud {
                Image(systemName: "cloud")
                    .foregroundStyle(.secondary)
                    .help("Ollama 클라우드 모델")
            } else if isInstalled {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
                    .help("설치됨")
            } else {
                Button {
                    Task { await install(option) }
                } label: {
                    if isInstalling {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.down.circle")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(installingModel != nil || isUnsupported)
                .help(isUnsupported ? "현재 PC 사양에서는 권장하지 않음" : "\(option.name) 다운로드")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .opacity(isUnsupported ? 0.62 : 1)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 0.5)
        )
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
        guard let index = Constants.availableNewsOllamaModelOptions.firstIndex(where: { $0.name == model }) else {
            return
        }
        page = index / modelsPerPage
    }

    @MainActor
    private func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            installedModels = try await pipelineService.installedOllamaModelNames(endpoint: endpoint)
            if installingModel == nil {
                installingStatus = nil
            }
        } catch {
            installedModels = []
            installingStatus = "Ollama 설치 목록을 불러오지 못했습니다. Ollama 앱 또는 서버 실행 상태를 확인해주세요."
        }
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
        defer {
            installingModel = nil
            installingProgress = nil
        }

        do {
            try await pipelineService.installOllamaModel(
                model: option.name,
                dataBasePath: dataBasePath,
                progress: { progress in
                    installingStatus = progress.message
                    installingProgress = progress.fraction
                }
            )
            installedModels.insert(option.name)
            installingStatus = "\(option.name) 설치가 완료되었습니다."
        } catch {
            installingStatus = error.localizedDescription
        }
    }
}
