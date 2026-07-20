import Foundation
import SwiftData

private struct PomodoroTaskContext {
    let linkedMemoID: UUID
    let taskTitleSnapshot: String?
}

@Observable
final class TimerManager: @unchecked Sendable {
    private var timer: Timer?
    private var postBreakPromptTimer: Timer?
    private var appState: AppState
    private var modelContext: ModelContext?
    private var currentSession: FocusSession?
    private var lastCompletedTaskContext: PomodoroTaskContext?
    private var linkedTaskCompletionObserver: NSObjectProtocol?

    private(set) var canContinueLastTask = true

    init(appState: AppState) {
        self.appState = appState
        linkedTaskCompletionObserver = NotificationCenter.default.addObserver(
            forName: .pomodoroLinkedTaskDidComplete,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let linkedMemoID = notification.object as? UUID,
                  self?.lastCompletedTaskContext?.linkedMemoID == linkedMemoID else {
                return
            }
            self?.lastCompletedTaskContext = nil
            self?.canContinueLastTask = false
        }
    }

    deinit {
        if let linkedTaskCompletionObserver {
            NotificationCenter.default.removeObserver(linkedTaskCompletionObserver)
        }
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func startFocus(
        category: String = Constants.defaultFocusCategory,
        linkedMemoID: UUID? = nil,
        taskTitleSnapshot: String? = nil
    ) {
        cancelPostBreakPrompt()
        TrackerStateStore.shared.clearManualAway()
        appState.timerState = .focusing
        appState.remainingSeconds = appState.focusMinutes * 60

        let session = FocusSession(
            focusMinutes: appState.focusMinutes,
            breakMinutes: appState.breakMinutes,
            category: category,
            linkedMemoID: linkedMemoID,
            taskTitleSnapshot: taskTitleSnapshot
        )
        currentSession = session
        modelContext?.insert(session)
        try? modelContext?.save()

        startCountdown()
    }

    func startBreak() {
        appState.timerState = .breaking
        appState.remainingSeconds = appState.breakMinutes * 60
        startCountdown()
    }

    func pause() {
        guard appState.timerState == .focusing else { return }
        appState.timerState = .paused
        timer?.invalidate()
    }

    func resume() {
        guard appState.timerState == .paused else { return }
        appState.timerState = .focusing
        startCountdown()
    }

    func reset() {
        timer?.invalidate()
        timer = nil
        cancelPostBreakPrompt()

        if let session = currentSession, !session.completed {
            session.endedAt = Date()
            session.completed = false
            try? modelContext?.save()
        }
        currentSession = nil

        appState.timerState = .idle
        appState.remainingSeconds = 0
    }

    func continueAfterBreak(category: String) {
        guard let prompt = appState.breakTransitionPrompt else {
            startFocus(
                category: category,
                linkedMemoID: lastCompletedTaskContext?.linkedMemoID,
                taskTitleSnapshot: lastCompletedTaskContext?.taskTitleSnapshot
            )
            return
        }
        recordBreakTransition(
            breakEndedAt: prompt.breakEndedAt,
            decision: .sameTaskReturn,
            previousCategory: prompt.previousCategory,
            nextCategory: category
        )
        startFocus(
            category: category,
            linkedMemoID: lastCompletedTaskContext?.linkedMemoID,
            taskTitleSnapshot: lastCompletedTaskContext?.taskTitleSnapshot
        )
    }

    func resolveBreakTransition(_ decision: BreakTransitionDecisionKind, nextCategory: String? = nil) {
        guard let prompt = appState.breakTransitionPrompt else { return }
        recordBreakTransition(
            breakEndedAt: prompt.breakEndedAt,
            decision: decision,
            previousCategory: prompt.previousCategory,
            nextCategory: nextCategory
        )
        if decision == .externalTransition {
            TrackerStateStore.shared.markManualAway()
            Task { @MainActor in
                IdlePromptPanel.shared.close(animated: true)
            }
        }
        cancelPostBreakPrompt()
    }

    private func startCountdown() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        if appState.remainingSeconds > 0 {
            appState.remainingSeconds -= 1
        } else {
            timer?.invalidate()
            timer = nil
            handleTimerComplete()
        }
    }

    private func handleTimerComplete() {
        switch appState.timerState {
        case .focusing:
            let completedSessionID = currentSession?.id
            if let session = currentSession {
                session.endedAt = Date()
                session.completed = true
                canContinueLastTask = canContinueTask(linkedMemoID: session.linkedMemoID)
                if let linkedMemoID = session.linkedMemoID, canContinueLastTask {
                    lastCompletedTaskContext = PomodoroTaskContext(
                        linkedMemoID: linkedMemoID,
                        taskTitleSnapshot: session.taskTitleSnapshot
                    )
                } else {
                    lastCompletedTaskContext = nil
                }
                try? modelContext?.save()
                // 완료된 집중 세션을 통계(AppUsageRecord)에 반영한다.
                recordCompletedFocus(session: session)
                NotificationCenter.default.post(
                    name: .pomodoroSessionDidChange,
                    object: session.id
                )
            } else {
                canContinueLastTask = true
            }
            appState.timerState = .breakAlert
            let focusMins = appState.focusMinutes
            let shouldRequestReflection = UserDefaults.standard.bool(
                forKey: Constants.AppStorageKey.pomodoroReflectionEnabled
            )
            presentFocusCompletionNotification(
                focusMinutes: focusMins,
                completedSessionID: completedSessionID,
                shouldRequestReflection: shouldRequestReflection
            )
        case .breaking:
            let breakEndedAt = Date()
            let previousCategory = currentSession?.category ?? Constants.defaultFocusCategory
            currentSession = nil
            appState.timerState = .idle
            schedulePostBreakTransitionPrompt(
                breakEndedAt: breakEndedAt,
                previousCategory: previousCategory
            )
            presentBreakCompletionNotification()
        default:
            break
        }
    }

    private func presentFocusCompletionNotification(
        focusMinutes: Int,
        completedSessionID: UUID?,
        shouldRequestReflection: Bool
    ) {
        let content = Constants.focusCompletionNotificationContent(focusMinutes: focusMinutes)

        switch timerCompletionNotificationStyle {
        case .system:
            NotificationManager.shared.send(
                title: content.title,
                subtitle: content.subtitle,
                body: content.body,
                identifier: Constants.timerCompletionNotificationIdentifier,
                replacesExisting: true
            )
            guard shouldRequestReflection else { return }
            Task { @MainActor [weak self] in
                try? await Task.sleep(
                    for: .seconds(Constants.timerCompletionNativeReflectionDelaySeconds)
                )
                guard !Task.isCancelled else { return }
                self?.showReflection(focusSessionID: completedSessionID)
            }

        case .horong:
            Task { @MainActor [weak self] in
                ToastPanel.shared.showTimerAlert(
                    title: content.title,
                    subtitle: content.subtitle,
                    detail: content.body
                )
                guard shouldRequestReflection else { return }
                await ToastPanel.shared.waitUntilDismissed()
                guard !Task.isCancelled else { return }
                self?.showReflection(focusSessionID: completedSessionID)
            }
        }
    }

    private func presentBreakCompletionNotification() {
        let content = Constants.breakCompletionNotificationContent

        switch timerCompletionNotificationStyle {
        case .system:
            NotificationManager.shared.send(
                title: content.title,
                subtitle: content.subtitle,
                body: content.body,
                identifier: Constants.timerCompletionNotificationIdentifier,
                replacesExisting: true
            )

        case .horong:
            Task { @MainActor in
                ToastPanel.shared.showTimerAlert(
                    title: content.title,
                    subtitle: content.subtitle,
                    detail: content.body
                )
            }
        }
    }

    @MainActor
    private func showReflection(focusSessionID: UUID?) {
        guard let focusSessionID, let modelContext else { return }
        PomodoroReflectionPanel.shared.show(
            focusSessionID: focusSessionID,
            modelContext: modelContext
        )
    }

    private func schedulePostBreakTransitionPrompt(breakEndedAt: Date, previousCategory: String) {
        cancelPostBreakPrompt()
        let mode = postBreakTransitionPromptMode
        switch mode {
        case .always:
            presentPostBreakTransitionPrompt(breakEndedAt: breakEndedAt, previousCategory: previousCategory)
        case .afterDelay:
            let delay = TimeInterval(max(1, postBreakTransitionPromptDelayMinutes) * 60)
            postBreakPromptTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                self?.evaluatePostBreakTransition(
                    breakEndedAt: breakEndedAt,
                    previousCategory: previousCategory
                )
            }
        }
    }

    private func evaluatePostBreakTransition(breakEndedAt: Date, previousCategory: String) {
        postBreakPromptTimer?.invalidate()
        postBreakPromptTimer = nil
        guard appState.timerState == .idle else { return }
        guard !hasFocusSession(startingAfter: breakEndedAt) else { return }
        guard !hasProductiveActivity(since: breakEndedAt) else { return }
        presentPostBreakTransitionPrompt(breakEndedAt: breakEndedAt, previousCategory: previousCategory)
    }

    private func presentPostBreakTransitionPrompt(breakEndedAt: Date, previousCategory: String) {
        appState.breakTransitionPrompt = BreakTransitionPrompt(
            breakEndedAt: breakEndedAt,
            previousCategory: previousCategory
        )
    }

    private func cancelPostBreakPrompt() {
        postBreakPromptTimer?.invalidate()
        postBreakPromptTimer = nil
        appState.breakTransitionPrompt = nil
    }

    private var postBreakTransitionPromptMode: Constants.PostBreakTransitionPromptMode {
        let rawValue = UserDefaults.standard.string(forKey: Constants.AppStorageKey.postBreakTransitionPromptMode)
        return Constants.PostBreakTransitionPromptMode(rawValue: rawValue ?? "") ?? .afterDelay
    }

    private var timerCompletionNotificationStyle: Constants.TimerCompletionNotificationStyle {
        let rawValue = UserDefaults.standard.string(
            forKey: Constants.AppStorageKey.timerCompletionNotificationStyle
        )
        return Constants.TimerCompletionNotificationStyle(rawValue: rawValue ?? "")
            ?? Constants.defaultTimerCompletionNotificationStyle
    }

    private var postBreakTransitionPromptDelayMinutes: Int {
        let stored = UserDefaults.standard.integer(forKey: Constants.AppStorageKey.postBreakTransitionPromptDelayMinutes)
        return stored > 0 ? stored : Constants.defaultPostBreakTransitionPromptDelayMinutes
    }

    private func hasFocusSession(startingAfter date: Date) -> Bool {
        guard let context = modelContext else { return false }
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.startedAt > date }
        )
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    private func canContinueTask(linkedMemoID: UUID?) -> Bool {
        guard let linkedMemoID else { return true }
        guard let context = modelContext else { return true }
        let memoID = linkedMemoID
        var descriptor = FetchDescriptor<Memo>(
            predicate: #Predicate { $0.id == memoID }
        )
        descriptor.fetchLimit = 1
        guard let memo = try? context.fetch(descriptor).first else { return false }
        return !memo.isCompletedValue && !memo.isArchivedValue
    }

    private func hasProductiveActivity(since date: Date) -> Bool {
        guard let context = modelContext else { return false }
        let descriptor = FetchDescriptor<AppUsageSegment>(
            predicate: #Predicate { $0.endTime > date }
        )
        let segments = (try? context.fetch(descriptor)) ?? []
        let productiveSeconds = segments.reduce(0) { total, segment in
            guard Constants.postBreakProductiveCategories.contains(segment.category) else {
                return total
            }
            let start = max(segment.startTime, date)
            guard segment.endTime > start else { return total }
            return total + Int(segment.endTime.timeIntervalSince(start))
        }
        return productiveSeconds >= 60
    }

    private func recordBreakTransition(
        breakEndedAt: Date,
        decision: BreakTransitionDecisionKind,
        previousCategory: String,
        nextCategory: String?
    ) {
        guard let context = modelContext else { return }
        let intent = BreakTransitionIntent(
            breakEndedAt: breakEndedAt,
            decision: decision,
            previousCategory: previousCategory,
            nextCategory: nextCategory
        )
        context.insert(intent)
        try? context.save()
    }

    // MARK: - 집중 세션 통계 반영

    private func recordCompletedFocus(session: FocusSession) {
        guard let context = modelContext else { return }
        let category = session.category ?? Constants.defaultFocusCategory
        let seconds = session.focusMinutes * 60
        guard seconds > 0 else { return }

        let today = Calendar.current.startOfDay(for: Date())
        let bundleId = Constants.focusSessionBundleId(for: category)
        let targetBundleId = bundleId
        let targetDate = today

        let descriptor = FetchDescriptor<AppUsageRecord>(
            predicate: #Predicate {
                $0.bundleIdentifier == targetBundleId && $0.date == targetDate
            }
        )

        if let existing = try? context.fetch(descriptor).first {
            existing.durationSeconds += seconds
            if existing.category != category {
                existing.category = category
            }
        } else {
            let record = AppUsageRecord(
                appName: Constants.focusSessionAppName,
                bundleIdentifier: bundleId,
                category: category,
                date: today
            )
            record.durationSeconds = seconds
            context.insert(record)
        }
        try? context.save()
    }
}
