import Foundation
import SwiftData

enum BreakTransitionDecisionKind: String, CaseIterable {
    case sameTaskReturn
    case plannedTaskSwitch
    case externalTransition
    case dayEnded
    case unresolvedBreak
}

@Model
final class BreakTransitionIntent {
    var id: UUID
    var breakEndedAt: Date
    var decidedAt: Date
    var decisionRawValue: String
    var previousCategory: String
    var nextCategory: String?

    init(
        breakEndedAt: Date,
        decision: BreakTransitionDecisionKind,
        previousCategory: String,
        nextCategory: String? = nil,
        decidedAt: Date = Date()
    ) {
        self.id = UUID()
        self.breakEndedAt = breakEndedAt
        self.decidedAt = decidedAt
        self.decisionRawValue = decision.rawValue
        self.previousCategory = previousCategory
        self.nextCategory = nextCategory
    }

    var decision: BreakTransitionDecisionKind {
        BreakTransitionDecisionKind(rawValue: decisionRawValue) ?? .unresolvedBreak
    }
}
