import Foundation
import SwiftData

enum AttentionEventVerdict: String, CaseIterable {
    case distraction
    case notDistraction
    case misclassified

    var label: String {
        switch self {
        case .distraction: return "신호 맞음"
        case .notDistraction: return "방해 아님"
        case .misclassified: return "분류 오류"
        }
    }
}

@Model
final class AttentionEvent {
    var id: UUID
    var fingerprint: String
    var eventType: String
    var occurredAt: Date
    var sourceApp: String
    var sourceCategory: String
    var targetCategory: String?
    var durationSeconds: Int
    var verdictRawValue: String
    var createdAt: Date
    var updatedAt: Date

    init(
        fingerprint: String,
        eventType: String,
        occurredAt: Date,
        sourceApp: String,
        sourceCategory: String,
        targetCategory: String?,
        durationSeconds: Int,
        verdict: AttentionEventVerdict
    ) {
        self.id = UUID()
        self.fingerprint = fingerprint
        self.eventType = eventType
        self.occurredAt = occurredAt
        self.sourceApp = sourceApp
        self.sourceCategory = sourceCategory
        self.targetCategory = targetCategory
        self.durationSeconds = durationSeconds
        self.verdictRawValue = verdict.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var verdict: AttentionEventVerdict {
        get { AttentionEventVerdict(rawValue: verdictRawValue) ?? .distraction }
        set {
            verdictRawValue = newValue.rawValue
            updatedAt = Date()
        }
    }
}

@Model
final class AttentionDaySummary {
    var id: UUID
    var day: Date
    var dayKey: String
    var levelRawValue: String
    var overallScore: Double
    var selectiveEventCount: Int
    var sustainedEventCount: Int
    var returnEventCount: Int
    var representativeReason: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        day: Date,
        dayKey: String,
        flowState: AttentionFlowState,
        overallScore: Double,
        selectiveEventCount: Int,
        sustainedEventCount: Int,
        returnEventCount: Int,
        representativeReason: String?
    ) {
        self.id = UUID()
        self.day = day
        self.dayKey = dayKey
        self.levelRawValue = flowState.rawValue
        self.overallScore = overallScore
        self.selectiveEventCount = selectiveEventCount
        self.sustainedEventCount = sustainedEventCount
        self.returnEventCount = returnEventCount
        self.representativeReason = representativeReason
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var flowState: AttentionFlowState {
        get { AttentionFlowState.fromLegacyValue(levelRawValue) }
        set {
            levelRawValue = newValue.rawValue
            updatedAt = Date()
        }
    }
}
