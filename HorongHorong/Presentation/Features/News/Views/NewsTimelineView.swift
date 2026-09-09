import SwiftUI

/// 분야별 월간 타임라인 — 가로 축 시각화.
///
/// 목업(Obsidian Excalidraw)의 구조를 그대로 옮긴다:
/// 월별 고정 폭 컬럼 → 축선 «위» 에 핵심 축 카드(최대 3개) → 점선으로 축 위 다이아몬드
/// 마커에 연결 → 축선 «아래» 에 우선순위순 세부 사건.
///
/// **높이를 재지 않고 상수로 고정한다**(CLAUDE.md R11). 축선 Y 가 모든 달에서 같아야
/// 하나의 선으로 보이는데, 카드 높이를 `GeometryReader` 로 재서 상위 상태에 되먹이면
/// 그 값이 다시 카드 폭·높이를 정해 레이아웃이 수렴하지 못한다. 대신 카드 높이를 고정하고
/// 넘치는 글은 `lineLimit` 으로 자른다 — vault 생성기(`clipped_wrap`)와 같은 전략이다.
enum NewsTimelineMetrics {
    /// 축 카드 1개의 폭. 월 컬럼은 이 폭 3개가 들어가도록 잡는다.
    static let cardWidth: CGFloat = 196
    static let cardSpacing: CGFloat = 12
    static let columnPadding: CGFloat = 16
    /// 축 카드 영역의 고정 높이. 카드는 아래로 정렬해 축선에 붙는다.
    static let axisCardHeight: CGFloat = 188
    /// 카드와 축선 사이 점선 구간.
    static let connectorHeight: CGFloat = 26
    static let markerSize: CGFloat = 10
    static let dateLabelHeight: CGFloat = 18
    static let headerBarHeight: CGFloat = 44
    /// 머리말 배너 폭. **고정해야 한다** — 가로 스크롤 안에서 `maxWidth: .infinity` 를 주면
    /// 배너가 월 컬럼 전체를 합친 폭(8개월이면 5,000pt 넘는다)까지 늘어난다.
    static let bannerWidth: CGFloat = 1080

    static let columnWidth: CGFloat =
        cardWidth * 3 + cardSpacing * 2 + columnPadding * 2

    /// 월별 파스텔. vault 생성기와 같은 계열을 쓴다.
    static let palette: [Color] = [
        Color(red: 0.647, green: 0.847, blue: 1.0),
        Color(red: 0.698, green: 0.949, blue: 0.729),
        Color(red: 1.0, green: 0.925, blue: 0.6),
        Color(red: 0.816, green: 0.749, blue: 1.0),
        Color(red: 1.0, green: 0.847, blue: 0.659),
        Color(red: 0.6, green: 0.914, blue: 0.949),
        Color(red: 0.918, green: 0.867, blue: 0.843),
        Color(red: 1.0, green: 0.788, blue: 0.788),
    ]

    static func tint(for index: Int) -> Color {
        palette[index % palette.count]
    }
}

struct NewsTimelineView: View {
    let timeline: NewsTimeline

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 18) {
                NewsTimelineBanner(timeline: timeline)
                    .equatable()

                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(timeline.months.enumerated()), id: \.element.id) { index, month in
                        NewsTimelineMonthColumn(month: month, tint: NewsTimelineMetrics.tint(for: index))
                            .equatable()
                    }
                }
            }
            .padding(20)
        }
        .background(PopoverChrome.surface)
    }
}

// MARK: - 머리말 배너

struct NewsTimelineBanner: View, Equatable {
    let timeline: NewsTimeline

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(timeline.categoryLabel) — 월별 핵심 사건 타임라인")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)

            Text(statsLine)
                .font(.system(size: 11.5, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)

            if !timeline.overview.emphasisKeywords.isEmpty {
                Text("강조: " + timeline.overview.emphasisKeywords.joined(separator: " · "))
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
            }

            if !timeline.overview.summary.isEmpty {
                Text(timeline.overview.summary)
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: NewsTimelineMetrics.bannerWidth - 28, alignment: .leading)
            }
        }
        .padding(14)
        .frame(width: NewsTimelineMetrics.bannerWidth, alignment: .leading)
        .background(
            NewsTimelineMetrics.palette[1].opacity(0.32),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
        )
    }

    private var statsLine: String {
        var parts: [String] = []
        if !timeline.dateFrom.isEmpty, !timeline.dateTo.isEmpty {
            parts.append("\(timeline.dateFrom) ~ \(timeline.dateTo)")
        }
        parts.append("\(timeline.totalEventCount)개 시점")
        parts.append("\(timeline.months.count)개월")
        parts.append("월별 축 최대 3개")
        parts.append("전환점 \(timeline.turningPointMonthKeys.count)곳")
        return parts.joined(separator: " · ")
    }
}

// MARK: - 월 컬럼

struct NewsTimelineMonthColumn: View, Equatable {
    let month: NewsTimelineMonth
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            monthHeaderBar
                .padding(.horizontal, NewsTimelineMetrics.columnPadding)
                .padding(.bottom, 14)

            axisSection

            detailSection
                .padding(.horizontal, NewsTimelineMetrics.columnPadding)
                .padding(.top, 12)

            Spacer(minLength: 0)
        }
        .frame(width: NewsTimelineMetrics.columnWidth, alignment: .topLeading)
    }

    private var monthHeaderBar: some View {
        HStack(spacing: 8) {
            Text(month.monthKey)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)

            Text("축 \(month.axisEvents.count) · 세부 \(month.detailEvents.count)")
                .font(.system(size: 10.5, design: .rounded))
                .foregroundStyle(PopoverChrome.ink.opacity(0.65))

            if month.isTurningPoint {
                Text("전환점")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 6)

            Text(month.keyTerms.isEmpty ? "핵심어 -" : "핵심어 " + month.keyTerms.joined(separator: " · "))
                .font(.system(size: 10.5, design: .rounded))
                .foregroundStyle(PopoverChrome.ink.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 12)
        .frame(height: NewsTimelineMetrics.headerBarHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// 축 카드 → 점선 → 축선 → 날짜 라벨. 높이가 전부 상수라 달마다 축선 Y 가 같다.
    private var axisSection: some View {
        ZStack(alignment: .top) {
            // 축선은 컬럼 전체 폭을 지난다. 컬럼이 붙어 있어 하나의 선으로 이어진다.
            Rectangle()
                .fill(PopoverChrome.inkTertiary.opacity(0.55))
                .frame(height: 1.5)
                .offset(
                    y: NewsTimelineMetrics.axisCardHeight
                        + NewsTimelineMetrics.connectorHeight
                        + NewsTimelineMetrics.markerSize / 2
                )

            HStack(alignment: .top, spacing: NewsTimelineMetrics.cardSpacing) {
                ForEach(Array(month.axisEvents.enumerated()), id: \.element.id) { index, event in
                    NewsTimelineAxisColumn(event: event, ordinal: index + 1, tint: tint)
                        .equatable()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, NewsTimelineMetrics.columnPadding)
        }
        .frame(
            height: NewsTimelineMetrics.axisCardHeight
                + NewsTimelineMetrics.connectorHeight
                + NewsTimelineMetrics.markerSize
                + NewsTimelineMetrics.dateLabelHeight
        )
    }

    @ViewBuilder
    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(month.detailEvents.isEmpty ? "세부 사건 없음" : "세부 사건 · 우선순위순")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)

            ForEach(month.detailEvents) { event in
                NewsTimelineDetailCard(event: event, tint: tint)
                    .equatable()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 축 사건 (카드 + 연결선 + 마커 + 날짜)

struct NewsTimelineAxisColumn: View, Equatable {
    let event: NewsTimelineEvent
    let ordinal: Int
    let tint: Color

    var body: some View {
        VStack(spacing: 0) {
            // 카드는 아래로 붙인다 — 내용이 짧아도 축선까지의 거리가 같아야 한다.
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                card
            }
            .frame(width: NewsTimelineMetrics.cardWidth, height: NewsTimelineMetrics.axisCardHeight)

            NewsTimelineDottedLine()
                .stroke(
                    PopoverChrome.inkTertiary.opacity(0.6),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
                .frame(width: 1, height: NewsTimelineMetrics.connectorHeight)

            marker

            Text(event.shortDate)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)
                .frame(height: NewsTimelineMetrics.dateLabelHeight)
        }
        .frame(width: NewsTimelineMetrics.cardWidth)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("핵심 \(ordinal) · 중요도 \(event.importance)")
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink.opacity(0.6))

            NewsTimelineTitleText(title: event.title, url: event.linkURL, size: 12, lineLimit: 3)
                .equatable()

            ForEach(event.bullets.prefix(2), id: \.self) { bullet in
                Text("• \(bullet)")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink.opacity(0.75))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !event.tags.isEmpty {
                Text(event.tags.prefix(2).joined(separator: " · "))
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.red.opacity(0.8))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(.red.opacity(0.45), lineWidth: 1)
                    )
            }
        }
        .padding(10)
        .frame(width: NewsTimelineMetrics.cardWidth, alignment: .leading)
        .background(tint.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
        )
        .help(event.whyItMatters.isEmpty ? event.title : event.whyItMatters)
    }

    private var marker: some View {
        Rectangle()
            .fill(tint)
            .overlay(Rectangle().stroke(PopoverChrome.inkSecondary.opacity(0.7), lineWidth: 1))
            .frame(width: NewsTimelineMetrics.markerSize, height: NewsTimelineMetrics.markerSize)
            .rotationEffect(.degrees(45))
    }
}

struct NewsTimelineDottedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

// MARK: - 세부 사건

struct NewsTimelineDetailCard: View, Equatable {
    let event: NewsTimelineEvent
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(event.shortDate)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink.opacity(0.75))
                if let rank = event.rank {
                    Text("\(rank)순위")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                }
                Text("중요도 \(event.importance)")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }
            .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                NewsTimelineTitleText(title: event.title, url: event.linkURL, size: 11, lineLimit: 2)
                    .equatable()

                ForEach(event.bullets.prefix(1), id: \.self) { bullet in
                    Text("• \(bullet)")
                        .font(.system(size: 9.5, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.2), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(PopoverChrome.border.opacity(0.7), lineWidth: PopoverChrome.borderWidth)
        )
    }
}

/// 제목. 원문 URL 이 있으면 링크로 연다.
struct NewsTimelineTitleText: View, Equatable {
    let title: String
    let url: URL?
    let size: CGFloat
    var lineLimit: Int = 3

    var body: some View {
        if let url {
            Link(destination: url) {
                titleText
            }
            .buttonStyle(.plain)
        } else {
            titleText
        }
    }

    private var titleText: some View {
        Text(title)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundStyle(PopoverChrome.ink)
            .lineLimit(lineLimit)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
// MARK: - 보관함 창 안의 타임라인 모드

/// 뉴스 탭이 보여줄 두 가지 — 리포트 한 편씩 보는 보관함과, 분야별 흐름을 보는 타임라인.
enum NewsHubMode: String, CaseIterable, Identifiable {
    case archive
    case timeline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .archive:  return "보관함"
        case .timeline: return "타임라인"
        }
    }
}

/// 타임라인 모드의 내용.
///
/// **타임라인은 사용자가 만들 때만 생긴다.** 리포트가 늘었다고 자동으로 만들거나 갱신하지
/// 않는다 — 원한 적 없는 분야에 LLM 비용이 나가면 안 되기 때문이다. 「만들기」를 누르면
/// 리포트에서 «실제로 존재하는» 주제만 제안하고, 그중 고른 것만 만든다.
struct NewsTimelinePane: View {
    @Bindable var viewModel: NewsTimelineViewModel
    let gateway: NewsTimelineGateway
    let dataBasePath: String
    /// 스크린샷 타깃(`news-timeline-picker`)처럼 시트를 연 채로 열어야 할 때만 쓴다.
    var initiallyPresentingPicker: Bool = false

    @State private var isPickerPresented = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(PopoverChrome.divider)
            content
        }
        .onAppear { isPickerPresented = isPickerPresented || initiallyPresentingPicker }
        .sheet(isPresented: $isPickerPresented) {
            NewsTimelineTopicPicker(
                viewModel: viewModel,
                gateway: gateway,
                dataBasePath: dataBasePath
            )
        }
        .overlay { buildingOverlay }
        .alert(
            "타임라인 생성 실패",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.dismissError() } }
            )
        ) {
            Button("확인") { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text(viewModel.isEmpty ? "타임라인 없음" : "\(viewModel.timelines.count)개 분야")
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)

            Spacer(minLength: 8)

            Button {
                isPickerPresented = true
            } label: {
                Label("타임라인 만들기", systemImage: "plus")
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.buildingLabel != nil)
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(PopoverChrome.surfaceAlt.opacity(0.35))
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isEmpty {
            emptyState
        } else {
            HStack(spacing: 0) {
                if viewModel.timelines.count > 1 {
                    categoryList
                    Divider().overlay(PopoverChrome.divider)
                }

                if let timeline = viewModel.selectedTimeline {
                    NewsTimelineView(timeline: timeline)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var categoryList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(viewModel.timelines) { timeline in
                categoryButton(timeline)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 12)
        .frame(width: 190)
        .background(PopoverChrome.surfaceAlt.opacity(0.35))
    }

    private func categoryButton(_ timeline: NewsTimeline) -> some View {
        let isSelected = viewModel.selectedTimeline?.categoryId == timeline.categoryId
        return Button {
            viewModel.select(timeline.categoryId)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(timeline.categoryLabel)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                    .lineLimit(1)
                Text("\(timeline.months.count)개월 · 사건 \(timeline.totalEventCount)건")
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isSelected ? PopoverChrome.accentSoft.opacity(0.22) : Color.clear,
                in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 28))
                .foregroundStyle(PopoverChrome.inkTertiary)
            Text("아직 타임라인이 없습니다")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)
            Text("「타임라인 만들기」를 누르면 리포트에 실제로 있는 주제만 골라서 보여줍니다.")
                .font(.system(size: 11.5, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PopoverChrome.surface)
    }

    @ViewBuilder
    private var buildingOverlay: some View {
        if let label = viewModel.buildingLabel {
            VStack(spacing: 10) {
                ProgressView()
                Text("\(label) 타임라인 만드는 중...")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                Text("월별로 종합하는 동안 몇 분 걸릴 수 있습니다.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }
            .padding(22)
            .background(
                PopoverChrome.card,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .shadow(radius: 12)
        }
    }
}

/// 리포트에서 만들 수 있는 주제 목록. 여기 없는 주제는 만들 수 없다.
struct NewsTimelineTopicPicker: View {
    @Bindable var viewModel: NewsTimelineViewModel
    let gateway: NewsTimelineGateway
    let dataBasePath: String

    @Environment(\.dismiss) private var dismiss
    @AppStorage(Constants.NewsStorageKey.selectedProvider)
    private var selectedProvider = Constants.defaultNewsProvider

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(PopoverChrome.divider)
            body_
        }
        .frame(width: 520, height: 460)
        .background(PopoverChrome.surface)
        .task {
            await viewModel.loadSuggestions(gateway: gateway, dataBasePath: dataBasePath)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("어떤 주제로 만들까요?")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                Text("리포트에 실제로 있는 주제만 보여줍니다. 고른 주제만 만들어집니다.")
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                Text("현재 Provider: \(selectedProvider.capitalized)")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.accent)
            }

            Spacer(minLength: 8)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(PopoverChrome.inkSecondary)
            .help("닫기")
            .accessibilityLabel("닫기")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    @ViewBuilder
    private var body_: some View {
        if viewModel.isLoadingSuggestions {
            ProgressView("주제를 찾는 중...")
                .font(.system(size: 12, design: .rounded))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.suggestions.isEmpty {
            // 시트가 뒤쪽 alert 를 가리므로 사유를 여기서 직접 보여준다.
            VStack(spacing: 8) {
                Image(systemName: viewModel.errorMessage == nil
                      ? "tray" : "exclamationmark.triangle")
                    .font(.system(size: 22))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                Text(viewModel.errorMessage ?? "만들 수 있는 주제가 없습니다.\n리포트가 더 쌓이면 다시 확인해 주세요.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.suggestions) { suggestion in
                        NewsTimelineSuggestionRow(suggestion: suggestion) {
                            dismiss()
                            Task {
                                await viewModel.build(
                                    label: suggestion.label,
                                    gateway: gateway,
                                    dataBasePath: dataBasePath
                                )
                            }
                        }
                    }
                }
                .padding(14)
            }
        }
    }
}

/// **`Equatable` 을 붙이지 않는다.** R3 은 «데이터 크기에 비례하는» 컬렉션 행을 두고 한
/// 말인데, 주제 후보는 리포트가 아무리 쌓여도 분야 수(한 자릿수)에 머문다. 게다가 행이
/// 클로저를 들고 있어 합성이 안 되고, 손으로 `==` 를 쓰면 View 의 `@MainActor` 격리를
/// 넘는다(Swift 6 에서 컴파일 에러다).
struct NewsTimelineSuggestionRow: View {
    let suggestion: NewsTimelineSuggestion
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(suggestion.label)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(PopoverChrome.ink)
                    if suggestion.alreadyExists {
                        Text("이미 있음")
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(PopoverChrome.accentSoft.opacity(0.4), in: Capsule())
                            .foregroundStyle(PopoverChrome.accent)
                    }
                }

                Text(suggestion.summaryLine)
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)

                if !suggestion.headings.isEmpty {
                    Text(suggestion.headings.prefix(4).joined(separator: " · "))
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(suggestion.alreadyExists ? "갱신" : "만들기", action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(11)
        .background(
            PopoverChrome.card,
            in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous)
                .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
        )
    }
}
