import Foundation

/// 넛지 발동 기록 한 건. SwiftData 모델과 분리해 집계 로직만 따로 테스트한다.
struct FocusNudgeRecord: Equatable {
    let firedAt: Date
    let category: String
}

/// 한 주의 몰입 추이.
struct FocusTrendWeek: Identifiable, Equatable {
    var id: Date { weekStart }
    let weekStart: Date
    let sessionCount: Int
    /// 기준선을 지킨 세션 비율(0...1).
    let onTargetRatio: Double
    /// 그 주에 들은 잔소리 횟수.
    let nudgeCount: Int
}

/// 카테고리별 주간 몰입도 한 점.
struct FocusCategoryTrendPoint: Identifiable, Equatable {
    var id: String { "\(category)|\(weekStart.timeIntervalSince1970)" }
    let category: String
    let weekStart: Date
    let meanScore: Double
    let sessionCount: Int
}

enum FocusTrendBuilder {
    /// 추이를 볼 주 수.
    static let weekCount = 8

    /// 주별 기준선 달성률과 잔소리 횟수.
    ///
    /// 달성률은 **그 주에 적용된 기준선이 아니라 지금 기준선**으로 다시 계산한다.
    /// 기준선을 바꿔가며 보는 화면이라, 과거 기준선을 섞으면 선을 옮겨도 과거가 그대로여서
    /// 무엇을 비교하는지 알 수 없게 된다.
    static func weeks(
        samples: [FocusScoreSample],
        nudges: [FocusNudgeRecord],
        threshold: (String) -> Double,
        calendar: Calendar = .current
    ) -> [FocusTrendWeek] {
        var sessionsByWeek: [Date: (total: Int, onTarget: Int)] = [:]
        for sample in samples {
            guard let weekStart = weekStart(of: sample.startedAt, calendar: calendar) else { continue }
            var bucket = sessionsByWeek[weekStart] ?? (0, 0)
            bucket.total += 1
            if sample.score.value >= threshold(sample.category) {
                bucket.onTarget += 1
            }
            sessionsByWeek[weekStart] = bucket
        }

        var nudgesByWeek: [Date: Int] = [:]
        for nudge in nudges {
            guard let weekStart = weekStart(of: nudge.firedAt, calendar: calendar) else { continue }
            nudgesByWeek[weekStart, default: 0] += 1
        }

        // 세션이 있었던 주만 그린다. 쉰 주까지 0% 로 찍으면 추세가 왜곡된다.
        return sessionsByWeek.keys.sorted().map { weekStart in
            let bucket = sessionsByWeek[weekStart] ?? (0, 0)
            return FocusTrendWeek(
                weekStart: weekStart,
                sessionCount: bucket.total,
                onTargetRatio: bucket.total > 0
                    ? Double(bucket.onTarget) / Double(bucket.total)
                    : 0,
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
                        meanScore: bucket.count > 0 ? bucket.sum / Double(bucket.count) : 0,
                        sessionCount: bucket.count
                    )
                }
            }
            .sorted {
                $0.weekStart != $1.weekStart
                    ? $0.weekStart < $1.weekStart
                    : $0.category < $1.category
            }
    }

    static func weekStart(of date: Date, calendar: Calendar = .current) -> Date? {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
    }
}
