import Foundation
import SwiftData

/// 저장소의 세 번째 버전.
///
/// 'Second Brain'의 짬뽕 단일 테이블(`SecondBrainRecord`)을 도메인별 전용 모델로 분리:
/// - `Todo.self` (할 일 전용, `ZTODO`)
/// - `QuickNote.self` (빠른 메모 전용, `ZQUICKNOTE`)
/// - `Reference.self` (참고 자료 전용, `ZREFERENCE`)
/// - `Diary.self` (일기 전용, `ZDIARY`, 기존 `DiaryEntry` 대체)
///
/// 기존 `SecondBrainRecord` 및 `DiaryEntry` 데이터를 읽어 안전하게 1:1 분류 복사하기 위해
/// 구 모델들을 함께 등록한다 (Lightweight 마이그레이션 호환).
enum HorongHorongSchemaV3: VersionedSchema {
    nonisolated static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

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
