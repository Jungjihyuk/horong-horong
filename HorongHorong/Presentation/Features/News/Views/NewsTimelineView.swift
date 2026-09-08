import SwiftUI

/// 분야별 월간 타임라인 화면.
///
/// 파이썬 파이프라인이 만든 `data/timeline/<분야>.json` 을 그대로 그린다. 축/세부 선정과
/// 월 종합은 이미 끝나 있으므로 여기서는 계산하지 않는다.
///
/// **행을 독립 View 구조체로 뽑고 `Equatable` 을 붙인 이유**(CLAUDE.md R3): 사건 수가
/// 분야당 수십~수백 개로 늘어난다. `@ViewBuilder` 헬퍼로 두면 렌더링 경계가 생기지 않아
/// 한 달만 바뀌어도 전부 다시 그린다.
struct NewsTimelineView: View {
    let timeline: NewsTimeline

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                NewsTimelineHeaderView(timeline: timeline)
                    .equatable()

                ForEach(timeline.months) { month in
                    NewsTimelineMonthSection(month: month)
                        .equatable()
                }
            }
            .padding(20)
        }
        .background(PopoverChrome.surface)
    }
}

// MARK: - 머리말

struct NewsTimelineHeaderView: View, Equatable {
    let timeline: NewsTimeline

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(headline)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)

            Text(subtitle)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)

            if !timeline.overview.emphasisKeywords.isEmpty {
                NewsTimelineChipRow(
                    symbol: "sparkles",
                    terms: timeline.overview.emphasisKeywords
                )
                .equatable()
            }

            if !timeline.overview.summary.isEmpty {
                Text(timeline.overview.summary)
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        PopoverChrome.card,
                        in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous)
                    )
            }

            if !timeline.warnings.isEmpty {
                NewsTimelineWarningsView(warnings: timeline.warnings)
                    .equatable()
            }
        }
    }

    private var headline: String {
        "\(timeline.categoryLabel) — 월별 핵심 사건 타임라인"
    }

    /// 목업의 요약 줄과 같은 정보를 담는다.
    private var subtitle: String {
        var parts: [String] = []
        if !timeline.dateFrom.isEmpty, !timeline.dateTo.isEmpty {
            parts.append("\(timeline.dateFrom) ~ \(timeline.dateTo)")
        }
        parts.append("\(timeline.totalEventCount)개 시점")
        parts.append("\(timeline.months.count)개월")
        parts.append("전환점 \(timeline.turningPointMonthKeys.count)곳")
        return parts.joined(separator: " · ")
    }
}

struct NewsTimelineWarningsView: View, Equatable {
    let warnings: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - 월

struct NewsTimelineMonthSection: View, Equatable {
    let month: NewsTimelineMonth

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            monthHeader

            if !month.summary.isEmpty {
                Text(month.summary)
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(Array(month.axisEvents.enumerated()), id: \.element.id) { index, event in
                NewsTimelineAxisCard(event: event, ordinal: index + 1)
                    .equatable()
            }

            detailSection
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            PopoverChrome.card,
            in: RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous)
                .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
        )
    }

    private var monthHeader: some View {
        HStack(spacing: 8) {
            Text(month.displayLabel)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)

            if month.isTurningPoint {
                Text("전환점")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.16), in: Capsule())
                    .foregroundStyle(.red)
            }

            Text(countLabel)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)

            Spacer(minLength: 8)

            if !month.keyTerms.isEmpty {
                Text(month.keyTerms.joined(separator: " · "))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private var countLabel: String {
        "축 \(month.axisEvents.count) · 세부 \(month.detailEvents.count)"
    }

    @ViewBuilder
    private var detailSection: some View {
        if month.detailEvents.isEmpty {
            Text("세부 사건 없음")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("세부 사건 · 우선순위순")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)

                ForEach(month.detailEvents) { event in
                    NewsTimelineDetailRow(event: event)
                        .equatable()
                }
            }
        }
    }
}

// MARK: - 사건

struct NewsTimelineAxisCard: View, Equatable {
    let event: NewsTimelineEvent
    let ordinal: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("축 \(ordinal)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(PopoverChrome.accentSoft.opacity(0.5), in: Capsule())
                    .foregroundStyle(PopoverChrome.accent)

                Text(event.shortDate)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)

                Text("중요도 \(event.importance)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }

            NewsTimelineTitleText(title: event.title, url: event.linkURL, size: 13)
                .equatable()

            ForEach(event.bullets, id: \.self) { bullet in
                Text("· \(bullet)")
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !event.whyItMatters.isEmpty {
                Text(event.whyItMatters)
                    .font(.system(size: 11.5, design: .rounded))
                    .italic()
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !event.tags.isEmpty {
                NewsTimelineChipRow(symbol: "tag", terms: event.tags)
                    .equatable()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            PopoverChrome.surface,
            in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous)
        )
    }
}

struct NewsTimelineDetailRow: View, Equatable {
    let event: NewsTimelineEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(event.shortDate)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)

                if let rank = event.rank {
                    Text("\(rank)순위")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                }

                Text("중요도 \(event.importance)")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }

            NewsTimelineTitleText(title: event.title, url: event.linkURL, size: 12)
                .equatable()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 제목. 원문 URL 이 있으면 링크로 연다.
struct NewsTimelineTitleText: View, Equatable {
    let title: String
    let url: URL?
    let size: CGFloat

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
            .font(.system(size: size, weight: .medium, design: .rounded))
            .foregroundStyle(PopoverChrome.ink)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
    }
}

struct NewsTimelineChipRow: View, Equatable {
    let symbol: String
    let terms: [String]

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(PopoverChrome.inkTertiary)

            Text(terms.joined(separator: " · "))
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)
                .lineLimit(2)
        }
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

/// 타임라인 모드의 내용. 분야가 여럿이면 왼쪽에서 고른다.
struct NewsTimelinePane: View {
    @Bindable var viewModel: NewsTimelineViewModel

    var body: some View {
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
            Text("\(viewModel.timelines.count)개 분야")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 6)

            ForEach(viewModel.timelines) { timeline in
                categoryButton(timeline)
            }

            Spacer(minLength: 0)
        }
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

    /// 타임라인은 앱이 만들지 않는다. 어떻게 만드는지 알려줘야 막다른 화면이 되지 않는다.
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 28))
                .foregroundStyle(PopoverChrome.inkTertiary)
            Text("아직 타임라인이 없습니다")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)
            Text("리포트가 쌓인 뒤 타임라인 생성을 한 번 돌리면 분야별 흐름이 여기 나타납니다.")
                .font(.system(size: 11.5, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PopoverChrome.surface)
    }
}
