import Foundation
import SwiftData
import UserNotifications

extension Notification.Name {
    static let todayPlanningReminderSelected = Notification.Name(
        "app.horonghorong.todayPlanningReminderSelected"
    )
}

enum TodayPlanningReminderPolicy {
    static func isTodayTask(
        _ memo: Memo,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard !memo.isCompletedValue,
              !memo.isRecentlyDeleted else {
            return false
        }
        return isTodayTask(startDate: memo.startDate, now: now, calendar: calendar)
    }

    static func isTodayTask(
        _ record: SecondBrainRecord,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard !record.isCompletedValue,
              !record.isRecentlyDeleted else {
            return false
        }
        return isTodayTask(startDate: record.startDate, now: now, calendar: calendar)
    }

    /// `@Model` 없이 같은 판정을 한다. 이미 살아 있는 할일만 넘어온 자리에서 쓴다
    /// (뽀모도로 후보 목록). 규칙이 두 벌이 되지 않게 위 버전이 이걸 부른다.
    static func isTodayTask(
        startDate: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard let startDate else { return false }
        return calendar.isDate(startDate, inSameDayAs: now)
    }

    static func hasTodayTask(
        in memos: [Memo],
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        memos.contains {
            isTodayTask($0, now: now, calendar: calendar)
        }
    }

    static func hasTodayTask(
        in records: [SecondBrainRecord],
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        records.contains {
            isTodayTask($0, now: now, calendar: calendar)
        }
    }

    static func shouldPrompt(
        isEnabled: Bool,
        memos: [Memo],
        lastPromptedAt: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard isEnabled, !hasTodayTask(in: memos, now: now, calendar: calendar) else {
            return false
        }
        guard let lastPromptedAt else { return true }
        return !calendar.isDate(lastPromptedAt, inSameDayAs: now)
    }

    static func shouldPrompt(
        isEnabled: Bool,
        records: [SecondBrainRecord],
        lastPromptedAt: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard isEnabled, !hasTodayTask(in: records, now: now, calendar: calendar) else {
            return false
        }
        guard let lastPromptedAt else { return true }
        return !calendar.isDate(lastPromptedAt, inSameDayAs: now)
    }

    static func nextDayEvaluationDate(
        after date: Date,
        delaySeconds: TimeInterval,
        calendar: Calendar = .current
    ) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let startOfNextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        return startOfNextDay.addingTimeInterval(delaySeconds)
    }
}

@MainActor
final class TodayPlanningReminderCoordinator {
    static let shared = TodayPlanningReminderCoordinator()

    private var modelContext: ModelContext?
    private var evaluationTask: Task<Void, Never>?
    private var retryAttemptCount = 0

    private init() {}

    private var configuredDelaySeconds: TimeInterval {
        let defaults = UserDefaults.standard
        let key = Constants.AppStorageKey.todayPlanningReminderDelayMinutes
        let minutes = defaults.object(forKey: key) == nil
            ? Constants.defaultTodayPlanningReminderDelayMinutes
            : defaults.integer(forKey: key)
        return Constants.todayPlanningReminderDelaySeconds(for: minutes)
    }

    func start(modelContext: ModelContext) {
        self.modelContext = modelContext
        settingDidChange(
            isEnabled: UserDefaults.standard.bool(
                forKey: Constants.AppStorageKey.todayPlanningReminderEnabled
            )
        )
    }

    func settingDidChange(isEnabled: Bool) {
        evaluationTask?.cancel()
        evaluationTask = nil
        retryAttemptCount = 0

        guard isEnabled, modelContext != nil else {
            NotificationManager.shared.cancel(
                identifier: Constants.todayPlanningReminderNotificationIdentifier
            )
            return
        }
        scheduleEvaluation(after: configuredDelaySeconds)
    }

    func systemDateDidChange() {
        evaluationTask?.cancel()
        evaluationTask = nil
        retryAttemptCount = 0

        guard UserDefaults.standard.bool(
            forKey: Constants.AppStorageKey.todayPlanningReminderEnabled
        ), modelContext != nil else {
            return
        }
        scheduleEvaluation(after: configuredDelaySeconds)
    }

    func stop() {
        evaluationTask?.cancel()
        evaluationTask = nil
        retryAttemptCount = 0
        modelContext = nil
    }

    private func scheduleEvaluation(after delay: TimeInterval) {
        evaluationTask?.cancel()
        let nanoseconds = UInt64(max(0, delay) * 1_000_000_000)
        evaluationTask = Task { @MainActor [weak self] in
            do {
                try await Task<Never, Never>.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.evaluate()
        }
    }

    private func evaluate() async {
        guard let modelContext,
              UserDefaults.standard.bool(
                  forKey: Constants.AppStorageKey.todayPlanningReminderEnabled
              ) else {
            return
        }

        let now = Date()
        let records: [SecondBrainRecord]
        do {
            records = try modelContext.fetch(FetchDescriptor<SecondBrainRecord>())
        } catch {
            print("오늘 할 일 계획 알림 판정 실패: \(error.localizedDescription)")
            scheduleRetryOrNextDay()
            return
        }

        let lastPromptedAt = lastPromptedAtFromDefaults()
        guard TodayPlanningReminderPolicy.shouldPrompt(
            isEnabled: true,
            records: records,
            lastPromptedAt: lastPromptedAt,
            now: now
        ) else {
            retryAttemptCount = 0
            scheduleNextDay(after: now)
            return
        }

        let sendResult = await NotificationManager.shared.sendAwaitingResult(
            title: "오늘은 무엇을 할 건가요?",
            body: "오늘 시작할 할 일을 먼저 등록하면 포모도로와 진행 기록을 함께 볼 수 있어요.",
            identifier: Constants.todayPlanningReminderNotificationIdentifier
        )

        guard !Task.isCancelled,
              UserDefaults.standard.bool(
                  forKey: Constants.AppStorageKey.todayPlanningReminderEnabled
              ) else {
            NotificationManager.shared.cancel(
                identifier: Constants.todayPlanningReminderNotificationIdentifier
            )
            return
        }

        switch sendResult {
        case .unavailable:
            retryAttemptCount = 0
            scheduleNextDay(after: Date())
            return
        case .failed:
            scheduleRetryOrNextDay()
            return
        case .scheduled:
            break
        }

        let promptedAt = Date()
        guard Calendar.current.isDate(now, inSameDayAs: promptedAt) else {
            NotificationManager.shared.cancel(
                identifier: Constants.todayPlanningReminderNotificationIdentifier
            )
            retryAttemptCount = 0
            scheduleEvaluation(after: configuredDelaySeconds)
            return
        }

        do {
            let latestRecords = try modelContext.fetch(FetchDescriptor<SecondBrainRecord>())
            guard !TodayPlanningReminderPolicy.hasTodayTask(
                in: latestRecords,
                now: promptedAt
            ) else {
                NotificationManager.shared.cancel(
                    identifier: Constants.todayPlanningReminderNotificationIdentifier
                )
                retryAttemptCount = 0
                scheduleNextDay(after: promptedAt)
                return
            }
        } catch {
            NotificationManager.shared.cancel(
                identifier: Constants.todayPlanningReminderNotificationIdentifier
            )
            print("오늘 할 일 계획 알림 재확인 실패: \(error.localizedDescription)")
            scheduleRetryOrNextDay()
            return
        }

        retryAttemptCount = 0
        UserDefaults.standard.set(
            promptedAt.timeIntervalSince1970,
            forKey: Constants.AppStorageKey.todayPlanningReminderLastPromptDay
        )
        scheduleNextDay(after: promptedAt)
    }

    private func scheduleRetryOrNextDay() {
        if retryAttemptCount == 0 {
            retryAttemptCount = 1
            scheduleEvaluation(after: 60)
        } else {
            retryAttemptCount = 0
            scheduleNextDay(after: Date())
        }
    }

    private func scheduleNextDay(after date: Date) {
        let nextDate = TodayPlanningReminderPolicy.nextDayEvaluationDate(
            after: date,
            delaySeconds: configuredDelaySeconds
        )
        scheduleEvaluation(after: nextDate.timeIntervalSinceNow)
    }

    private func lastPromptedAtFromDefaults() -> Date? {
        let key = Constants.AppStorageKey.todayPlanningReminderLastPromptDay
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        return Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: key))
    }
}

final class NotificationManager: NSObject, @unchecked Sendable, UNUserNotificationCenterDelegate {
    enum AlertAuthorizationState: Equatable {
        case available
        case notDetermined
        case unavailable
    }

    enum ImmediateSendResult {
        case scheduled
        case unavailable
        case failed
    }

    static let shared = NotificationManager()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        Task {
            _ = await requestAuthorizationIfNeeded()
        }
    }

    func requestAuthorizationIfNeeded() async -> AlertAuthorizationState {
        let center = UNUserNotificationCenter.current()
        let currentState = await alertAuthorizationState()
        guard currentState == .notDetermined else {
            return currentState
        }

        await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
                if let error {
                    print("알림 권한 요청 실패: \(error.localizedDescription)")
                }
                continuation.resume()
            }
        }
        return await alertAuthorizationState()
    }

    func alertAuthorizationState() async -> AlertAuthorizationState {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return Self.alertAuthorizationState(
            authorizationStatus: settings.authorizationStatus,
            alertSetting: settings.alertSetting,
            alertStyle: settings.alertStyle
        )
    }

    static func alertAuthorizationState(
        authorizationStatus: UNAuthorizationStatus,
        alertSetting: UNNotificationSetting,
        alertStyle: UNAlertStyle
    ) -> AlertAuthorizationState {
        switch authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .authorized, .provisional, .ephemeral:
            return alertSetting == .enabled && alertStyle != .none
                ? .available
                : .unavailable
        case .denied:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    func send(
        title: String,
        subtitle: String = "",
        body: String
    ) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error = error {
                print("알림 전송 실패: \(error.localizedDescription)")
            }
        }
    }

    func sendAwaitingResult(
        title: String,
        body: String,
        identifier: String? = nil
    ) async -> ImmediateSendResult {
        guard await alertAuthorizationState() == .available else {
            return .unavailable
        }
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier ?? UUID().uuidString,
            content: content,
            trigger: nil
        )

        return await withCheckedContinuation { continuation in
            center.add(request) { error in
                if let error {
                    print("알림 전송 실패: \(error.localizedDescription)")
                }
                continuation.resume(returning: error == nil ? .scheduled : .failed)
            }
        }
    }

    func scheduleMemoReminder(identifier: String, title: String, body: String, at date: Date) {
        guard date > Date() else {
            cancel(identifier: identifier)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("메모 알림 예약 실패: \(error.localizedDescription)")
            }
        }
    }

    func cancel(identifier: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let shouldOpenTodayTaskComposer = response.notification.request.identifier
            == Constants.todayPlanningReminderNotificationIdentifier
        completionHandler()

        guard shouldOpenTodayTaskComposer,
              UserDefaults.standard.bool(
                  forKey: Constants.AppStorageKey.todayPlanningReminderEnabled
              ) else {
            return
        }
        Task { @MainActor in
            NotificationCenter.default.post(name: .todayPlanningReminderSelected, object: nil)
        }
    }
}
