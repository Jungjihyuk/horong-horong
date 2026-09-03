import Foundation
import SwiftData

/// `PomodoroReflectionRepository` 의 SwiftData 구현.
@MainActor
final class SwiftDataPomodoroReflectionRepository: PomodoroReflectionRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func prompt(for sessionID: UUID) -> PomodoroReflectionPrompt? {
        // 이미 답했으면 다시 묻지 않는다.
        let answered = FetchDescriptor<PomodoroReflection>(
            predicate: #Predicate { $0.focusSessionID == sessionID }
        )
        guard ((try? context.fetchCount(answered)) ?? 0) == 0 else { return nil }

        let session = find(sessionID)
        let focusIntervals = session.map(FocusScoreHistory.focusIntervals) ?? []
        let assessment = AppClassificationService.unclassifiedAssessment(
            activeIntervals: focusIntervals,
            modelContext: context
        )

        return PomodoroReflectionPrompt(
            sessionID: sessionID,
            taskTitle: session?.taskTitleSnapshot,
            isLinkedTask: session?.linkedMemoID != nil,
            canRecordLinkedTaskCompletion: session?.linkedMemoID.map {
                PomodoroTaskCompletionRecorder.hasLinkedMemo(id: $0, modelContext: context)
            } ?? false,
            suggestedAppCategory: session?.category ?? Constants.defaultFocusCategory,
            // 「더 물어볼 만큼」이 아니면 분류 질문을 아예 띄우지 않는다.
            unclassifiedApps: assessment.needsClassificationFollowUp ? assessment.apps : [],
            unclassifiedRatio: assessment.needsClassificationFollowUp ? assessment.unclassifiedRatio : nil,
            productivityManagementAppUsages: AppClassificationService.productivityManagementAppUsages(
                activeIntervals: focusIntervals,
                modelContext: context
            )
        )
    }

    func saveReflection(
        sessionID: UUID,
        focusExperience: PomodoroFocusExperience,
        progressResult: PomodoroProgressResult,
        incompleteReason: PomodoroIncompleteReason?,
        answeredAt: Date
    ) throws {
        let session = find(sessionID)
        context.insert(PomodoroReflection(
            focusSessionID: sessionID,
            focusExperience: focusExperience,
            progressResult: progressResult,
            incompleteReason: incompleteReason,
            answeredAt: answeredAt
        ))
        // 답을 받았으므로 「나중에 쓰기」 표시를 지운다.
        session?.reflectionDeferredAt = nil

        do {
            // 계획대로 끝냈고 할 일이 연결돼 있을 때만 그 할 일을 완료로 찍는다.
            let completesLinkedTask = progressResult == .completedAsPlanned
                && session?.linkedMemoID.map {
                    PomodoroTaskCompletionRecorder.hasLinkedMemo(id: $0, modelContext: context)
                } == true

            let affectedMemo: Memo?
            if completesLinkedTask, let session {
                affectedMemo = try PomodoroTaskCompletionRecorder.recordCompletion(
                    for: session,
                    completedAt: answeredAt,
                    modelContext: context
                )
            } else {
                affectedMemo = nil
            }

            try context.save()

            NotificationCenter.default.post(name: .pomodoroReflectionDidChange, object: nil)
            NotificationCenter.default.post(name: .pomodoroSessionDidChange, object: nil)
            if completesLinkedTask, let linkedMemoID = session?.linkedMemoID {
                NotificationCenter.default.post(name: .pomodoroLinkedTaskDidComplete, object: linkedMemoID)
            }
            if let affectedMemo {
                PomodoroTaskCompletionRecorder.applyPostSaveEffects(to: affectedMemo, modelContext: context)
            }
        } catch {
            // 회고만 남고 할 일은 안 찍힌 어중간한 상태를 만들지 않는다.
            context.rollback()
            throw error
        }
    }

    func saveClassification(
        sessionID: UUID,
        choices: [String: UnclassifiedAppChoice],
        apps: [UnclassifiedAppUsage],
        productivityManagementAppCategories: [String: String]
    ) throws {
        let focusIntervals = find(sessionID).map(FocusScoreHistory.focusIntervals) ?? []
        do {
            try AppClassificationService.apply(choices: choices, apps: apps, modelContext: context)
            for (bundleIdentifier, category) in productivityManagementAppCategories {
                for interval in focusIntervals {
                    try AppClassificationService
                        .prepareProductivityManagementAppSessionClassification(
                            bundleIdentifier: bundleIdentifier,
                            from: interval.start,
                            to: interval.end,
                            category: category,
                            modelContext: context
                        )
                }
            }
            try context.save()
            // 규칙이 바뀌었으니 분류기가 쓰는 사본도 다시 읽는다.
            CategoryManager.shared.loadUserRules(from: SwiftDataAppUsageRepository(context: context))
            NotificationCenter.default.post(name: .pomodoroSessionDidChange, object: nil)
        } catch {
            context.rollback()
            throw error
        }
    }

    func deferReflection(sessionID: UUID, at date: Date) throws {
        guard let session = find(sessionID) else { return }
        session.reflectionDeferredAt = date
        do {
            try context.save()
            NotificationCenter.default.post(name: .pomodoroSessionDidChange, object: sessionID)
        } catch {
            context.rollback()
            throw error
        }
    }

    private func find(_ id: UUID) -> FocusSession? {
        var descriptor = FetchDescriptor<FocusSession>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
