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
    /// 이 목표가 **못 이룬 채로 닫힌 순간**. 아직 열려 있으면 `nil`.
    ///
    /// `completedAt` 의 짝이다. 달성이 사건이듯 «못 했다고 인정한 것» 도 사건이다 —
    /// 마감이 지났는지는 지금 계산할 수 있지만, **언제 접었는지는 그 순간에만 알 수 있다.**
    ///
    /// 이 값이 찍히면 목표의 표시 수명이 그 주·그 달에서 끝난다. 안 찍으면 못 끝낸 목표가
    /// 이번 주로 영원히 이월된다.
    var closedAt: Date?
    /// 왜 닫혔나(`AchievementCloseReason` 의 rawValue).
    ///
    /// 문자열로 두는 이유는 `cadence` 와 같다 — 사유를 늘려도 스키마가 바뀌지 않는다.
    var closedReasonRaw: String?

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
    /// 못 이룬 채 닫힌 사유. 알 수 없는 값이 저장돼 있으면 `nil` 로 본다.
    var closedReason: AchievementCloseReason? {
        get { closedReasonRaw.flatMap(AchievementCloseReason.init(rawValue:)) }
        set { closedReasonRaw = newValue?.rawValue }
    }

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
