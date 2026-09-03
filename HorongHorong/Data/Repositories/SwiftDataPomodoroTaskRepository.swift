import Foundation
import SwiftData

/// `PomodoroTaskRepository` 의 SwiftData 구현.
@MainActor
final class SwiftDataPomodoroTaskRepository: PomodoroTaskRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func candidateMemos() -> [AchievementMemoDetail] {
        // 후보가 될 수 없는 것은 DB 에서 떨군다 — 예전에는 전량을 가져와 Swift 에서 버렸다.
        //
        // 정렬 키는 `updatedAt` 그대로 둔다. 후보 목록이 이 순서로 **재정렬 없이 그대로**
        // 표시되므로, 키를 바꾸면 사용자가 보는 순서가 달라진다.
        let descriptor = FetchDescriptor<SecondBrainRecord>(
            predicate: #Predicate { $0.isCompleted != true && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return ((try? context.fetch(descriptor)) ?? []).map {
            AchievementMemoDetail(
                id: $0.id,
                content: $0.content,
                icon: $0.icon,
                startDate: $0.startDate,
                deadline: $0.deadline,
                updatedAt: $0.updatedAt,
                isCompleted: $0.isCompletedValue
            )
        }
    }

    func goalLinkedMemoIDs() -> Set<UUID> {
        let descriptor = FetchDescriptor<AchievementGoalRecord>()
        let records = (try? context.fetch(descriptor)) ?? []
        return Set(records.flatMap(\.linkedMemoIDs))
    }
}
