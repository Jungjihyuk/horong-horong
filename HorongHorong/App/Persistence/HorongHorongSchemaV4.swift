import Foundation
import SwiftData

/// 저장소의 네 번째 버전.
///
/// 목표에 «못 이룬 채 닫힌 순간»(`closedAt`·`closedReasonRaw`)을 더했다. 마감을 넘긴 목표를
/// 실패로 마감하고 패널티를 매기려면 그 순간을 저장해야 한다.
///
/// V3 과의 차이는 `AchievementGoalRecord` 하나뿐이다 — V3 은 얼려 둔 옛 모양
/// (`LegacyAchievementSchema.AchievementGoalRecord`)을, 여기서는 살아 있는 타입을 가리킨다.
enum HorongHorongSchemaV4: VersionedSchema {
    nonisolated static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    nonisolated static var models: [any PersistentModel.Type] {
        [
            Todo.self,
            QuickNote.self,
            Reference.self,
            Diary.self,
            SecondBrainRecord.self,
            Memo.self,
            DiaryEntry.self,
            AchievementGoalRecord.self,
            FocusSession.self,
            PomodoroReflection.self,
            CategoryBehaviorConditionSet.self,
            PomodoroTaskCompletion.self,
            AppUsageRecord.self,
            AppUsageSegment.self,
            BreakTransitionIntent.self,
            AttentionEvent.self,
            AttentionDaySummary.self,
            FocusNudgeEvent.self,
            StatsAggregateCache.self,
            AppCategoryRule.self,
            NewsJob.self,
            NewsReportIndex.self,
            RewardLedgerEntry.self,
            RewardCatalogItem.self,
        ]
    }
}
