import Foundation
import Observation

/// 팝오버 「기록」 대시보드의 상태와 사용자 의도를 모은다.
@MainActor
@Observable
final class MemoListViewModel {
    private(set) var recentNotes: [QuickNoteItem] = []
    private(set) var todayDiary: DiaryDay?
    private(set) var todos: [TodoItem] = []
    private(set) var reminderLists: [ReminderListOption] = []
    private(set) var todoSaveMessage: String?

    static let representativeMoods: [DiaryMood] = [
        .happy, .motivation, .comfort, .sad, .anxious, .angry, .exhausted,
    ]

    private let todosRepository: TodoRepository
    private let quickNotes: QuickNoteRepository
    private let diary: DiaryRepository
    private let clipboard: ClipboardGateway
    private let calendar: Calendar

    init(
        repository: TodoRepository,
        quickNotes: QuickNoteRepository,
        diary: DiaryRepository,
        clipboard: ClipboardGateway,
        calendar: Calendar = .current
    ) {
        todosRepository = repository
        self.quickNotes = quickNotes
        self.diary = diary
        self.clipboard = clipboard
        self.calendar = calendar
    }

    func reload(now: Date = Date()) {
        recentNotes = (try? quickNotes.recent(limit: 5)) ?? []
        todos = (try? todosRepository.activeTodos(matching: "")) ?? []
        todayDiary = try? diary.entry(on: now)
    }

    func timeline(now: Date) -> TodoTimeline {
        TodoTimelinePolicy.make(todos: todos, now: now, calendar: calendar)
    }

    func copy(_ note: QuickNoteItem) -> Bool {
        clipboard.writeText(note.content)
    }

    @discardableResult
    func appendDiaryCue(_ text: String, now: Date = Date()) -> Bool {
        guard let body = DiaryQuickCapturePolicy.appending(
            text, at: now, to: todayDiary?.body ?? "", calendar: calendar
        ) else { return false }
        guard let updated = try? diary.setBody(on: now, body: body) else { return false }
        todayDiary = updated
        return true
    }

    func moodSlot(now: Date) -> DiaryMoodSlot {
        DiaryQuickCapturePolicy.slot(at: now, calendar: calendar)
    }

    func currentMood(now: Date) -> DiaryMood? {
        todayDiary?.record(moodSlot(now: now))?.mood
    }

    func setMood(_ mood: DiaryMood, now: Date = Date()) {
        let slot = moodSlot(now: now)
        let next = todayDiary?.record(slot)?.mood == mood ? nil : mood
        guard let updated = try? diary.setMood(on: now, slot: slot, mood: next) else { return }
        todayDiary = updated
    }

    @discardableResult
    func submitComposer(_ text: String, now: Date = Date()) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let entry = TodoComposerPolicy.parse(trimmed, now: now, calendar: calendar)
        guard let made = try? todosRepository.add(
            title: entry.title,
            startDate: entry.startDate,
            deadline: entry.deadline
        ) else { return false }
        todos = (try? todosRepository.activeTodos(matching: "")) ?? (todos + [made])
        if made.bucket(now: now) != .today {
            todoSaveMessage = "\(entry.scheduleSummary ?? "예정") 일정으로 저장됨"
        } else {
            todoSaveMessage = nil
        }
        return true
    }

    func clearSaveMessage() { todoSaveMessage = nil }

    func reminderList(for item: TodoItem) -> ReminderListOption? {
        ReminderListPolicy.list(for: item, in: reminderLists)
    }

    func loadReminderLists() async {
        reminderLists = (try? await todosRepository.reminderLists()) ?? []
    }

    func togglePinned(_ item: TodoItem) {
        try? todosRepository.setPinned(id: item.id, isPinned: !item.isPinned)
        reload()
    }

    func toggleCompleted(_ item: TodoItem) {
        try? todosRepository.setCompleted(id: item.id, isCompleted: !item.isCompleted)
        reload()
    }

    func updateContent(_ id: UUID, content: String) {
        try? todosRepository.updateContent(id: id, content: content)
        reload()
    }

    func delete(_ id: UUID) {
        try? todosRepository.moveToRecentlyDeleted(id: id)
        reload()
    }
}
