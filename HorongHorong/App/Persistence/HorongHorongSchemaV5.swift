import Foundation
import SwiftData

/// 저장소의 다섯 번째 버전.
///
/// 일기의 수면에 «몇 시부터 몇 시까지»(`Diary.sleepStart`·`sleepEnd`)를 더했다. 길이만 적던
/// 기록으로는 잠든 시각이 규칙적인지 알 수 없어 타임라인을 그릴 수 없다.
///
/// 두 필드 모두 Optional 이라 옛 행은 `nil` 로 열리고, 그 행의 `sleepHours` 는 그대로 남는다.
/// 모델 목록은 V4 와 같다.
enum HorongHorongSchemaV5: VersionedSchema {
    nonisolated static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

    nonisolated static var models: [any PersistentModel.Type] {
        [
            Todo.self,
            QuickNote.self,
            LegacyReferenceSchema.Reference.self,
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
