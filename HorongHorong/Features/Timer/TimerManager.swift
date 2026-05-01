import Foundation
import SwiftData

@Observable
final class TimerManager: @unchecked Sendable {
    private var timer: Timer?
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

        if let session = currentSession {
            session.endedAt = Date()
            session.completed = false
            try? modelContext?.save()
        }
        currentSession = nil

        appState.timerState = .idle
        appState.remainingSeconds = 0
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
                title: "🔥 집중 시간 완료!",
                body: "\(focusMins)분 동안 수고했어요. 잠시 쉬어가세요."
            )
            Task { @MainActor in
                ToastPanel.shared.show(
                    icon: "🔥",
                    title: "집중 시간 완료!",
                    subtitle: "\(focusMins)분 동안 수고했어요. 잠시 쉬어가세요."
                )
            }
        case .breaking:
            currentSession = nil
            appState.timerState = .idle
            NotificationManager.shared.send(
                title: "☕ 휴식 끝!",
                body: "다시 집중할 준비가 되셨나요?"
            )
            Task { @MainActor in
                ToastPanel.shared.show(
                    icon: "☕",
                    title: "휴식 끝!",
                    subtitle: "다시 집중할 준비가 되셨나요?"
                )
            }
        default:
            break
        }
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
