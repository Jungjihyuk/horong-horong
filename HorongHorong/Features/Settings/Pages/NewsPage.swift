import SwiftUI
import AppKit

struct NewsPage: View {
    @AppStorage(Constants.AppStorageKey.interestKeywords)
    private var interestKeywordsCSV: String = Constants.defaultInterestKeywords
    @AppStorage(Constants.NewsStorageKey.selectedProvider)
    private var selectedProvider: String = Constants.defaultNewsProvider
    @AppStorage(Constants.NewsStorageKey.dataBasePath)
    private var dataBasePath: String = ""
    @AppStorage(Constants.NewsStorageKey.schedule)
    private var schedule: String = Constants.defaultNewsSchedule

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
                Text("관심사를 칩으로 관리하세요. Agent 실험 탭과 같은 값을 공유합니다.")
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
