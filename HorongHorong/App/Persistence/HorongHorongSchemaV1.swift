import Foundation
import SwiftData

/// 저장소의 첫 버전. **지금 디스크에 있는 그대로**를 옮겨 적은 것이다.
///
/// 여태 버전 개념 없이 `Schema([...])` 만 썼다. 필드를 더하는 정도는 SwiftData 가 알아서
/// 처리했지만, **이름 변경·타입 변경은 계획이 없으면 데이터를 못 읽는다.**
/// (`Memo` 의 Optional 필드 10개가 그 흔적이다 — 나중에 추가돼서 옛 행은 값이 비어 있다.)
///
/// ⚠️ **이 파일은 이제 고치지 않는다.**
///
/// 여기 적힌 목록은 «이미 사용자 디스크에 있는 것» 이다. 모델을 더하거나 이름을 바꾸려면
/// 이 파일이 아니라 **V2 를 새로 만들고** `HorongHorongMigrationPlan` 에서 잇는다.
/// 여기를 고치면 그 순간부터 기존 저장소를 열지 못한다.
///
/// 검증: 계획 없이 만든 저장소가 계획을 붙인 컨테이너로 열리는지 `SchemaVersioningTests` 가 확인한다.
/// 실사용 저장소 복사본(190건)으로도 확인했다(2026-09-03).
enum HorongHorongSchemaV1: VersionedSchema {
    nonisolated static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    nonisolated static var models: [any PersistentModel.Type] {
        [
            Memo.self,
            DiaryEntry.self,
            // 얼려 둔 옛 모양. 이유는 `LegacyAchievementGoalRecord.swift` 참고.
            LegacyAchievementSchema.AchievementGoalRecord.self,
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
