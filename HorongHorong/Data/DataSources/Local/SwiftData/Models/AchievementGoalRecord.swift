import Foundation
import SwiftData

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
    /// 사용자가 지정한 마감일. 지정하지 않으면 nil이고, 기한 지남 표시도 하지 않는다.
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
    /// 이 목표가 **달성된 순간**. 아직이면 `nil`.
    ///
    /// 달성 여부는 원래 «묶인 할일이 다 끝났나»(`done >= total`)로 **매번 계산**했다.
    /// 그런데 그 값은 지금 남아 있는 할일로부터 나오므로 **나중에 바뀐다** —
    /// 할일을 더 묶으면 달성이 풀리고, 묶인 할일을 지우면 달성으로 바뀌기도 한다.
    ///
    /// 달성은 **사건**이지 상태가 아니다. 몇 달 뒤에 같은 질문을 해도 같은 답이 나오려면
    /// 그때 찍어 둬야 한다(→ 평가 문서 [4] 채택 후 달성률).
    var completedAt: Date?
    /// 이 목표가 **어느 추천 실행에서 왔나.** 직접 만들었으면 `nil`.
    ///
    /// 이게 없으면 «AI 추천을 채택한 목표» 와 «직접 만든 목표» 를 가릴 수 없어
    /// 채택률·달성률을 낼 수 없다. 적용한 순간에만 알 수 있으므로 소급이 불가능하다.
    var sourceRunID: String?
    /// 추천 카드의 id. 같은 실행에서 나온 여러 제안 중 어느 것이었나.
    var sourceSuggestionID: UUID?

    init(
        title: String,
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
        linkedMemoIDs: [UUID] = []
    ) {
        self.id = UUID()
        self.title = title
        self.emoji = emoji
        self.cadence = cadence
        self.rule = rule
        self.targetCount = max(1, targetCount)
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
        self.linkedMemoIDsText = linkedMemoIDs.map(\.uuidString).joined(separator: ",")
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

extension AchievementGoalRecord {
    var linkedMemoIDs: [UUID] {
        get {
            linkedMemoIDsText
                .split(separator: ",")
                .compactMap { UUID(uuidString: String($0)) }
        }
        set {
            linkedMemoIDsText = newValue.map(\.uuidString).joined(separator: ",")
            updatedAt = Date()
        }
    }
}
