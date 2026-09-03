import Foundation

/// 한 구간을 **날짜별로** 나눈다. 자정을 넘겨 쓴 시간을 하루씩 나눠 기록하기 위해서다.
///
/// 순수 계산이라 저장소도 화면도 없이 검사한다.
/// 원래 `AppTracker` 안의 `static func` 이었다. 2026-09-03 이동.
enum AppUsageDaySlicer {
    struct Slice: Equatable {
        let date: Date
        let durationSeconds: Int
    }

    /// 초 단위 합이 원래 구간 길이와 정확히 같도록 나머지를 큰 소수부터 1초씩 나눠 준다.
    /// 그냥 내림하면 하루씩 잃어버려 총합이 줄어든다.
    static func slices(
        from start: Date,
        to end: Date,
        calendar: Calendar = .current
    ) -> [Slice] {
        guard end > start else { return [] }

        var cursor = start
        var rawSlices: [(date: Date, duration: TimeInterval)] = []
        while cursor < end {
            let dayStart = calendar.startOfDay(for: cursor)
            guard let nextDay = calendar.date(
                byAdding: .day,
                value: 1,
                to: dayStart
            ), nextDay > cursor else {
                break
            }

            let sliceEnd = min(end, nextDay)
            rawSlices.append((
                date: dayStart,
                duration: sliceEnd.timeIntervalSince(cursor)
            ))
            cursor = sliceEnd
        }

        var durationSeconds = rawSlices.map { max(0, Int($0.duration)) }
        var remainingSeconds = max(0, Int(end.timeIntervalSince(start)))
            - durationSeconds.reduce(0, +)
        let remainderOrder = rawSlices.indices.sorted {
            let lhsFraction = rawSlices[$0].duration.rounded(.down)
            let rhsFraction = rawSlices[$1].duration.rounded(.down)
            let lhsRemainder = rawSlices[$0].duration - lhsFraction
            let rhsRemainder = rawSlices[$1].duration - rhsFraction
            if lhsRemainder != rhsRemainder {
                return lhsRemainder > rhsRemainder
            }
            return rawSlices[$0].date < rawSlices[$1].date
        }
        for index in remainderOrder where remainingSeconds > 0 {
            durationSeconds[index] += 1
            remainingSeconds -= 1
        }

        return rawSlices.indices.compactMap { index in
            guard durationSeconds[index] > 0 else { return nil }
            return Slice(
                date: rawSlices[index].date,
                durationSeconds: durationSeconds[index]
            )
        }
    }
}
