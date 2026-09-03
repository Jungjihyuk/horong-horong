import Foundation
import SwiftData

@Model
final class PomodoroReflection {
    var id: UUID
    @Attribute(.unique)
    var focusSessionID: UUID
    var focusExperienceRawValue: String
    var progressResultRawValue: String
    var incompleteReasonRawValue: String?
    var answeredAt: Date
    var schemaVersion: Int

    init(
        focusSessionID: UUID,
        focusExperience: PomodoroFocusExperience,
        progressResult: PomodoroProgressResult,
        incompleteReason: PomodoroIncompleteReason? = nil,
        answeredAt: Date = Date()
    ) {
        self.id = UUID()
        self.focusSessionID = focusSessionID
        self.focusExperienceRawValue = focusExperience.rawValue
        self.progressResultRawValue = progressResult.rawValue
        self.incompleteReasonRawValue = progressResult.requiresReason ? incompleteReason?.rawValue : nil
        self.answeredAt = answeredAt
        self.schemaVersion = 1
    }

    var focusExperience: PomodoroFocusExperience? {
        PomodoroFocusExperience(rawValue: focusExperienceRawValue)
    }

    var progressResult: PomodoroProgressResult? {
        PomodoroProgressResult(rawValue: progressResultRawValue)
    }

    var incompleteReason: PomodoroIncompleteReason? {
        incompleteReasonRawValue.flatMap(PomodoroIncompleteReason.init(rawValue:))
    }

    func updateAnswers(
        focusExperience: PomodoroFocusExperience,
        progressResult: PomodoroProgressResult,
        incompleteReason: PomodoroIncompleteReason?
    ) {
        focusExperienceRawValue = focusExperience.rawValue
        progressResultRawValue = progressResult.rawValue
        incompleteReasonRawValue = progressResult.requiresReason ? incompleteReason?.rawValue : nil
    }
}
