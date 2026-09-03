import Foundation

struct UnclassifiedAppUsage: Identifiable, Equatable, Sendable {
    let bundleIdentifier: String
    let appName: String
    let durationSeconds: Int

    var id: String { bundleIdentifier }
}

struct UnclassifiedAppAssessment: Equatable, Sendable {
    let apps: [UnclassifiedAppUsage]
    /// 앱으로 귀속할 수 있었던 전체 기록 시간. 겹쳐 어느 앱인지 모르는 시간은 제외한다.
    let recordedAppSeconds: Int
    let unclassifiedAppSeconds: Int

    var unclassifiedRatio: Double {
        guard recordedAppSeconds > 0 else { return 0 }
        return min(1, max(0, Double(unclassifiedAppSeconds) / Double(recordedAppSeconds)))
    }

    var needsClassificationFollowUp: Bool {
        guard !apps.isEmpty, recordedAppSeconds > 0 else { return false }
        return 1 - unclassifiedRatio < FocusScore.minimumClassifiedAppRatio
    }
}

struct ProductivityManagementAppUsage: Identifiable, Equatable, Sendable {
    let bundleIdentifier: String
    let appName: String
    let durationSeconds: Int

    var id: String { bundleIdentifier }
}

enum UnclassifiedAppChoice: Equatable, Sendable {
    case category(String)
    case excluded
}
