import Foundation
import SwiftData

@Model
final class PomodoroTaskCompletion {
    var id: UUID
    @Attribute(.unique)
    var focusSessionID: UUID
    var linkedMemoID: UUID
    var taskTitleSnapshot: String?
    var completedAt: Date
    var didMarkMemoCompleted: Bool
    var memoWasPinnedBeforeCompletion: Bool
    var memoStateChangedAt: Date?
    var schemaVersion: Int

    init(
        focusSessionID: UUID,
        linkedMemoID: UUID,
        taskTitleSnapshot: String?,
        completedAt: Date = Date(),
        didMarkMemoCompleted: Bool,
        memoWasPinnedBeforeCompletion: Bool
    ) {
        self.id = UUID()
        self.focusSessionID = focusSessionID
        self.linkedMemoID = linkedMemoID
        self.taskTitleSnapshot = Self.normalizedText(taskTitleSnapshot)
        self.completedAt = completedAt
        self.didMarkMemoCompleted = didMarkMemoCompleted
        self.memoWasPinnedBeforeCompletion = memoWasPinnedBeforeCompletion
        self.memoStateChangedAt = didMarkMemoCompleted ? completedAt : nil
        self.schemaVersion = 1
    }

    private static func normalizedText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
