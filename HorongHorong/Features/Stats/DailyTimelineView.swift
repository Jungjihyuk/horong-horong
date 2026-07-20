import SwiftUI
import Charts

// MARK: - Data types

/// 30분 단위 타임라인 버킷. 해당 구간의 카테고리별 누적 시간과 카테고리 전환 횟수를 담는다.
struct TimelineBucket: Identifiable, Equatable {
    var id: Date { startTime }
    let startTime: Date
    let endTime: Date
    let categoryDurations: [String: Int] // seconds
    let switches: Int                    // 구간 내 카테고리 전환 횟수

    var totalSeconds: Int { categoryDurations.values.reduce(0, +) }

    var sortedCategories: [(category: String, seconds: Int)] {
        categoryDurations
            .sorted {
                if $0.value != $1.value { return $0.value > $1.value }
                return $0.key < $1.key
            }
            .map { ($0.key, $0.value) }
    }

    /// Herfindahl 집중도: 0=완전히 분산, 1=단일 작업
    var concentration: Double {
        let total = totalSeconds
        guard total > 0 else { return 1.0 }
        let fractions = categoryDurations.values.map { Double($0) / Double(total) }
        let n = Double(fractions.count)
        guard n > 1 else { return 1.0 }
        let h = fractions.reduce(0) { $0 + $1 * $1 }
        let minH = 1.0 / n
        let norm = (h - minH) / max(0.0001, 1.0 - minH)
        return max(0.0, min(1.0, norm))
    }

    /// 전환이 많을수록 페널티. 30분 내 6회 이상이면 거의 0에 수렴
    var switchPenalty: Double {
        let softCap = 6.0
        return max(0.0, 1.0 - Double(switches) / softCap)
    }

    /// 최종 집중 점수 ∈ [0, 1]
    var focusScore: Double {
        concentration * switchPenalty
    }
}

/// 하루 전체 요약
struct DailyFocusSummary {
    let totalSeconds: Int
    let switches: Int
    let longestFocusSeconds: Int
    let topCategory: String?
    let overallScore: Double // 버킷 focusScore 를 totalSeconds 로 가중평균

    enum Level { case focused, moderate, scattered, empty }

    var level: Level {
        if totalSeconds == 0 { return .empty }
        if overallScore >= 0.55 { return .focused }
        if overallScore >= 0.30 { return .moderate }
        return .scattered
    }

    var flowState: AttentionFlowState {
        switch level {
        case .focused: return .steady
        case .moderate: return .variable
        case .scattered: return .returnNeeded
        case .empty: return .noRecord
        }
    }
}

// MARK: - Analytics

enum TimelineAnalytics {
    static let bucketSeconds: TimeInterval = 30 * 60 // 30분

    /// 주어진 시점이 완료되었거나 중단된 타이머 세션 구간 내에 있는지.
    /// endedAt 이 nil 인 (아직 돌아가는 중이거나 비정상 종료된) 세션은 제외한다 — 과거 분석에만 쓰이므로 안전.
    static func isInTimerSession(_ date: Date, sessions: [FocusSession]) -> Bool {
        for s in sessions {
            guard let end = s.endedAt else { continue }
            if date >= s.startedAt && date < end {
                return true
            }
        }
        return false
    }

    /// 특정 하루의 세그먼트를 버킷(기본 30분)으로 집계한다.
    /// timerSessions 에 해당 날짜와 겹치는 세션을 넘기면, 그 세션 안에서 발생한 카테고리 전환은 카운트하지 않는다.
    /// bucketSeconds 로 버킷 크기를 조정할 수 있다 (타임라인 뷰의 사용자 설정).
    static func buckets(
        for day: Date,
        segments: [AppUsageSegment],
        timerSessions: [FocusSession] = [],
        bucketSeconds customBucketSeconds: TimeInterval? = nil
    ) -> [TimelineBucket] {
        let bucketSeconds = customBucketSeconds ?? Self.bucketSeconds
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

        let clipped: [(start: Date, end: Date, category: String)] = segments.compactMap { seg in
            let s = max(seg.startTime, dayStart)
            let e = min(seg.endTime, dayEnd)
            guard e > s else { return nil }
            return (s, e, seg.category)
        }.sorted { $0.start < $1.start }

        var bucketMap: [Int: [String: Int]] = [:]
        for seg in clipped {
            var cursor = seg.start
            while cursor < seg.end {
                let offset = cursor.timeIntervalSince(dayStart)
                let idx = Int(floor(offset / bucketSeconds))
                let bucketEnd = dayStart.addingTimeInterval(Double(idx + 1) * bucketSeconds)
                let chunkEnd = min(seg.end, bucketEnd)
                let sec = Int(chunkEnd.timeIntervalSince(cursor))
                if sec > 0 {
                    bucketMap[idx, default: [:]][seg.category, default: 0] += sec
                }
                cursor = chunkEnd
            }
        }

        // 카테고리 전환 카운트 — 연속 세그먼트 사이 카테고리가 바뀌면 새 세그먼트가 시작된 버킷에 +1
        // 단, 짝 카테고리로 등록된 쌍이거나 타이머 세션 구간 내의 전환이면 무시한다.
        let pairs = CategoryPairStore.shared
        var switchMap: [Int: Int] = [:]
        var lastCategory: String? = nil
        for seg in clipped {
            if let last = lastCategory, last != seg.category {
                let exempt = pairs.contains(last, seg.category)
                    || isInTimerSession(seg.start, sessions: timerSessions)
                if !exempt {
                    let offset = seg.start.timeIntervalSince(dayStart)
                    let idx = Int(floor(offset / bucketSeconds))
                    switchMap[idx, default: 0] += 1
                }
            }
            lastCategory = seg.category
        }

        return bucketMap.keys.sorted().map { idx in
            let start = dayStart.addingTimeInterval(Double(idx) * bucketSeconds)
            let end = start.addingTimeInterval(bucketSeconds)
            return TimelineBucket(
                startTime: start,
                endTime: end,
                categoryDurations: bucketMap[idx] ?? [:],
                switches: switchMap[idx] ?? 0
            )
        }
    }

    /// 하루 전체 요약. 같은 카테고리의 기록 사이 2분 이하 간극은 같은 구간으로 묶되,
    /// 최장 기록 시간에는 실제로 기록된 시간만 더한다.
    /// buckets 가 이미 짝 카테고리/타이머 세션 예외를 반영하기 때문에 overallScore 는 그 보정을 자동으로 상속한다.
    /// 사용자에게 보여주는 전환 횟수는 예외 규칙을 적용하지 않은 실제 카테고리 변경 횟수다.
    static func summary(
        for day: Date,
        segments: [AppUsageSegment],
        buckets: [TimelineBucket],
        timerSessions: [FocusSession] = []
    ) -> DailyFocusSummary {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else {
            return DailyFocusSummary(totalSeconds: 0, switches: 0, longestFocusSeconds: 0, topCategory: nil, overallScore: 0)
        }

        let clipped: [(start: Date, end: Date, category: String)] = segments.compactMap { seg in
            let s = max(seg.startTime, dayStart)
            let e = min(seg.endTime, dayEnd)
            guard e > s else { return nil }
            return (s, e, seg.category)
        }.sorted { $0.start < $1.start }

        let maxSwitchGap: TimeInterval = 120
        var switches = 0
        var previous: (start: Date, end: Date, category: String)?
        for seg in clipped {
            if let previous {
                let gap = seg.start.timeIntervalSince(previous.end)
                if gap >= 0,
                   gap <= maxSwitchGap,
                   previous.category != seg.category {
                    switches += 1
                }
            }
            previous = seg
        }

        let maxGap: TimeInterval = 120
        var longest: TimeInterval = 0
        var runDuration: TimeInterval = 0
        var runEnd: Date? = nil
        var runCat: String? = nil
        for seg in clipped {
            if let rc = runCat, rc == seg.category, let re = runEnd, seg.start.timeIntervalSince(re) <= maxGap {
                runDuration += seg.end.timeIntervalSince(seg.start)
                runEnd = seg.end
            } else {
                longest = max(longest, runDuration)
                runDuration = seg.end.timeIntervalSince(seg.start)
                runEnd = seg.end
                runCat = seg.category
            }
        }
        longest = max(longest, runDuration)

        var totals: [String: Int] = [:]
        for seg in clipped {
            totals[seg.category, default: 0] += Int(seg.end.timeIntervalSince(seg.start))
        }
        let totalSec = totals.values.reduce(0, +)
        let topCat = totals.max { $0.value < $1.value }?.key

        let totalWeight = buckets.reduce(0) { $0 + $1.totalSeconds }
        let weightedSum = buckets.reduce(0.0) { $0 + $1.focusScore * Double($1.totalSeconds) }
        let overall = totalWeight > 0 ? weightedSum / Double(totalWeight) : 0

        return DailyFocusSummary(
            totalSeconds: totalSec,
            switches: switches,
            longestFocusSeconds: Int(longest),
            topCategory: topCat,
            overallScore: overall
        )
    }
}

// MARK: - Summary card (레이어 1)

struct DailyFocusSummaryCard: View {
    let summary: DailyFocusSummary
    let showsDetailedMetrics: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Label("관찰 기록", systemImage: "chart.xyaxis.line")
                .font(.callout.bold())
                .foregroundStyle(PopoverChrome.ink)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(PopoverChrome.accentSoft.opacity(0.3), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(PopoverChrome.accent.opacity(0.25), lineWidth: 1)
                )

            Rectangle()
                .fill(PopoverChrome.divider)
                .frame(width: 1, height: 28)

            if showsDetailedMetrics {
                metric(label: "같은 카테고리 최장 기록", value: formatDuration(summary.longestFocusSeconds))
                metric(label: "카테고리 전환", value: "\(summary.switches)회")
            }
            if let top = summary.topCategory {
                metric(
                    label: "가장 오래 기록된 카테고리",
                    value: "\(Constants.categoryEmoji(for: top)) \(top)"
                )
            }

            Spacer()
        }
        .popoverCard(padding: 12)
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(PopoverChrome.inkTertiary)
            Text(value)
                .font(.callout.bold())
                .monospacedDigit()
                .foregroundStyle(PopoverChrome.ink)
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

// MARK: - Timeline buckets (레이어 2)

struct DailyTimelineBucketsView: View {
    let buckets: [TimelineBucket]
    /// 각 버킷의 길이(초). 가로 막대 채움 비율 계산에 쓰인다. 사용자 설정에서 결정.
    let bucketSeconds: TimeInterval
    var emptyTitle: String = "이 날짜의 타임라인 기록이 없어요"
    var emptyDetail: String = "타임라인은 이 기능이 추가된 이후의 기록부터 표시됩니다"
    @State private var hovered: TimelineBucket? = nil

    private var hasActivity: Bool {
        buckets.contains { $0.totalSeconds > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if buckets.isEmpty || !hasActivity {
                noDataView
            } else {
                verticalTimeline
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("시간대별 작업")
                .font(.headline)
                .foregroundStyle(PopoverChrome.ink)
            Spacer()
            if let h = hovered {
                Text(hoverLabel(h))
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .monospacedDigit()
            } else {
                Text("막대 길이는 기록 시간, 색상은 카테고리를 보여줘요")
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }
        }
    }

    /// 위에서 아래로 시간이 흐르는 세로 타임라인. 막대 길이/색상은 기존 방식 유지.
    private var verticalTimeline: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(buckets) { bucket in
                    bucketRow(bucket)
                        .onHover { inside in
                            if inside { hovered = bucket }
                            else if hovered == bucket { hovered = nil }
                        }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxHeight: 420)
        .padding(8)
        .background(timelineBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PopoverChrome.border, lineWidth: 1)
        )
    }

    private var timelineBackground: Color {
        if PopoverChrome.isWineLantern {
            return PopoverChrome.card.opacity(0.78)
        }
        return Color.white.opacity(0.55)
    }

    private func bucketRow(_ bucket: TimelineBucket) -> some View {
        let isHovered = hovered == bucket
        let fillRatio = CGFloat(bucket.totalSeconds) / CGFloat(max(1, Int(bucketSeconds)))
        return HStack(spacing: 8) {
            Text(timeLabel(bucket.startTime))
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(PopoverChrome.inkTertiary)
                .frame(width: 44, alignment: .trailing)

            GeometryReader { geo in
                let fullWidth = geo.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(PopoverChrome.surfaceAlt.opacity(0.85))
                    HStack(spacing: 0) {
                        ForEach(bucket.sortedCategories, id: \.category) { entry in
                            let segFrac = CGFloat(entry.seconds) / CGFloat(max(1, bucket.totalSeconds))
                            Rectangle()
                                .fill(Constants.categoryColor(for: entry.category))
                                .frame(width: fullWidth * fillRatio * segFrac)
                        }
                        Spacer(minLength: 0)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(isHovered ? PopoverChrome.accent : .clear, lineWidth: 1.5)
                )
            }
            .frame(height: 14)

        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .background(isHovered ? PopoverChrome.accentSoft.opacity(0.35) : .clear, in: RoundedRectangle(cornerRadius: 6))
    }

    private func timeLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: date)
    }

    private var noDataView: some View {
        VStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title3)
                .foregroundStyle(PopoverChrome.inkTertiary)
            Text(emptyTitle)
                .font(.caption)
                .foregroundStyle(PopoverChrome.inkSecondary)
            Text(emptyDetail)
                .font(.caption2)
                .foregroundStyle(PopoverChrome.inkTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .popoverCard()
    }

    private func hoverLabel(_ bucket: TimelineBucket) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        let s = fmt.string(from: bucket.startTime)
        let e = fmt.string(from: bucket.endTime)
        let top = bucket.sortedCategories.first.map { "\(Constants.categoryEmoji(for: $0.category)) \($0.category)" } ?? "-"
        let mins = bucket.totalSeconds / 60
        return "\(s)–\(e) · \(top) · 기록 \(mins)분"
    }
}
