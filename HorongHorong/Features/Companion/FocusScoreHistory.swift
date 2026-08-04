import Foundation
import SwiftData

/// 몰입도를 저장소에서 읽어오는 유일한 경계.
///
/// 과거 그래프와 진행 중 세션이 **반드시 같은 `score(start:end:category:segments:)` 를 지난다.**
/// 그래야 "설정 화면 막대에 찍히는 그 숫자" 와 "지금 호로롱이가 보고 있는 숫자" 가 같은 것이 되어,
/// 사용자가 기준선을 어디에 그을지 판단할 수 있다.
enum FocusScoreHistory {
    static let dayCount = 14

    /// 지난 N일의 완료된 포모도로 세션별 몰입도. 시간순.
    static func samples(
        days: Int = dayCount,
        now: Date = Date(),
        modelContext: ModelContext
    ) -> [FocusScoreSample] {
        guard let periodStart = Calendar.current.date(byAdding: .day, value: -days, to: now) else {
            return []
        }

        // 경계에 걸친 세션을 놓치지 않도록 세션 조회만 앞으로 당긴다. (AttentionAnalytics 와 같은 관례)
        let bufferStart = periodStart.addingTimeInterval(-4 * 3600)
        let sessions = (try? modelContext.fetch(
            FetchDescriptor<FocusSession>(
                predicate: #Predicate { $0.startedAt >= bufferStart && $0.startedAt < now },
                sortBy: [SortDescriptor(\.startedAt)]
            )
        )) ?? []

        let windows = sessions.compactMap { session -> (session: FocusSession, end: Date)? in
            guard isCompletedPomodoro(session),
                  let end = focusEnd(for: session),
                  end > session.startedAt,
                  end > periodStart else { return nil }
            return (session, end)
        }
        guard let firstStart = windows.first?.session.startedAt,
              let lastEnd = windows.map(\.end).max() else {
            return []
        }

        let segments = (try? modelContext.fetch(
            FetchDescriptor<AppUsageSegment>(
                predicate: #Predicate { $0.startTime < lastEnd && $0.endTime > firstStart },
                sortBy: [SortDescriptor(\.startTime)]
            )
        )) ?? []

        // 세션과 세그먼트 모두 시간순이라 커서를 전진시키며 훑는다.
        // 세션마다 전체를 다시 훑으면 14일치에서 수십만 번 비교가 된다.
        var cursor = 0
        return windows.map { window in
            while cursor < segments.count, segments[cursor].endTime <= window.session.startedAt {
                cursor += 1
            }
            var index = cursor
            var overlapping: [AppUsageSegment] = []
            while index < segments.count, segments[index].startTime < window.end {
                if segments[index].endTime > window.session.startedAt {
                    overlapping.append(segments[index])
                }
                index += 1
            }

            let category = window.session.category ?? Constants.defaultFocusCategory
            let observation = PomodoroSessionObservationBuilder.observation(
                from: window.session.startedAt,
                to: window.end,
                segments: overlapping
            )
            return FocusScoreSample(
                id: window.session.id,
                startedAt: window.session.startedAt,
                category: category,
                score: FocusScoreCalculator.score(
                    observation: observation,
                    focusCategory: category,
                    isPaired: { CategoryPairStore.shared.contains($0, $1) }
                ),
                categorySeconds: observation.categories.reduce(into: [:]) {
                    $0[$1.category, default: 0] += max(0, $1.durationSeconds)
                }
            )
        }
    }

    /// 진행 중인 세션의 지금까지의 몰입도.
    static func liveScore(
        sessionStart: Date,
        windowEnd: Date,
        focusCategory: String,
        modelContext: ModelContext
    ) -> FocusScore {
        guard windowEnd > sessionStart else { return .zero }
        let segments = (try? modelContext.fetch(
            FetchDescriptor<AppUsageSegment>(
                predicate: #Predicate { $0.startTime < windowEnd && $0.endTime > sessionStart },
                sortBy: [SortDescriptor(\.startTime)]
            )
        )) ?? []

        return score(
            start: sessionStart,
            end: windowEnd,
            category: focusCategory,
            segments: segments
        )
    }

    /// 과거와 실시간이 함께 지나는 단 하나의 계산.
    private static func score(
        start: Date,
        end: Date,
        category: String,
        segments: [AppUsageSegment]
    ) -> FocusScore {
        FocusScoreCalculator.score(
            observation: PomodoroSessionObservationBuilder.observation(
                from: start,
                to: end,
                segments: segments
            ),
            focusCategory: category,
            isPaired: { CategoryPairStore.shared.contains($0, $1) }
        )
    }

    /// 통계 화면과 같은 기준으로 "끝난 포모도로" 를 가린다. (`StatsAggregateCache` 와 동일)
    private static func isCompletedPomodoro(_ session: FocusSession) -> Bool {
        guard let endedAt = session.endedAt else { return false }
        let expectedSeconds = max(0, session.focusMinutes) * 60
        guard expectedSeconds > 0 else { return false }
        return session.completed
            || endedAt.timeIntervalSince(session.startedAt) >= TimeInterval(expectedSeconds)
    }

    /// 집중 창은 계획한 시간을 넘지 않게 자른다.
    private static func focusEnd(for session: FocusSession) -> Date? {
        guard let endedAt = session.endedAt else { return nil }
        let expectedEnd = session.startedAt.addingTimeInterval(
            TimeInterval(max(0, session.focusMinutes) * 60)
        )
        return min(endedAt, expectedEnd)
    }
}
