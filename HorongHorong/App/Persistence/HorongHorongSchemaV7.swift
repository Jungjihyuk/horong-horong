import Foundation
import SwiftData

/// 저장소의 일곱 번째 버전.
///
/// 떠 있는 쪽지 위젯의 **창 크기와 접힘 상태**를 더했다. 크기를 조절해 놓고 앱을 껐다 켰을 때
/// 원래대로 돌아가면 위치만 기억하던 것과 같은 불편이 남는다.
///
/// 새 필드는 전부 Optional 이라 옛 행은 `nil` 로 열리고, 그때는 기본 크기로 뜬다.
enum HorongHorongSchemaV7: VersionedSchema {
    nonisolated static var versionIdentifier: Schema.Version { Schema.Version(7, 0, 0) }

    nonisolated static var models: [any PersistentModel.Type] {
        [
            Todo.self,
            QuickNote.self,
            LegacyReferenceV7Schema.Reference.self,
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
