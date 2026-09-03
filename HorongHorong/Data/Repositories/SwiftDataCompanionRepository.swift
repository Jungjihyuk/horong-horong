import Foundation
import SwiftData

/// `CompanionRepository` 의 SwiftData 구현.
@MainActor
struct SwiftDataCompanionRepository: CompanionRepository {
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

    func onboardingCounts() -> CompanionOnboardingCounts {
        CompanionOnboardingCounts(
            memoCount: (try? context.fetchCount(FetchDescriptor<Memo>())) ?? 0,
            focusSessionCount: (try? context.fetchCount(FetchDescriptor<FocusSession>())) ?? 0,
            achievementGoalCount: (try? context.fetchCount(FetchDescriptor<AchievementGoalRecord>())) ?? 0
        )
    }

    func briefingMemos() -> [CompanionMemoSummary] {
        let memos = (try? context.fetch(FetchDescriptor<Memo>())) ?? []
        return memos
            .filter { !$0.isRecentlyDeleted }
            .map {
                CompanionMemoSummary(
                    title: $0.content,
                    isCompleted: $0.isCompletedValue,
                    startDate: $0.startDate,
                    deadline: $0.deadline
                )
            }
    }
}
