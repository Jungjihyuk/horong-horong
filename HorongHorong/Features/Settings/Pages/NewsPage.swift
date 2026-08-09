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
    @AppStorage(Constants.NewsStorageKey.scheduleDailyHour)
    private var dailyHour: Int = Constants.defaultNewsScheduleDailyHour
    @AppStorage(Constants.NewsStorageKey.scheduleDailyMinute)
    private var dailyMinute: Int = Constants.defaultNewsScheduleDailyMinute
    @AppStorage(Constants.NewsStorageKey.scheduleIntervalHours)
    private var intervalHours: Int = Constants.defaultNewsScheduleIntervalHours
    @AppStorage(Constants.NewsStorageKey.scheduleIntervalStartHour)
    private var intervalStartHour: Int = Constants.defaultNewsScheduleIntervalStartHour
    @AppStorage(Constants.NewsStorageKey.scheduleIntervalStartMinute)
    private var intervalStartMinute: Int = Constants.defaultNewsScheduleIntervalStartMinute
    @AppStorage(Constants.NewsStorageKey.scheduleNextSlotAt)
    private var nextSlotAtRaw: Double = 0
    @AppStorage(Constants.NewsStorageKey.maxItemsPerSource)
    private var maxItemsPerSource: Int = Constants.defaultNewsMaxItemsPerSource

    /// `DatePicker` 는 `Date` 바인딩만 받으므로 시·분 저장값과 여기서 오간다.
    @State private var dailyTime: Date = .now
    @State private var intervalStartTime: Date = .now

    @State private var store = NewsSourceStore.shared

    @State private var newKeyword: String = ""

    @State private var showAddSource: Bool = false
    @State private var detailKind: SourceDetailKind?

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
            syncTimePickersFromStorage()
        }
        .onChange(of: dailyTime) { _, newValue in
            storeDailyTime(newValue)
        }
        .onChange(of: intervalStartTime) { _, newValue in
            storeIntervalStartTime(newValue)
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

    // MARK: - 스케줄

    private var scheduleMode: Constants.NewsScheduleMode {
        Constants.NewsScheduleMode.normalized(rawValue: schedule)
    }

    private var scheduleSubtitle: String {
        switch scheduleMode {
        case .manual:
            return "팝오버의 '리포트 생성' 버튼을 누를 때만 수집합니다."
        case .dailyAt:
            return "매일 정해진 시각에 백그라운드에서 뉴스를 수집·요약합니다."
        case .interval:
            return "고정된 간격마다 백그라운드에서 뉴스를 수집·요약합니다."
        }
    }

    private var nextSlotAt: Date? {
        nextSlotAtRaw > 0 ? Date(timeIntervalSince1970: nextSlotAtRaw) : nil
    }

    private var nextCollectionText: String {
        guard let nextSlotAt else { return "예약 없음" }
        return NewsSchedulePlan.displayText(for: nextSlotAt)
    }

    private var nextCollectionSubtitle: String {
        switch scheduleMode {
        case .manual:
            return ""
        case .dailyAt:
            return "맥이 잠들어 있었다면 깨어난 뒤 한 번 수집합니다."
        case .interval:
            let start = String(format: "%02d:%02d", intervalStartHour, intervalStartMinute)
            return "\(start) 기준 \(intervalHours)시간 격자입니다."
        }
    }

    private func syncTimePickersFromStorage() {
        dailyTime = time(hour: dailyHour, minute: dailyMinute)
        intervalStartTime = time(hour: intervalStartHour, minute: intervalStartMinute)
    }

    private func time(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }

    private func storeDailyTime(_ date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        dailyHour = components.hour ?? Constants.defaultNewsScheduleDailyHour
        dailyMinute = components.minute ?? Constants.defaultNewsScheduleDailyMinute
    }

    private func storeIntervalStartTime(_ date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        intervalStartHour = components.hour ?? Constants.defaultNewsScheduleIntervalStartHour
        intervalStartMinute = components.minute ?? Constants.defaultNewsScheduleIntervalStartMinute
    }

    // MARK: - 파이프라인 카드

    private var pipelineCard: some View {
        SettingsGroupCard("파이프라인") {
            VStack(spacing: 0) {
                SettingsRow(
                    "자동 수집 스케줄",
                    subtitle: scheduleSubtitle
                ) {
                    Picker("", selection: $schedule) {
                        ForEach(Constants.NewsScheduleMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                if scheduleMode == .dailyAt {
                    SettingsRow(
                        "수집 시각",
                        subtitle: "매일 이 시각에 한 번 수집합니다. 맥이 잠들어 있었다면 깨어난 뒤 한 번 수집합니다."
                    ) {
                        DatePicker("", selection: $dailyTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                }
                if scheduleMode == .interval {
                    SettingsRow(
                        "시작 시각",
                        subtitle: "이 시각을 기준으로 격자가 만들어집니다. '특정 시각' 설정과는 별개 값입니다."
                    ) {
                        DatePicker("", selection: $intervalStartTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    SettingsRow(
                        "수집 간격",
                        subtitle: "중간에 직접 생성해도 다음 예정 시각은 밀리지 않습니다."
                    ) {
                        Stepper("\(intervalHours)시간", value: $intervalHours, in: 1...24)
                            .labelsHidden()
                        Text("\(intervalHours)시간")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                if scheduleMode != .manual {
                    SettingsRow("다음 수집", subtitle: nextCollectionSubtitle) {
                        Text(nextCollectionText)
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(nextSlotAt == nil ? .secondary : .primary)
                    }
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
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ollama 모델").font(.callout)
                Text("리포트 생성에 사용할 로컬 모델입니다. 설치된 모델은 체크 표시, 미설치 로컬 모델은 다운로드 버튼으로 표시합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            OllamaModelPicker(
                model: $ollamaModel,
                endpoint: normalizedOllamaEndpoint,
                dataBasePath: normalizedDataBasePath
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
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

    private func applyRecommendedOllamaModelIfNeeded() {
        let storedModel = UserDefaults.standard.string(forKey: Constants.NewsStorageKey.ollamaModel)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if storedModel == nil || storedModel?.isEmpty == true {
            ollamaModel = Constants.defaultNewsOllamaModel
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
