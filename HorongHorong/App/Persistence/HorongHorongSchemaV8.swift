import Foundation
import SwiftData

/// 저장소의 여덟 번째 버전.
///
/// 떠 있는 쪽지 위젯을 **모든 창 앞에 둘지 뒤에 둘지**(`widgetBehind`)를 더했다.
/// 항상 앞에 있으면 방해가 되고, 항상 뒤에 있으면 자주 볼 수 없다 — 쪽지마다 다르게 정한다.
///
/// Optional 이라 옛 행은 `nil` 로 열리고 그때는 «맨 앞» 으로 읽힌다.
enum HorongHorongSchemaV8: VersionedSchema {
    nonisolated static var versionIdentifier: Schema.Version { Schema.Version(8, 0, 0) }

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
