import SwiftUI
import AppKit

struct NewsPage: View {
    // 뉴스 전용 관심 키워드 — popover NewsView·runner 와 동일한 키를 사용해 설정 변경이 곧장 리포트에 반영되도록 함.
    @AppStorage(Constants.NewsStorageKey.interestKeywords)
    private var interestKeywordsCSV: String = ""
    // AI Agent 와 *과거에 공유* 하던 키. 첫 진입 시 마이그레이션 소스로만 사용.
    @AppStorage(Constants.AppStorageKey.interestKeywords)
    private var legacyAgentKeywordsCSV: String = Constants.defaultInterestKeywords
    @AppStorage(Constants.NewsStorageKey.selectedProvider)
    private var selectedProvider: String = Constants.defaultNewsProvider
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
                    subtitle: "설치된 CLI 에이전트 중에서 선택합니다."
                ) {
                    Picker("", selection: $selectedProvider) {
                        ForEach(Constants.availableNewsProviders, id: \.self) { provider in
                            Text(provider).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
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
