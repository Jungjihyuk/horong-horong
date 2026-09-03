import Foundation
import SwiftData

/// `CompanionMemoRepository` 의 SwiftData 구현.
@MainActor
struct SwiftDataCompanionMemoRepository: CompanionMemoRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    func createMemo(
        content: String,
        icon: String,
        startDate: Date?,
        deadline: Date?
    ) throws -> UUID {
        // 섹션을 안 주면 `Memo.init` 이 내용으로 판별한다.
        let memo = Memo(content: content, icon: icon)
        memo.startDate = startDate
        memo.deadline = deadline
        context.insert(memo)
        do {
            try context.save()
            return memo.id
        } catch {
            // 저장에 실패한 것이 메모리에 남으면 다음 저장에 딸려 간다.
            context.delete(memo)
            throw error
        }
    }
}
