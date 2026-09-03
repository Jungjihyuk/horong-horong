import Foundation

/// 연속된 세션 시간에서 일시정지 구간을 잘라 실제 집중 구간만 만든다.
enum FocusSessionActivityIntervals {
    static func make(
        startedAt: Date,
        endedAt: Date,
        excluding pauses: [FocusSessionPauseInterval],
        maximumActiveSeconds: TimeInterval? = nil
    ) -> [DateInterval] {
        guard endedAt > startedAt else { return [] }

        var intervals: [DateInterval] = []
        var cursor = startedAt
        for pause in pauses.sorted(by: { $0.startedAt < $1.startedAt }) {
            let pauseStart = max(startedAt, pause.startedAt)
            let pauseEnd = min(endedAt, pause.endedAt)
            guard pauseEnd > cursor else { continue }

            if pauseStart > cursor {
                intervals.append(DateInterval(start: cursor, end: min(pauseStart, endedAt)))
            }
            cursor = max(cursor, pauseEnd)
            guard cursor < endedAt else { break }
        }
        if cursor < endedAt {
            intervals.append(DateInterval(start: cursor, end: endedAt))
        }

        guard let maximumActiveSeconds else { return intervals }
        var remaining = max(0, maximumActiveSeconds)
        var limited: [DateInterval] = []
        for interval in intervals where remaining > 0 {
            let duration = min(interval.duration, remaining)
            guard duration > 0 else { continue }
            limited.append(
                DateInterval(
                    start: interval.start,
                    end: interval.start.addingTimeInterval(duration)
                )
            )
            remaining -= duration
        }
        return limited
    }
}
