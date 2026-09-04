import Foundation
import SwiftData

@MainActor
enum PomodoroSessionDeletion {
    @discardableResult
    static func delete(
        _ session: FocusSession,
        modelContext: ModelContext
    ) throws -> Todo? {
        let sessionID = session.id
        let affectedRecord = try PomodoroTaskCompletionRecorder.removeCompletion(
            focusSessionID: sessionID,
            modelContext: modelContext
        )
        let reflectionDescriptor = FetchDescriptor<PomodoroReflection>(
            predicate: #Predicate { $0.focusSessionID == sessionID }
        )
        for reflection in try modelContext.fetch(reflectionDescriptor) {
            modelContext.delete(reflection)
        }
        modelContext.delete(session)
        return affectedRecord
    }

    static func repairOrphanedRecords(modelContext: ModelContext) throws -> [Todo] {
        let existingSessionIDs = Set(
            try modelContext.fetch(FetchDescriptor<FocusSession>()).map(\.id)
        )
        let completions = try modelContext.fetch(FetchDescriptor<PomodoroTaskCompletion>())
        let recordsByID = Dictionary(
            uniqueKeysWithValues: try modelContext.fetch(FetchDescriptor<Todo>()).map {
                ($0.id, $0)
            }
        )
        for completion in completions where completion.didMarkMemoCompleted {
            let stateChangedAt = completion.memoStateChangedAt ?? completion.completedAt
            guard let record = recordsByID[completion.linkedMemoID],
                  record.isCompletedValue,
                  record.completionStateChangedAt == nil,
                  record.updatedAt == stateChangedAt else {
                continue
            }
            record.completionStateChangedAt = stateChangedAt
        }

        let orphanedCompletionSessionIDs = completions
            .map(\.focusSessionID)
            .filter { !existingSessionIDs.contains($0) }

        var affectedRecordsByID: [UUID: Todo] = [:]
        for sessionID in orphanedCompletionSessionIDs {
            if let record = try PomodoroTaskCompletionRecorder.removeCompletion(
                focusSessionID: sessionID,
                modelContext: modelContext
            ) {
                affectedRecordsByID[record.id] = record
            }
        }

        let orphanedReflections = try modelContext.fetch(FetchDescriptor<PomodoroReflection>())
            .filter { !existingSessionIDs.contains($0.focusSessionID) }
        for reflection in orphanedReflections {
            modelContext.delete(reflection)
        }
        return Array(affectedRecordsByID.values)
    }
}
