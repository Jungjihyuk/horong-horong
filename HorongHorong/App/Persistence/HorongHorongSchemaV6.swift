import Foundation
import SwiftData

/// 저장소의 여섯 번째 버전.
///
/// 참고 자료에 갈래(`kindRaw`)와 구조를 더했다. 예전에는 `content` 한 덩어리에 다 넣고
/// 링크인지 쪽지인지를 읽을 때마다 추측했는데, 그러면 링크의 제목과 주소를 따로 적을 수 없다.
/// 쪽지 색(`colorRaw`)과 위젯 상태(`isWidget`·`widgetX`·`widgetY`)도 여기서 생겼다.
///
/// 새 필드는 전부 Optional 이라 옛 행은 `nil` 로 열리고, 값은 앱 시작 때 한 번 백필된다.
/// 모델 목록은 V5 와 같고 `Reference` 만 살아 있는 타입을 가리킨다.
enum HorongHorongSchemaV6: VersionedSchema {
    nonisolated static var versionIdentifier: Schema.Version { Schema.Version(6, 0, 0) }

    nonisolated static var models: [any PersistentModel.Type] {
        [
            Todo.self,
            QuickNote.self,
            LegacyReferenceV6Schema.Reference.self,
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
