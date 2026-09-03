import Foundation

extension PomodoroComparisonSegmentScope {
    static func includedSessionIDs(
        sessions: [FocusSession]
    ) -> Set<UUID> {
        Set(sessions.map(\.id))
    }
}
