import Foundation
import SwiftData

/// V1~V3 이 **디스크에 남긴** `AchievementGoalRecord` 의 모양. 얼려 둔 사본이다.
///
/// ⚠️ **이 파일은 고치지 않는다.**
///
/// 왜 사본이 필요한가 — `HorongHorongSchemaV1`~`V3` 은 모델을 «살아 있는 타입» 으로
/// 참조했다(`AchievementGoalRecord.self`). 그러면 그 타입에 필드를 하나 더하는 순간
/// **선언된 모든 버전의 모양이 함께 바뀌어**, 디스크의 저장소가 어느 버전과도 맞지 않게 된다.
/// SwiftData 는 그때 `Cannot use staged migration with an unknown model version` 으로
/// 저장소 열기를 통째로 거부한다. 버전을 하나 더 올려도 마찬가지다 — 새 버전도 같은
/// 살아 있는 타입을 보기 때문이다.
///
/// 그래서 옛 버전은 **그때의 모양**을 가리켜야 한다. 타입 이름이 `AchievementGoalRecord` 로
/// 같아야 엔티티가 이어지므로 이름은 그대로 두고 이름공간만 다르게 둔다.
///
/// 앞으로 `@Model` 에 필드를 더할 때도 같은 절차가 필요하다:
/// 1. 지금 모양을 이 파일처럼 얼려 사본으로 남긴다
/// 2. 직전 버전이 사본을 가리키게 바꾼다
/// 3. 새 버전을 만들어 살아 있는 타입을 가리키고 `.lightweight` 로 잇는다
enum LegacyAchievementSchema {
    @Model
    final class AchievementGoalRecord {
        var id: UUID
        var title: String
        var emoji: String
        var cadence: String
        var rule: String
        var targetCount: Int
        var targetValueText: String?
        var periodText: String?
        var dueDate: Date?
        var rewardText: String
        var colorHex: String
        var roleName: String
        var vision: String
        var yearGoal: String?
        var quarterGoal: String?
        var monthGoal: String?
        var linkedMemoIDsText: String
        var createdAt: Date
        var updatedAt: Date
        var completedAt: Date?
        var sourceRunID: String?
        var sourceSuggestionID: UUID?

        init(
            id: UUID = UUID(),
            title: String = "",
            emoji: String = "🎯",
            cadence: String = "주간",
            rule: String = "",
            targetCount: Int = 1,
            targetValueText: String? = nil,
            periodText: String? = nil,
            dueDate: Date? = nil,
            rewardText: String = "",
            colorHex: String = "#E87333",
            roleName: String = "나",
            vision: String = "",
            yearGoal: String? = nil,
            quarterGoal: String? = nil,
            monthGoal: String? = nil,
            linkedMemoIDsText: String = "",
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            completedAt: Date? = nil,
            sourceRunID: String? = nil,
            sourceSuggestionID: UUID? = nil
        ) {
            self.id = id
            self.title = title
            self.emoji = emoji
            self.cadence = cadence
            self.rule = rule
            self.targetCount = targetCount
            self.targetValueText = targetValueText
            self.periodText = periodText
            self.dueDate = dueDate
            self.rewardText = rewardText
            self.colorHex = colorHex
            self.roleName = roleName
            self.vision = vision
            self.yearGoal = yearGoal
            self.quarterGoal = quarterGoal
            self.monthGoal = monthGoal
            self.linkedMemoIDsText = linkedMemoIDsText
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.completedAt = completedAt
            self.sourceRunID = sourceRunID
            self.sourceSuggestionID = sourceSuggestionID
        }
    }
}
