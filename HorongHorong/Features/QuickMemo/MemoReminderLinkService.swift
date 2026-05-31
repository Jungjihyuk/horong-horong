import EventKit
import Foundation

@MainActor
final class MemoReminderLinkService {
    static let shared = MemoReminderLinkService()

    private var eventStore = EKEventStore()

    private init() {}

    func reminderLists() async throws -> [ReminderListOption] {
        try await requestAccessIfNeeded()
        return writableReminderCalendars()
            .filter(\.allowsContentModifications)
            .map {
                ReminderListOption(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    isDefault: $0.calendarIdentifier == eventStore.defaultCalendarForNewReminders()?.calendarIdentifier
                )
            }
            .sorted {
                if $0.isDefault != $1.isDefault { return $0.isDefault }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }

    func reminderImportLists() async throws -> [ReminderListOption] {
        try await requestFullAccessIfNeeded()
        let calendars = reminderCalendarsWithRetry()
        return calendars
            .map {
                ReminderListOption(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    isDefault: $0.calendarIdentifier == eventStore.defaultCalendarForNewReminders()?.calendarIdentifier
                )
            }
            .sorted {
                if $0.isDefault != $1.isDefault { return $0.isDefault }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }

    func reminderAccessDiagnostics() -> ReminderAccessDiagnostics {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        refreshSources()
        let calendars = eventStore.calendars(for: .reminder)
        return ReminderAccessDiagnostics(
            authorizationStatus: Self.statusDescription(status),
            sourceCount: eventStore.sources.count,
            reminderCalendarCount: calendars.count,
            writableReminderCalendarCount: calendars.filter(\.allowsContentModifications).count
        )
    }

    func reminderItems(calendarIDs: Set<String>? = nil) async throws -> [ReminderListItem] {
        try await requestFullAccessIfNeeded()
        let calendars = reminderCalendarsWithRetry()
            .filter { calendar in
                guard let calendarIDs else { return true }
                return calendarIDs.contains(calendar.calendarIdentifier)
            }
        let predicate = eventStore.predicateForReminders(in: calendars)
        let items: [ReminderListItem] = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                Task { @MainActor in
                    let items = (reminders ?? []).compactMap { reminder -> ReminderListItem? in
                        guard let calendar = reminder.calendar else {
                            return nil
                        }
                        return ReminderListItem(
                            id: reminder.calendarItemIdentifier,
                            title: reminder.title.nilIfEmpty ?? "제목 없음",
                            notes: reminder.notes,
                            url: reminder.url,
                            startDate: Self.date(from: reminder.startDateComponents),
                            dueDate: Self.date(from: reminder.dueDateComponents),
                            calendarIdentifier: calendar.calendarIdentifier,
                            calendarTitle: calendar.title,
                            isCompleted: reminder.isCompleted
                        )
                    }
                    continuation.resume(returning: items)
                }
            }
        }

        return items
            .sorted {
                if $0.isCompleted != $1.isCompleted { return !$0.isCompleted }
                let left = $0.dueDate ?? .distantFuture
                let right = $1.dueDate ?? .distantFuture
                if left != right { return left < right }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }

    func saveReminder(for memo: Memo) async throws -> String {
        try await requestAccessIfNeeded()

        let content = reminderContent(for: memo)
        let reminder = existingReminder(for: memo) ?? EKReminder(eventStore: eventStore)
        reminder.calendar = targetCalendar(for: memo) ?? reminder.calendar ?? eventStore.defaultCalendarForNewReminders()
        reminder.title = content.title
        reminder.notes = content.notes
        reminder.url = content.url
        reminder.priority = reminderPriority(for: memo)
        reminder.isCompleted = memo.isCompletedValue

        if let startDate = memo.startDate {
            reminder.startDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: startDate)
        } else {
            reminder.startDateComponents = nil
        }

        if let deadline = memo.deadline {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: deadline)
        } else {
            reminder.dueDateComponents = nil
        }
        syncAlarm(for: reminder, memo: memo)

        do {
            try eventStore.save(reminder, commit: true)
        } catch {
            throw normalizedError(error)
        }
        return reminder.calendarItemIdentifier
    }

    func removeReminder(for memo: Memo) throws {
        guard let reminder = existingReminder(for: memo) else { return }
        do {
            try eventStore.remove(reminder, commit: true)
        } catch {
            throw normalizedError(error)
        }
    }

    private func requestAccessIfNeeded() async throws {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        switch status {
        case .fullAccess, .writeOnly, .authorized:
            return
        case .notDetermined:
            let granted: Bool = try await withCheckedThrowingContinuation { continuation in
                eventStore.requestFullAccessToReminders { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
            guard granted else { throw MemoReminderError.accessDenied }
        default:
            throw MemoReminderError.accessDenied
        }
    }

    private func requestFullAccessIfNeeded() async throws {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        switch status {
        case .fullAccess, .authorized:
            return
        case .notDetermined:
            let granted: Bool = try await withCheckedThrowingContinuation { continuation in
                eventStore.requestFullAccessToReminders { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
            guard granted else { throw MemoReminderError.accessDenied }
        case .writeOnly:
            throw MemoReminderError.fullAccessRequired
        default:
            throw MemoReminderError.accessDenied
        }
    }

    private func writableReminderCalendars() -> [EKCalendar] {
        refreshSources()
        return eventStore.calendars(for: .reminder)
    }

    private func reminderCalendarsWithRetry() -> [EKCalendar] {
        refreshSources()
        var calendars = eventStore.calendars(for: .reminder)
        if calendars.isEmpty {
            eventStore.reset()
            eventStore = EKEventStore()
            refreshSources()
            calendars = eventStore.calendars(for: .reminder)
        }
        return calendars
    }

    private func refreshSources() {
        eventStore.refreshSourcesIfNecessary()
    }

    private func existingReminder(for memo: Memo) -> EKReminder? {
        guard let identifier = memo.reminderIdentifier,
              let item = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            return nil
        }
        return item
    }

    private func targetCalendar(for memo: Memo) -> EKCalendar? {
        guard let identifier = memo.reminderCalendarIdentifier else {
            return eventStore.defaultCalendarForNewReminders()
        }
        return eventStore.calendar(withIdentifier: identifier) ?? eventStore.defaultCalendarForNewReminders()
    }

    private static func date(from components: DateComponents?) -> Date? {
        guard var components else { return nil }
        components.calendar = components.calendar ?? Calendar.current
        return components.date
    }

    private func reminderContent(for memo: Memo) -> ReminderContent {
        let trimmed = memo.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ReminderContent(title: "호롱호롱 메모", notes: nil, url: nil)
        }

        let lines = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let title = lines.first ?? "호롱호롱 메모"
        let url = firstURL(in: trimmed)
        let urlText = url?.absoluteString
        let notes = lines
            .dropFirst()
            .filter { $0 != urlText }
            .joined(separator: "\n")
            .nilIfEmpty

        return ReminderContent(title: title, notes: notes, url: url)
    }

    private func firstURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.firstMatch(in: text, options: [], range: range)?.url
    }

    private func reminderPriority(for memo: Memo) -> Int {
        if memo.isPinned || memo.icon == "⭐️" {
            return 1
        }
        return 0
    }

    private func syncAlarm(for reminder: EKReminder, memo: Memo) {
        reminder.alarms?.forEach { reminder.removeAlarm($0) }
        guard let deadline = memo.deadline,
              let offset = memo.reminderOffsetMinutes else {
            return
        }
        let fireDate = deadline.addingTimeInterval(TimeInterval(-offset * 60))
        reminder.addAlarm(EKAlarm(absoluteDate: fireDate))
    }

    private func normalizedError(_ error: Error) -> Error {
        let nsError = error as NSError
        guard nsError.domain == EKErrorDomain else {
            return error
        }
        switch nsError.code {
        case EKError.eventStoreNotAuthorized.rawValue:
            return MemoReminderError.accessDenied
        case EKError.calendarReadOnly.rawValue,
             EKError.calendarDoesNotAllowReminders.rawValue,
             31:
            return MemoReminderError.calendarUnavailable
        default:
            return error
        }
    }

    private static func statusDescription(_ status: EKAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "notDetermined"
        case .restricted:
            return "restricted"
        case .denied:
            return "denied"
        case .authorized:
            return "authorized"
        case .writeOnly:
            return "writeOnly"
        case .fullAccess:
            return "fullAccess"
        @unknown default:
            return "unknown"
        }
    }
}

struct ReminderListOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let isDefault: Bool
}

struct ReminderListItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let notes: String?
    let url: URL?
    let startDate: Date?
    let dueDate: Date?
    let calendarIdentifier: String
    let calendarTitle: String
    let isCompleted: Bool
}

struct ReminderAccessDiagnostics: Hashable, Sendable {
    let authorizationStatus: String
    let sourceCount: Int
    let reminderCalendarCount: Int
    let writableReminderCalendarCount: Int
}

private struct ReminderContent {
    let title: String
    let notes: String?
    let url: URL?
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

enum MemoReminderError: LocalizedError {
    case accessDenied
    case saveFailed
    case removeFailed
    case calendarUnavailable
    case fullAccessRequired

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "미리알림 접근 권한이 필요합니다. 시스템 설정 > 개인정보 보호 및 보안 > 미리 알림에서 호롱호롱을 허용해 주세요."
        case .saveFailed:
            return "미리알림 저장에 실패했습니다."
        case .removeFailed:
            return "미리알림 삭제에 실패했습니다."
        case .calendarUnavailable:
            return "선택한 미리알림 목록에 저장할 수 없습니다. 다른 목록을 선택해 주세요."
        case .fullAccessRequired:
            return "미리알림 목록을 가져오려면 전체 접근 권한이 필요합니다. 시스템 설정 > 개인정보 보호 및 보안 > 미리 알림에서 호롱호롱 권한을 다시 허용해 주세요."
        }
    }
}
