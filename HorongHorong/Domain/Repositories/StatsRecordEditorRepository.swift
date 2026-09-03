import Foundation

@MainActor
protocol StatsRecordEditorRepository {
    func snapshot(on date: Date) throws -> StatsRecordEditorSnapshot
    func addSegment(_ draft: StatsSegmentDraft) throws
    func updateSegment(id: UUID, draft: StatsSegmentDraft) throws
    func deleteSegment(id: UUID) throws
    func updateFocusSession(id: UUID, draft: StatsFocusSessionDraft) throws
    func deleteFocusSession(id: UUID) throws
}

struct StatsRecordEditorSnapshot: Equatable, Sendable {
    let segments: [StatsEditableSegment]
    let focusSessions: [StatsEditableFocusSession]
}

struct StatsEditableSegment: Equatable, Sendable, Identifiable {
    let id: UUID
    let appName: String
    let category: String
    let start: Date
    let end: Date
    let isManual: Bool
    let isUserModified: Bool

    var durationSeconds: Int {
        max(0, Int(end.timeIntervalSince(start)))
    }
}

struct StatsEditableFocusSession: Equatable, Sendable, Identifiable {
    let id: UUID
    let category: String
    let start: Date
    let end: Date
    let durationSeconds: Int
}

struct StatsSegmentDraft: Equatable, Sendable {
    let appName: String
    let category: String
    let start: Date
    let end: Date
}

struct StatsFocusSessionDraft: Equatable, Sendable {
    let category: String
    let start: Date
    let end: Date
}

enum StatsRecordEditorError: Error, Equatable {
    case recordNotFound
    case missingFocusEnd
}
