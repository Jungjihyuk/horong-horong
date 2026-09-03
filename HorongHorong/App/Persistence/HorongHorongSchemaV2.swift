import Foundation
import SwiftData

/// 저장소의 두 번째 버전.
///
/// '메모'에서 'Second Brain / 기록'으로의 확장을 위해 `SecondBrainRecord`를 추가했다.
/// 기존 `Memo` 테이블의 데이터를 읽어 이전하기 위해 `Memo.self`와 `SecondBrainRecord.self`를
/// 둘 다 등록한다 (Lightweight 마이그레이션 호환).
enum HorongHorongSchemaV2: VersionedSchema {
    nonisolated static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    nonisolated static var models: [any PersistentModel.Type] {
        [
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
