import Foundation

/// 건강 앱 수면 구간에서 그날의 수면 시간을 계산한다.
enum HealthSleepMath {
    struct Interval: Equatable {
        var start: Date
        var end: Date
    }

    /// Apple Watch 수면 단계. inBed / awake 는 제외한다.
    static let asleepValues: Set<Int> = [1, 3, 4, 5]

    /// 그날 일기용 수면 창: 전날 18시 ~ 당일 18시.
    static func window(forDay day: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let startOfDay = calendar.startOfDay(for: day)
        let start = calendar.date(byAdding: .hour, value: -6, to: startOfDay) ?? startOfDay
        let end = calendar.date(byAdding: .hour, value: 18, to: startOfDay) ?? startOfDay
        return (start, end)
    }

    static func hours(
        from samples: [(start: Date, end: Date, value: Int)],
        window: (start: Date, end: Date)
    ) -> Double? {
        let intervals = samples.compactMap { sample -> Interval? in
            guard asleepValues.contains(sample.value) else { return nil }
            let start = max(sample.start, window.start)
            let end = min(sample.end, window.end)
            guard end > start else { return nil }
            return Interval(start: start, end: end)
        }
        let hours = mergedHours(intervals)
        guard hours > 0 else { return nil }
        return roundedToHalfHour(min(14, hours))
    }

    static func mergedHours(_ intervals: [Interval]) -> Double {
        let merged = merge(intervals)
        let seconds = merged.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) }
        return seconds / 3600
    }

    static func roundedToHalfHour(_ hours: Double) -> Double {
        (hours * 2).rounded() / 2
    }

    static func merge(_ intervals: [Interval]) -> [Interval] {
        let sorted = intervals
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
        guard var current = sorted.first else { return [] }
        var result: [Interval] = []
        for next in sorted.dropFirst() {
            if next.start <= current.end {
                current.end = max(current.end, next.end)
            } else {
                result.append(current)
                current = next
            }
        }
        result.append(current)
        return result
    }
}
