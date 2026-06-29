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

    init(
        title: String,
        emoji: String = "🎯",
        cadence: String = "주간",
        rule: String = "",
        targetCount: Int = 1,
        targetValueText: String? = nil,
        periodText: String? = nil,
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
