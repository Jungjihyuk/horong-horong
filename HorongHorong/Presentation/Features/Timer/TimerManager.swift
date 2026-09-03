import Foundation
import CoreGraphics

private struct PomodoroTaskContext {
    let linkedMemoID: UUID
    let taskTitleSnapshot: String?
}

/// **`@MainActor` 인 이유**: 타이머 콜백으로 화면 상태(`AppState`)를 고치고 알림을 띄운다.
/// 원래도 메인 스레드에서만 돌던 것을 이제 컴파일러가 지킨다.
@MainActor
@Observable
final class TimerManager {
    private var timer: Timer?
    private var postBreakPromptTimer: Timer?
    private var appState: AppState
    private var repository: FocusSessionRepository?
    private var reflections: PomodoroReflectionRepository?
    /// 진행 중인 세션의 **식별자만** 든다. `@Model` 을 들면 그게 화면 쪽까지 새어 나온다.
    private var currentSessionID: UUID?
    /// 이번 집중이 몇 분짜리였나. 타이머가 끝까지 갔을 때 기록할 시간을 여기서 안다.
    private var currentFocusMinutes = 0
    private var lastCompletedTaskContext: PomodoroTaskContext?
    /// `deinit` 이 액터 밖에서 읽어야 해서 격리에서 뺀다. 값을 만든 뒤로 바뀌지 않는다.
    @ObservationIgnored nonisolated(unsafe) private var linkedTaskCompletionObserver: NSObjectProtocol?

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
        // `deinit` 은 액터 밖에서 돌 수 있어 격리된 프로퍼티를 읽을 수 없다.
        // 관찰자만 떼면 되므로 지역 사본을 쓴다.
        if let observer = linkedTaskCompletionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func setRepositories(
        focusSessions: FocusSessionRepository,
        reflections: PomodoroReflectionRepository
    ) {
        self.repository = focusSessions
        self.reflections = reflections
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

        currentFocusMinutes = appState.focusMinutes
        currentSessionID = repository?.startFocus(
            focusMinutes: appState.focusMinutes,
            breakMinutes: appState.breakMinutes,
            category: category,
            linkedMemoID: linkedMemoID,
            taskTitleSnapshot: taskTitleSnapshot
        )
        focusInputActiveSeconds = 0
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
        if let currentSessionID { repository?.recordPauseStarted(id: currentSessionID, at: now) }
        appState.timerState = .paused
    }

    func resume(at now: Date = Date()) {
        guard appState.timerState == .paused else { return }
        if let currentSessionID { repository?.recordPauseEnded(id: currentSessionID, at: now) }
        appState.timerState = .focusing
        startCountdown()
    }

    func toggleFocus(category: String = Constants.defaultFocusCategory) {
        switch appState.timerState {
        case .idle:
            startFocus(category: category)
        case .focusing:
            pause()
        case .paused:
            resume()
        case .breakAlert, .breaking:
            break
        }
    }

    var currentFocusElapsedSeconds: Int {
        Self.elapsedFocusSeconds(
            plannedSeconds: appState.focusMinutes * 60,
            remainingSeconds: appState.remainingSeconds
        )
    }

    /// 순수 계산이라 액터와 무관하다. 클래스가 `@MainActor` 가 되면서 딸려 갔던 것을 뗀다.
    nonisolated static func elapsedFocusSeconds(
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
    /// 타이머가 끝나기 전에 사용자가 «기록하고 끝내기» 를 눌렀을 때.
    func endFocusAndRecord() {
        guard appState.timerState == .focusing || appState.timerState == .paused,
              let sessionID = currentSessionID else {
            return
        }

        timer?.invalidate()
        timer = nil
        cancelPostBreakPrompt()

        // 1초도 안 했으면 기록할 것이 없다.
        let actualSeconds = currentFocusElapsedSeconds
        guard actualSeconds > 0 else {
            discardCurrentFocus()
            return
        }

        let finished = repository?.finishFocus(
            id: sessionID,
            endedAt: Date(),
            actualSeconds: actualSeconds,
            inputActiveSeconds: focusInputActiveSeconds,
            endKind: .recordedEarly
        )
        applyFinished(finished)
        NotificationCenter.default.post(name: .pomodoroSessionDidChange, object: sessionID)

        currentSessionID = nil
        focusInputActiveSeconds = 0
        appState.timerState = .idle
        appState.remainingSeconds = 0

        if UserDefaults.standard.bool(
            forKey: Constants.AppStorageKey.pomodoroReflectionEnabled
        ) {
            Task { @MainActor [weak self] in
                self?.showReflection(focusSessionID: sessionID)
            }
        }
    }

    func discardCurrentFocus() {
        guard appState.timerState == .focusing || appState.timerState == .paused else {
            return
        }

        timer?.invalidate()
        timer = nil
        cancelPostBreakPrompt()

        let discardedSessionID = currentSessionID
        if let discardedSessionID { repository?.discardFocus(id: discardedSessionID) }
        currentSessionID = nil
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

        if let currentSessionID { repository?.abandonFocus(id: currentSessionID, endedAt: Date()) }
        currentSessionID = nil

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
        repository?.recordBreakTransition(
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
        repository?.recordBreakTransition(
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
            let completedSessionID = currentSessionID
            if let sessionID = completedSessionID {
                // 끝까지 갔으므로 계획한 시간을 그대로 기록한다.
                let finished = repository?.finishFocus(
                    id: sessionID,
                    endedAt: Date(),
                    actualSeconds: max(0, currentFocusMinutes * 60),
                    inputActiveSeconds: focusInputActiveSeconds,
                    endKind: .timerCompleted
                )
                applyFinished(finished)
                NotificationCenter.default.post(name: .pomodoroSessionDidChange, object: sessionID)
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
            // 쉬는 시간에 들어온 시점에는 집중 세션이 이미 닫혀 있다.
            // 이어서 할 갈래를 정할 때 쓰는 카테고리는 마지막으로 고른 값에서 읽는다.
            let previousCategory = UserDefaults.standard
                .string(forKey: Constants.AppStorageKey.selectedFocusCategory)
                ?? Constants.defaultFocusCategory
            currentSessionID = nil
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

    private func showReflection(focusSessionID: UUID?) {
        guard let focusSessionID, let reflections else { return }
        PomodoroReflectionPanel.shared.show(focusSessionID: focusSessionID, repository: reflections)
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
        guard !(repository?.hasFocusSession(startingAfter: breakEndedAt) ?? false) else { return }
        guard !(repository?.hasProductiveActivity(since: breakEndedAt, minimumSeconds: 60) ?? false) else { return }
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



    /// 끝난 세션을 보고 «이어서 같은 일을 할 수 있는가» 를 갱신한다.
    /// 그 판단(할 일이 아직 살아 있나)은 저장소가 이미 해서 넘겨준다.
    private func applyFinished(_ finished: FinishedFocusSession?) {
        guard let finished else {
            canContinueLastTask = true
            lastCompletedTaskContext = nil
            return
        }
        canContinueLastTask = finished.isTaskStillOpen
        if let linkedMemoID = finished.linkedMemoID, finished.isTaskStillOpen {
            lastCompletedTaskContext = PomodoroTaskContext(
                linkedMemoID: linkedMemoID,
                taskTitleSnapshot: finished.taskTitleSnapshot
            )
        } else {
            lastCompletedTaskContext = nil
        }
    }



    // MARK: - 집중 세션 통계 반영

}
