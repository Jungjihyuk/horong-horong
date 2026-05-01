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

    var levelLabel: String {
        switch level {
        case .focused: return "집중"
        case .moderate: return "보통"
        case .scattered: return "산만"
        case .empty: return "기록 없음"
        }
    }

    var levelColor: Color {
        switch level {
        case .focused: return .green
        case .moderate: return .yellow
        case .scattered: return .red
        case .empty: return .gray
        }
    }

    var levelEmoji: String {
        switch level {
        case .focused: return "🟢"
        case .moderate: return "🟡"
        case .scattered: return "🔴"
        case .empty: return "⚪️"
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

    /// 하루 전체 요약. 최장 집중 구간은 "같은 카테고리 + 2분 이하 간극"은 이어진 것으로 본다.
    /// buckets 가 이미 짝 카테고리/타이머 세션 예외를 반영하기 때문에 overallScore 는 그 보정을 자동으로 상속한다.
    /// 요약의 전환 횟수 필드도 동일 예외를 적용한다.
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

        let pairs = CategoryPairStore.shared
        var switches = 0
        var lastCategory: String? = nil
        for seg in clipped {
            if let last = lastCategory, last != seg.category {
                let exempt = pairs.contains(last, seg.category)
                    || isInTimerSession(seg.start, sessions: timerSessions)
                if !exempt { switches += 1 }
            }
            lastCategory = seg.category
        }

        let maxGap: TimeInterval = 120
        var longest: TimeInterval = 0
        var runStart: Date? = nil
        var runEnd: Date? = nil
        var runCat: String? = nil
        for seg in clipped {
            if let rc = runCat, rc == seg.category, let re = runEnd, seg.start.timeIntervalSince(re) <= maxGap {
                runEnd = seg.end
            } else {
                if let rs = runStart, let re = runEnd {
                    longest = max(longest, re.timeIntervalSince(rs))
                }
                runStart = seg.start
                runEnd = seg.end
                runCat = seg.category
            }
        }
        if let rs = runStart, let re = runEnd {
            longest = max(longest, re.timeIntervalSince(rs))
        }

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

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 6) {
                Text(summary.levelEmoji).font(.title3)
                Text(summary.levelLabel).font(.callout.bold())
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(summary.levelColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(summary.levelColor.opacity(0.35), lineWidth: 1)
            )

            Divider().frame(height: 28)

            metric(label: "최장 집중", value: formatDuration(summary.longestFocusSeconds))
            metric(label: "작업 전환", value: "\(summary.switches)회")
            if let top = summary.topCategory {
                metric(
                    label: "주 작업",
                    value: "\(Constants.categoryEmoji(for: top)) \(top)"
                )
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.bold())
                .monospacedDigit()
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
                legendHint
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("시간대별 작업")
                .font(.headline)
            Spacer()
            if let h = hovered {
                Text(hoverLabel(h))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text("막대가 길수록 오래, 흐릿할수록 산만한 시간대에요 (설정에서 시간 범위·간격 조정)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
        .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
    }

    private func bucketRow(_ bucket: TimelineBucket) -> some View {
        let isHovered = hovered == bucket
        let fillRatio = CGFloat(bucket.totalSeconds) / CGFloat(max(1, Int(bucketSeconds)))
        return HStack(spacing: 8) {
            Text(timeLabel(bucket.startTime))
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)

            GeometryReader { geo in
                let fullWidth = geo.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.08))
                    HStack(spacing: 0) {
                        ForEach(bucket.sortedCategories, id: \.category) { entry in
                            let segFrac = CGFloat(entry.seconds) / CGFloat(max(1, bucket.totalSeconds))
                            Rectangle()
                                .fill(Constants.categoryColor(for: entry.category))
                                .frame(width: fullWidth * fillRatio * segFrac)
                        }
                        Spacer(minLength: 0)
                    }
                    .saturation(0.15 + 0.85 * bucket.focusScore)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(isHovered ? Color.accentColor : .clear, lineWidth: 1.5)
                )
            }
            .frame(height: 14)

            // 전환 4회 이상 경고 점
            Group {
                if bucket.switches >= 4 {
                    Circle()
                        .fill(Color.red.opacity(0.8))
                        .frame(width: 5, height: 5)
                } else {
                    Color.clear.frame(width: 5, height: 5)
                }
            }
            .frame(width: 10)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .contentShape(Rectangle())
    }

    private func timeLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: date)
    }

    private var legendHint: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Rectangle().fill(Color.blue).frame(width: 10, height: 10).cornerRadius(2)
                Text("집중").font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                Rectangle().fill(Color.blue).saturation(0.15).frame(width: 10, height: 10).cornerRadius(2)
                Text("산만").font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                Circle().fill(Color.red.opacity(0.8)).frame(width: 4, height: 4)
                Text("전환 4회 이상").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.top, 2)
    }

    private var noDataView: some View {
        VStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(emptyTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(emptyDetail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private func hoverLabel(_ bucket: TimelineBucket) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        let s = fmt.string(from: bucket.startTime)
        let e = fmt.string(from: bucket.endTime)
        let top = bucket.sortedCategories.first.map { "\(Constants.categoryEmoji(for: $0.category)) \($0.category)" } ?? "-"
        let mins = bucket.totalSeconds / 60
        return "\(s)–\(e) · \(top) · 활동 \(mins)분 · 전환 \(bucket.switches)회"
    }
}
