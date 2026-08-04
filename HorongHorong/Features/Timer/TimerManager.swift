import Foundation
import SwiftData
import CoreGraphics

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
        focusInputActiveSeconds = 0
        modelContext?.insert(session)
        try? modelContext?.save()

        startCountdown()
    }

    func startBreak() {
        appState.timerState = .breaking
        appState.remainingSeconds = appState.breakMinutes * 60
        startCountdown()
    }

    func pause(at now: Date = Date()) {
        guard appState.timerState == .focusing else { return }
        timer?.invalidate()
        currentSession?.recordPauseStarted(at: now)
        try? modelContext?.save()
        appState.timerState = .paused
    }

    func resume(at now: Date = Date()) {
        guard appState.timerState == .paused else { return }
        currentSession?.recordPauseEnded(at: now)
        try? modelContext?.save()
        appState.timerState = .focusing
        startCountdown()
    }

    var currentFocusElapsedSeconds: Int {
        Self.elapsedFocusSeconds(
            plannedSeconds: appState.focusMinutes * 60,
            remainingSeconds: appState.remainingSeconds
        )
    }

    static func elapsedFocusSeconds(
        plannedSeconds: Int,
        remainingSeconds: Int
    ) -> Int {
        let normalizedPlannedSeconds = max(0, plannedSeconds)
        let normalizedRemainingSeconds = min(
            normalizedPlannedSeconds,
            max(0, remainingSeconds)
        )
        return normalizedPlannedSeconds - normalizedRemainingSeconds
    }

    @discardableResult
    func endFocusAndRecord() -> FocusSession? {
        guard appState.timerState == .focusing || appState.timerState == .paused,
              let session = currentSession else {
            return nil
        }

        timer?.invalidate()
        timer = nil
        cancelPostBreakPrompt()

        let actualSeconds = currentFocusElapsedSeconds
        guard actualSeconds > 0 else {
            discardCurrentFocus()
            return nil
        }

        let endedAt = Date()
        session.recordPauseEnded(at: endedAt)
        session.endedAt = endedAt
        session.completed = true
        session.actualFocusSeconds = actualSeconds
        session.endKind = .recordedEarly
        session.inputActiveSeconds = focusInputActiveSeconds
        updateLastCompletedTaskContext(for: session)
        try? modelContext?.save()
        recordCompletedFocus(session: session)
        NotificationCenter.default.post(
            name: .pomodoroSessionDidChange,
            object: session.id
        )

        let completedSessionID = session.id
        currentSession = nil
        focusInputActiveSeconds = 0
        appState.timerState = .idle
        appState.remainingSeconds = 0

        if UserDefaults.standard.bool(
            forKey: Constants.AppStorageKey.pomodoroReflectionEnabled
        ) {
            Task { @MainActor [weak self] in
                self?.showReflection(focusSessionID: completedSessionID)
            }
        }
        return session
    }

    func discardCurrentFocus() {
        guard appState.timerState == .focusing || appState.timerState == .paused else {
            return
        }

        timer?.invalidate()
        timer = nil
        cancelPostBreakPrompt()

        let discardedSessionID = currentSession?.id
        if let currentSession, let modelContext {
            modelContext.delete(currentSession)
            try? modelContext.save()
        }
        currentSession = nil
        focusInputActiveSeconds = 0
        appState.timerState = .idle
        appState.remainingSeconds = 0

        if let discardedSessionID {
            NotificationCenter.default.post(
                name: .pomodoroSessionDidChange,
                object: discardedSessionID
            )
        }
    }

    func reset() {
        if appState.timerState == .focusing || appState.timerState == .paused {
            discardCurrentFocus()
            return
        }

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
        // 집중 중인 1초마다 시스템 유휴 시간을 확인해, 최근에 입력이 있었으면 "입력 중"으로 센다.
        if appState.timerState == .focusing, appState.remainingSeconds > 0,
           currentIdleSeconds() < Self.inputActiveThresholdSeconds {
            focusInputActiveSeconds += 1
        }
        if appState.remainingSeconds > 0 {
            appState.remainingSeconds -= 1
        } else {
            timer?.invalidate()
            timer = nil
            handleTimerComplete()
        }
    }

    /// 집중 동안 키보드·마우스 입력이 있었던 초의 누적값. 세션 완료 시 FocusSession 에 저장한다.
    private var focusInputActiveSeconds = 0

    /// 마지막 입력 후 이 시간(초) 이내면 "입력 중"으로 본다. 틱 간격(1초)보다 살짝 크게 둔다.
    private static let inputActiveThresholdSeconds: TimeInterval = 2

    /// 마지막 입력(키보드/마우스) 후 경과 초. 권한이 필요 없는 시스템 유휴 타이머를 읽는다.
    private func currentIdleSeconds() -> TimeInterval {
        guard let anyType = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyType)
    }

    private func handleTimerComplete() {
        switch appState.timerState {
        case .focusing:
            let completedSessionID = currentSession?.id
            if let session = currentSession {
                session.endedAt = Date()
                session.completed = true
                session.actualFocusSeconds = max(0, session.focusMinutes * 60)
                session.endKind = .timerCompleted
                updateLastCompletedTaskContext(for: session)
                session.inputActiveSeconds = focusInputActiveSeconds
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
                body: content.body
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
                body: content.body
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

    private func updateLastCompletedTaskContext(for session: FocusSession) {
        canContinueLastTask = canContinueTask(linkedMemoID: session.linkedMemoID)
        if let linkedMemoID = session.linkedMemoID, canContinueLastTask {
            lastCompletedTaskContext = PomodoroTaskContext(
                linkedMemoID: linkedMemoID,
                taskTitleSnapshot: session.taskTitleSnapshot
            )
        } else {
            lastCompletedTaskContext = nil
        }
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
        let seconds = session.recordedFocusSeconds
        guard seconds > 0 else { return }

        let today = Calendar.current.startOfDay(for: session.endedAt ?? Date())
        let bundleId = Constants.focusSessionBundleId(for: category)
        try? AppUsageRecordStore.applyDelta(
            bundleIdentifier: bundleId,
            appName: Constants.focusSessionAppName,
            category: category,
            date: today,
            deltaSeconds: seconds,
            modelContext: context
        )
        try? context.save()
    }
}
