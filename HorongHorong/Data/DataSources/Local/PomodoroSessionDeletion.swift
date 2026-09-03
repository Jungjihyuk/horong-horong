import Foundation
import SwiftData

@MainActor
enum PomodoroSessionDeletion {
    @discardableResult
    static func delete(
        _ session: FocusSession,
        modelContext: ModelContext
    ) throws -> Memo? {
        let sessionID = session.id
        let affectedMemo = try PomodoroTaskCompletionRecorder.removeCompletion(
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
        return affectedMemo
    }

    static func repairOrphanedRecords(modelContext: ModelContext) throws -> [Memo] {
        let existingSessionIDs = Set(
            try modelContext.fetch(FetchDescriptor<FocusSession>()).map(\.id)
        )
        let completions = try modelContext.fetch(FetchDescriptor<PomodoroTaskCompletion>())
        let memosByID = Dictionary(
            uniqueKeysWithValues: try modelContext.fetch(FetchDescriptor<Memo>()).map {
                ($0.id, $0)
            }
        )
        for completion in completions where completion.didMarkMemoCompleted {
            let stateChangedAt = completion.memoStateChangedAt ?? completion.completedAt
            guard let memo = memosByID[completion.linkedMemoID],
                  memo.isCompletedValue,
                  memo.completionStateChangedAt == nil,
                  memo.updatedAt == stateChangedAt else {
                continue
            }
            memo.completionStateChangedAt = stateChangedAt
        }

        let orphanedCompletionSessionIDs = completions
            .map(\.focusSessionID)
            .filter { !existingSessionIDs.contains($0) }

        var affectedMemosByID: [UUID: Memo] = [:]
        for sessionID in orphanedCompletionSessionIDs {
            if let memo = try PomodoroTaskCompletionRecorder.removeCompletion(
                focusSessionID: sessionID,
                modelContext: modelContext
            ) {
                affectedMemosByID[memo.id] = memo
            }
        }

        let orphanedReflections = try modelContext.fetch(FetchDescriptor<PomodoroReflection>())
            .filter { !existingSessionIDs.contains($0.focusSessionID) }
        for reflection in orphanedReflections {
            modelContext.delete(reflection)
        }
        return Array(affectedMemosByID.values)
    }
}
