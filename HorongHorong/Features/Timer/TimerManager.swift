import Foundation
import SwiftData

@Observable
final class TimerManager: @unchecked Sendable {
    private var timer: Timer?
    private var postBreakPromptTimer: Timer?
    private var appState: AppState
    private var modelContext: ModelContext?
    private var currentSession: FocusSession?

    init(appState: AppState) {
        self.appState = appState
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func startFocus(category: String = Constants.defaultFocusCategory) {
        cancelPostBreakPrompt()
        TrackerStateStore.shared.clearManualAway()
        appState.timerState = .focusing
        appState.remainingSeconds = appState.focusMinutes * 60

        let session = FocusSession(
            focusMinutes: appState.focusMinutes,
            breakMinutes: appState.breakMinutes,
            category: category
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
            startFocus(category: category)
            return
        }
        recordBreakTransition(
            breakEndedAt: prompt.breakEndedAt,
            decision: .sameTaskReturn,
            previousCategory: prompt.previousCategory,
            nextCategory: category
        )
        startFocus(category: category)
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
            if let session = currentSession {
                session.endedAt = Date()
                session.completed = true
                try? modelContext?.save()
                // 완료된 집중 세션을 통계(AppUsageRecord)에 반영한다.
                recordCompletedFocus(session: session)
            }
            appState.timerState = .breakAlert
            let focusMins = appState.focusMinutes
            NotificationManager.shared.send(
                title: "포모도로 완료",
                body: "\(focusMins)분 집중 완료 · 집중 기록 저장 완료 · 잠시 쉬어가세요"
            )
            Task { @MainActor in
                ToastPanel.shared.showTimerAlert(
                    title: "포모도로 완료",
                    subtitle: "\(focusMins)분 집중 완료",
                    detail: "집중 기록 저장 완료 · 잠시 쉬어가세요"
                )
            }
        case .breaking:
            let breakEndedAt = Date()
            let previousCategory = currentSession?.category ?? Constants.defaultFocusCategory
            currentSession = nil
            appState.timerState = .idle
            schedulePostBreakTransitionPrompt(
                breakEndedAt: breakEndedAt,
                previousCategory: previousCategory
            )
            NotificationManager.shared.send(
                title: "휴식 끝!",
                body: "다시 집중할 준비가 되셨나요?"
            )
            Task { @MainActor in
                ToastPanel.shared.showTimerAlert(
                    title: "휴식 끝!",
                    subtitle: "다시 집중할 준비가 되셨나요?"
                )
            }
        default:
            break
        }
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
