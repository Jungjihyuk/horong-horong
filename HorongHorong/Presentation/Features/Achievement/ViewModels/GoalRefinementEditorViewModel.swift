import Foundation
import Observation

@MainActor
@Observable
final class GoalRefinementEditorViewModel: Identifiable {
    enum Target {
        case todo(TodoItem)
        case weeklyGoal(AchievementGoalDetail)
    }

    let id: UUID
    let example: String
    let isTodo: Bool

    var title: String
    var detail: String
    var hasStartDate: Bool
    var startDate: Date
    var hasDueDate: Bool
    var dueDate: Date
    var errorMessage: String?

    private let target: Target
    private let todoRepository: TodoRepository
    private let achievementRepository: AchievementRepository

    init(
        target: Target,
        example: String,
        todoRepository: TodoRepository,
        achievementRepository: AchievementRepository
    ) {
        self.target = target
        self.example = example
        self.todoRepository = todoRepository
        self.achievementRepository = achievementRepository

        switch target {
        case .todo(let todo):
            id = todo.id
            isTodo = true
            title = todo.split.title
            detail = todo.split.note
            hasStartDate = todo.startDate != nil
            startDate = todo.startDate ?? Date()
            hasDueDate = todo.deadline != nil
            dueDate = todo.deadline ?? todo.startDate ?? Date()
        case .weeklyGoal(let goal):
            id = goal.id
            isTodo = false
            title = goal.title
            detail = goal.rule
            hasStartDate = false
            startDate = Date()
            hasDueDate = goal.dueDate != nil
            dueDate = goal.dueDate ?? Date()
        }
    }

    func save() -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            errorMessage = "제목을 입력해 주세요."
            return false
        }

        do {
            switch target {
            case .todo:
                try todoRepository.update(
                    id: id,
                    with: TodoEditDraft(
                        content: TodoItem.joined(title: trimmedTitle, note: detail),
                        startDate: hasStartDate ? startDate : nil,
                        deadline: hasDueDate ? dueDate : nil
                    )
                )
            case .weeklyGoal(let goal):
                achievementRepository.updateGoal(
                    id: id,
                    with: AchievementGoalEditDraft(
                        title: trimmedTitle,
                        emoji: goal.emoji,
                        rule: detail.trimmingCharacters(in: .whitespacesAndNewlines),
                        targetCount: goal.targetCount,
                        rewardText: goal.rewardText,
                        linkedMemoIDs: nil,
                        dueDate: hasDueDate ? dueDate : nil,
                        additionalChildGoalIDs: nil
                    )
                )
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = "저장하지 못했습니다. 잠시 후 다시 시도해 주세요."
            return false
        }
    }
}
