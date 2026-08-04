import Foundation

/// 한 주의 몰입 추이.
struct FocusTrendWeek: Identifiable, Equatable {
    var id: Date { weekStart }
    let weekStart: Date
    /// 그 주에 들은 잔소리 횟수.
    let nudgeCount: Int
}

/// 카테고리별 주간 몰입도 한 점.
struct FocusCategoryTrendPoint: Identifiable, Equatable {
    var id: String { "\(category)|\(weekStart.timeIntervalSince1970)" }
    let category: String
    let weekStart: Date
    let meanScore: Double
}

enum FocusTrendBuilder {
    /// 추이를 볼 주 수.
    static let weekCount = 8

    /// 실제 표시된 잔소리를 주별로 센다. 세션 전체 점수를 현재 기준으로 다시 판정하지 않는다.
    static func weeks(
        samples: [FocusScoreSample],
        nudgeDates: [Date],
        calendar: Calendar = .current
    ) -> [FocusTrendWeek] {
        var weekStarts: Set<Date> = []
        for sample in samples {
            guard let weekStart = weekStart(of: sample.startedAt, calendar: calendar) else { continue }
            weekStarts.insert(weekStart)
        }

        var nudgesByWeek: [Date: Int] = [:]
        for date in nudgeDates {
            guard let weekStart = weekStart(of: date, calendar: calendar) else { continue }
            nudgesByWeek[weekStart, default: 0] += 1
            weekStarts.insert(weekStart)
        }

        return weekStarts.sorted().map { weekStart in
            return FocusTrendWeek(
                weekStart: weekStart,
                nudgeCount: nudgesByWeek[weekStart] ?? 0
            )
        }
    }

    /// 카테고리별 주간 평균 몰입도.
    static func categoryWeeks(
        samples: [FocusScoreSample],
        calendar: Calendar = .current
    ) -> [FocusCategoryTrendPoint] {
        var buckets: [String: [Date: (sum: Double, count: Int)]] = [:]
        for sample in samples {
            guard sample.score.isMeasurable else { continue }
            guard let weekStart = weekStart(of: sample.startedAt, calendar: calendar) else { continue }
            var byWeek = buckets[sample.category] ?? [:]
            var bucket = byWeek[weekStart] ?? (0, 0)
            bucket.sum += sample.score.value
            bucket.count += 1
            byWeek[weekStart] = bucket
            buckets[sample.category] = byWeek
        }

        return buckets
            .flatMap { category, byWeek in
                byWeek.map { weekStart, bucket in
                    FocusCategoryTrendPoint(
                        category: category,
                        weekStart: weekStart,
                        meanScore: bucket.count > 0 ? bucket.sum / Double(bucket.count) : 0
                    )
                }
            }
            .sorted {
                $0.weekStart != $1.weekStart
                    ? $0.weekStart < $1.weekStart
                    : $0.category < $1.category
            }
    }

    private static func weekStart(of date: Date, calendar: Calendar = .current) -> Date? {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
    }
}
