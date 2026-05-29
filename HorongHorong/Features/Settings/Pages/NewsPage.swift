import SwiftUI
import AppKit

struct NewsPage: View {
    @Environment(AppState.self) private var appState
    // 뉴스 전용 관심 키워드 — popover NewsView·runner 와 동일한 키를 사용해 설정 변경이 곧장 리포트에 반영되도록 함.
    @AppStorage(Constants.NewsStorageKey.interestKeywords)
    private var interestKeywordsCSV: String = ""
    // AI Agent 와 *과거에 공유* 하던 키. 첫 진입 시 마이그레이션 소스로만 사용.
    @AppStorage(Constants.AppStorageKey.interestKeywords)
    private var legacyAgentKeywordsCSV: String = Constants.defaultInterestKeywords
    @AppStorage(Constants.NewsStorageKey.selectedProvider)
    private var selectedProvider: String = Constants.defaultNewsProvider
    @AppStorage(Constants.NewsStorageKey.ollamaModel)
    private var ollamaModel: String = Constants.defaultNewsOllamaModel
    @AppStorage(Constants.NewsStorageKey.ollamaEndpoint)
    private var ollamaEndpoint: String = Constants.defaultNewsOllamaEndpoint
    @AppStorage(Constants.NewsStorageKey.ollamaTimeout)
    private var ollamaTimeout: Double = Constants.defaultNewsOllamaTimeout
    @AppStorage(Constants.NewsStorageKey.dataBasePath)
    private var dataBasePath: String = ""
    @AppStorage(Constants.NewsStorageKey.schedule)
    private var schedule: String = Constants.defaultNewsSchedule
    @AppStorage(Constants.NewsStorageKey.maxItemsPerSource)
    private var maxItemsPerSource: Int = Constants.defaultNewsMaxItemsPerSource

    @State private var store = NewsSourceStore.shared

    @State private var newKeyword: String = ""

    @State private var showAddSource: Bool = false
    @State private var detailKind: SourceDetailKind?
    @State private var installedOllamaModels: Set<String> = []
    @State private var isLoadingOllamaModels = false
    @State private var installingOllamaModel: String?
    @State private var installingOllamaStatus: String?
    @State private var installingOllamaProgress: Double?
    @State private var ollamaModelPage = 0

    private let ollamaModelsPerPage = 5

    private var pipelineService: NewsPipelineService {
        appState.newsPipelineService
    }

    var body: some View {
        SettingsPageScroll {
            SettingsPageHeader(title: SettingsTab.news.label, subtitle: SettingsTab.news.subtitle)

            sourceCard
            keywordCard
            pipelineCard
        }
        .onAppear {
            if dataBasePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                dataBasePath = Constants.defaultNewsDataBasePath
            }
            migrateLegacyKeywordsIfNeeded()
            applyRecommendedOllamaModelIfNeeded()
            if selectedProvider == "ollama" {
                Task { await refreshInstalledOllamaModels() }
            }
        }
        .onChange(of: selectedProvider) { _, newValue in
            guard newValue == "ollama" else { return }
            Task { await refreshInstalledOllamaModels() }
        }
        .onChange(of: ollamaEndpoint) { _, _ in
            guard selectedProvider == "ollama" else { return }
            Task { await refreshInstalledOllamaModels() }
        }
        .sheet(isPresented: $showAddSource) {
            AddSourceSheet()
        }
        .sheet(item: $detailKind) { kind in
            SourceDetailSheet(kind: kind)
        }
    }

    // MARK: - 소스 카드

    private var sourceCard: some View {
        SettingsGroupCard("소스") {
            VStack(alignment: .leading, spacing: 10) {
                Text("관심 정보 소스를 등록하세요. 칩 클릭으로 항목 추가·삭제, 단축 토글 등을 할 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 6) {
                    sourceChips
                    Button {
                        showAddSource = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.caption2)
                            Text("소스 추가")
                                .font(.caption.weight(.medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.primary.opacity(0.20), lineWidth: 0.6)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.clear)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private var sourceChips: some View {
        let playlistCount = store.youtubeItems.filter {
            if case .playlist = $0.kind { return true }
            return false
        }.count
        let channelCount = store.youtubeItems.filter {
            if case .channel = $0.kind { return true }
            return false
        }.count

        if channelCount > 0 {
            SourceChip(
                icon: .youtube,
                label: "YouTube 채널",
                count: channelCount,
                onTap: { detailKind = .youtube },
                onDelete: { store.clearAllYoutube() }
            )
        }
        if playlistCount > 0 {
            SourceChip(
                icon: .youtube,
                label: "YouTube 재생목록",
                count: playlistCount,
                onTap: { detailKind = .youtube },
                onDelete: { store.clearAllYoutube() }
            )
        }
        if store.googleNewsEnabled {
            SourceChip(
                icon: .googleNews,
                label: "Google News",
                count: nil,
                onTap: {},
                onDelete: { store.googleNewsEnabled = false }
            )
        }
        if store.yozmITEnabled {
            SourceChip(
                icon: .yozmIT,
                label: "YOZM IT",
                count: nil,
                onTap: {},
                onDelete: { store.yozmITEnabled = false }
            )
        }
        if store.hackerNewsEnabled {
            SourceChip(
                icon: .hackerNews,
                label: "Hacker News",
                count: nil,
                onTap: {},
                onDelete: { store.hackerNewsEnabled = false }
            )
        }
        if !store.rssFeeds.isEmpty {
            SourceChip(
                icon: .rss,
                label: "RSS",
                count: store.rssFeeds.count,
                onTap: { detailKind = .rss },
                onDelete: { store.clearAllRSS() }
            )
        }
    }

    // MARK: - 관심 키워드 카드

    private var keywordCard: some View {
        SettingsGroupCard("관심 키워드") {
            VStack(alignment: .leading, spacing: 10) {
                Text("뉴스 리포트 수집에 쓰일 관심사를 칩으로 관리하세요. AI Agent 탭의 관심사와는 별개로 저장됩니다.")
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
        interestKeywordsCSV.components(separatedBy: ",")
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
        interestKeywordsCSV = current.joined(separator: ", ")
        newKeyword = ""
    }

    private func removeKeyword(_ keyword: String) {
        var current = keywords
        current.removeAll { $0 == keyword }
        interestKeywordsCSV = current.joined(separator: ", ")
    }

    /// 뉴스 전용 키가 비어있을 때만, 기존에 Agent 와 공유하던 키워드를 *1회* 복사한다.
    /// 사용자가 이미 뉴스 키워드를 한 번이라도 편집했다면 (값이 있으면) 건너뜀.
    private func migrateLegacyKeywordsIfNeeded() {
        guard interestKeywordsCSV.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        let legacy = legacyAgentKeywordsCSV.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !legacy.isEmpty else { return }
        interestKeywordsCSV = legacy
    }

    // MARK: - 파이프라인 카드

    private var pipelineCard: some View {
        SettingsGroupCard("파이프라인") {
            VStack(spacing: 0) {
                SettingsRow(
                    "자동 수집 스케줄",
                    subtitle: "설정한 주기마다 백그라운드에서 뉴스를 수집·요약합니다.",
                    comingSoon: true
                ) {
                    Picker("", selection: $schedule) {
                        ForEach(Constants.availableNewsSchedules, id: \.value) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                SettingsRow(
                    "요약 에이전트 (LLM Provider)",
                    subtitle: "외부 CLI 에이전트 또는 로컬 Ollama 모델을 선택합니다."
                ) {
                    Picker("", selection: $selectedProvider) {
                        ForEach(Constants.availableNewsProviders, id: \.self) { provider in
                            Text(provider).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                if selectedProvider == "ollama" {
                    ollamaSettingsRows
                }
                SettingsRow(
                    "소스당 최대 항목 수",
                    subtitle: "각 소스에서 한 번에 가져올 기사 수. 늘리면 더 풍부하지만 LLM 호출 비용이 커집니다."
                ) {
                    Stepper("\(maxItemsPerSource)개", value: $maxItemsPerSource, in: 1...30)
                        .labelsHidden()
                    Text("\(maxItemsPerSource)개")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }
                SettingsRow(
                    "일일 리포트 저장 위치",
                    subtitle: "마크다운 파일이 저장되는 폴더입니다."
                ) {
                    HStack(spacing: 4) {
                        Text(dataBasePath.isEmpty ? Constants.defaultNewsDataBasePath : dataBasePath)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 260, alignment: .trailing)
                        Button {
                            if let selected = selectDirectory() {
                                dataBasePath = selected
                            }
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.bordered)
                        .help("폴더 변경")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var ollamaSettingsRows: some View {
        SettingsRow(
            "Ollama 모델",
            subtitle: "리포트 생성에 사용할 로컬 모델입니다. 목록 선택 후 직접 수정할 수 있습니다."
        ) {
            HStack(spacing: 8) {
                Picker("", selection: $ollamaModel) {
                    ForEach(Constants.availableNewsOllamaModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .labelsHidden()
                .frame(width: 150)

                TextField("예: qwen3:14b", text: $ollamaModel)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout.monospaced())
                    .frame(width: 170)
            }
        }
        SettingsRow(
            "모델 후보",
            subtitle: "설치된 모델은 체크 표시, 미설치 로컬 모델은 다운로드 버튼으로 표시합니다."
        ) {
            ollamaModelCandidateList
        }
        SettingsRow(
            "Ollama Endpoint",
            subtitle: "Ollama 서버 주소입니다. 기본값은 로컬 서버입니다."
        ) {
            TextField(Constants.defaultNewsOllamaEndpoint, text: $ollamaEndpoint)
                .textFieldStyle(.roundedBorder)
                .font(.callout.monospaced())
                .frame(width: 260)
        }
        SettingsRow(
            "Ollama Timeout",
            subtitle: "모델 응답을 기다릴 최대 시간입니다."
        ) {
            Stepper("\(Int(ollamaTimeout))초", value: $ollamaTimeout, in: 30...600, step: 30)
                .labelsHidden()
            Text("\(Int(ollamaTimeout))초")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }

    private var ollamaModelCandidateList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(isLoadingOllamaModels ? "설치 목록 확인 중..." : "사용 가능 후보")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("M칩 통합 메모리 \(Constants.newsHardwareMemoryGB)GB 기준")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer()
                Button {
                    Task { await refreshInstalledOllamaModels() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(isLoadingOllamaModels || installingOllamaModel != nil)
                .help("설치 상태 새로고침")
            }

            VStack(spacing: 6) {
                ForEach(pagedOllamaModelOptions) { option in
                    ollamaModelOptionRow(option)
                }
            }

            if ollamaModelPageCount > 1 {
                ollamaModelPagination
            }

            if let installingOllamaModel {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(installingOllamaModel) 준비 중")
                        .font(.caption.weight(.medium))
                    if let installingOllamaProgress {
                        ProgressView(value: installingOllamaProgress, total: 1.0)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                    if let installingOllamaStatus {
                        Text(installingOllamaStatus)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.top, 2)
            } else if let installingOllamaStatus {
                Text(installingOllamaStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(width: 390, alignment: .leading)
    }

    private var pagedOllamaModelOptions: [Constants.NewsOllamaModelOption] {
        let start = ollamaModelPage * ollamaModelsPerPage
        guard start < Constants.availableNewsOllamaModelOptions.count else {
            return Array(Constants.availableNewsOllamaModelOptions.prefix(ollamaModelsPerPage))
        }
        let end = min(start + ollamaModelsPerPage, Constants.availableNewsOllamaModelOptions.count)
        return Array(Constants.availableNewsOllamaModelOptions[start..<end])
    }

    private var ollamaModelPageCount: Int {
        max(1, (Constants.availableNewsOllamaModelOptions.count + ollamaModelsPerPage - 1) / ollamaModelsPerPage)
    }

    private var ollamaModelPagination: some View {
        HStack(spacing: 6) {
            Text("\(ollamaModelPage + 1) / \(ollamaModelPageCount)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)

            ForEach(0..<ollamaModelPageCount, id: \.self) { page in
                Button {
                    ollamaModelPage = page
                } label: {
                    Text("\(page + 1)")
                        .font(.caption2.weight(.semibold))
                        .frame(width: 22, height: 22)
                        .background(
                            Circle()
                                .fill(page == ollamaModelPage ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                        )
                        .overlay(
                            Circle()
                                .stroke(page == ollamaModelPage ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.10), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(page == ollamaModelPage ? Color.accentColor : Color.secondary)
                .help("\(page + 1)번째 모델 후보 페이지")
            }

            Spacer()
        }
        .padding(.top, 2)
    }

    private func ollamaModelOptionRow(_ option: Constants.NewsOllamaModelOption) -> some View {
        let isSelected = ollamaModel == option.name
        let recommendationKind = Constants.newsOllamaRecommendationKinds()[option.name]
        let isUnsupported = recommendationKind == .unsupported
        let isCloud = option.availability == .cloud
        let isInstalled = isCloud || installedOllamaModels.contains(option.name)
        let isInstalling = installingOllamaModel == option.name

        return HStack(spacing: 8) {
            Button {
                guard !isUnsupported else {
                    installingOllamaStatus = "\(option.name)은 현재 RAM \(Constants.newsHardwareMemoryGB)GB 기준으로 로컬 실행을 권장하지 않습니다."
                    return
                }
                ollamaModel = option.name
                if isCloud {
                    installingOllamaStatus = "클라우드 모델은 로컬 다운로드 없이 선택됩니다. Ollama 계정/클라우드 사용 가능 여부를 확인해주세요."
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
                    Task { await installOllamaModel(option) }
                } label: {
                    if isInstalling {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.down.circle")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(installingOllamaModel != nil || isUnsupported)
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

    private func applyRecommendedOllamaModelIfNeeded() {
        let storedModel = UserDefaults.standard.string(forKey: Constants.NewsStorageKey.ollamaModel)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if storedModel == nil || storedModel?.isEmpty == true {
            ollamaModel = Constants.defaultNewsOllamaModel
        }
        moveOllamaModelPage(to: ollamaModel)
    }

    private func moveOllamaModelPage(to model: String) {
        guard let index = Constants.availableNewsOllamaModelOptions.firstIndex(where: { $0.name == model }) else {
            return
        }
        ollamaModelPage = index / ollamaModelsPerPage
    }

    @MainActor
    private func refreshInstalledOllamaModels() async {
        isLoadingOllamaModels = true
        defer { isLoadingOllamaModels = false }

        do {
            installedOllamaModels = try await pipelineService.installedOllamaModelNames(endpoint: normalizedOllamaEndpoint)
            if installingOllamaModel == nil {
                installingOllamaStatus = nil
            }
        } catch {
            installedOllamaModels = []
            installingOllamaStatus = "Ollama 설치 목록을 불러오지 못했습니다. Ollama 앱 또는 서버 실행 상태를 확인해주세요."
        }
    }

    @MainActor
    private func installOllamaModel(_ option: Constants.NewsOllamaModelOption) async {
        if Constants.newsOllamaRecommendationKinds()[option.name] == .unsupported {
            ollamaModel = Constants.defaultNewsOllamaModel
            installingOllamaStatus = "\(option.name)은 현재 RAM \(Constants.newsHardwareMemoryGB)GB 기준으로 로컬 실행을 권장하지 않습니다."
            return
        }

        guard option.availability == .local else {
            ollamaModel = option.name
            installingOllamaStatus = "클라우드 모델은 로컬 다운로드 없이 선택됩니다."
            return
        }

        ollamaModel = option.name
        installingOllamaModel = option.name
        installingOllamaStatus = "다운로드 준비 중..."
        installingOllamaProgress = nil
        defer {
            installingOllamaModel = nil
            installingOllamaProgress = nil
        }

        do {
            try await pipelineService.installOllamaModel(
                model: option.name,
                dataBasePath: normalizedDataBasePath,
                progress: { progress in
                    installingOllamaStatus = progress.message
                    installingOllamaProgress = progress.fraction
                }
            )
            installedOllamaModels.insert(option.name)
            installingOllamaStatus = "\(option.name) 설치가 완료되었습니다."
        } catch {
            installingOllamaStatus = error.localizedDescription
        }
    }

    private var normalizedOllamaEndpoint: String {
        let trimmed = ollamaEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Constants.defaultNewsOllamaEndpoint : trimmed
    }

    private var normalizedDataBasePath: String {
        let trimmed = dataBasePath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Constants.defaultNewsDataBasePath : trimmed
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
