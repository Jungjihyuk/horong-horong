import Foundation

enum PomodoroComparisonSegmentScope {
    static func includedSessionIDs(
        sessions: [StatsFocusSession]
    ) -> Set<UUID> {
        Set(sessions.map(\.id))
    }
}
