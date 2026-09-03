import Foundation
import Observation

/// 할 일 화면의 상태.
///
/// **`@Query` 를 쓰지 않는다.** 예전에는 `@Query` 가 준 배열을 body 평가마다 다시 훑어
/// 묶음을 만들었다 — 한 번 그릴 때 전량 순회 12~17회. 지금은 «바뀐 것을 아는 쪽» 이
/// `reload()` 를 부르고, 묶기는 그때 한 번만 한다.
@MainActor
@Observable
final class TodoViewModel {
    private(set) var overdue: [TodoItem] = []
    private(set) var today: [TodoItem] = []
    private(set) var upcoming: [TodoItem] = []
    private(set) var someday: [TodoItem] = []
    private(set) var completed: [TodoItem] = []
    private(set) var recentlyDeleted: [TodoItem] = []
    /// 미리알림에 연동된 «끝나지 않은» 할 일 수. 머리말에 보인다.
    private(set) var linkedCount = 0

    private(set) var selected: TodoItem?
    private(set) var reminderLists: [ReminderListOption] = []
    private(set) var reminderStatusMessage = ""
    /// 지우기 직전 «취소» 를 받는 동안의 항목. 1.5초 뒤 확정된다.
    private(set) var pendingDeleteID: UUID?

    /// 묶음을 나누는 기준 시각. 자정을 넘기면 바뀐다 — 저장하지 않는다(CLAUDE.md 하드 룰 2).
    private(set) var todayReferenceDate = Date()

    var searchText = "" { didSet { guard searchText != oldValue else { return }; reload() } }
    var composerText = ""
    /// 편집 중인 제목·메모. **타건은 여기서 끝난다** — 저장은 400ms 뒤 한 번.
    var titleDraft = ""
    var noteDraft = ""

    private let repository: TodoRepository
    private var saveTask: Task<Void, Never>?
    private var pendingDeleteTask: Task<Void, Never>?

    init(repository: TodoRepository) {
        self.repository = repository
    }

    var canSubmitComposer: Bool {
        !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - 읽기

    /// 한 번 가져와 **한 번만 순회하며** 다섯 묶음과 연동 수를 함께 만든다.
    func reload() {
        let active = (try? repository.activeTodos(matching: searchText)) ?? []
        recentlyDeleted = (try? repository.recentlyDeleted(matching: searchText)) ?? []

        var buckets: [TodoBucket: [TodoItem]] = [:]
        var linked = 0
        for item in active {
            if !item.isCompleted, item.isLinkedToReminders { linked += 1 }
            buckets[item.bucket(now: todayReferenceDate), default: []].append(item)
        }
        linkedCount = linked

        // 정렬은 묶음마다 한 번씩. 전량을 다섯 번 정렬하던 것보다 다루는 배열이 훨씬 작다.
        func byDue(_ bucket: TodoBucket) -> [TodoItem] {
            (buckets[bucket] ?? []).sorted { $0.dueSortKey < $1.dueSortKey }
        }
        overdue = byDue(.overdue)
        today = byDue(.today)
        upcoming = byDue(.upcoming)
        someday = byDue(.someday)
        completed = byDue(.completed)

        syncSelection()
    }

    /// 자정을 넘겼을 때. 기준 시각이 바뀌면 묶음이 달라진다.
    func dayChanged() {
        todayReferenceDate = Date()
        reload()
    }

    func loadReminderLists() {
        Task { @MainActor in
            reminderLists = (try? await repository.reminderLists()) ?? []
        }
    }

    /// 목록에 보이는 순서. 선택이 사라졌을 때 다음 항목을 고르는 데 쓴다.
    var visible: [TodoItem] { overdue + today + upcoming + someday + completed }

    func select(_ id: UUID?) {
        flush()
        selected = id.flatMap { try? repository.todo(id: $0) }
        loadDrafts()
    }

    func reminderList(for item: TodoItem) -> ReminderListOption? {
        if let id = item.reminderCalendarIdentifier,
           let list = reminderLists.first(where: { $0.id == id }) {
            return list
        }
        return item.isLinkedToReminders ? reminderLists.first(where: \.isDefault) : nil
    }

    /// 시작 날짜 빠른 선택(«오늘»·«내일»)이 눌린 상태인지.
    func isStartDay(_ item: TodoItem, dayOffset: Int) -> Bool {
        guard let basis = item.startDate else { return false }
        let calendar = Calendar.current
        let target = calendar.date(byAdding: .day, value: dayOffset, to: todayReferenceDate) ?? todayReferenceDate
        return calendar.isDate(basis, inSameDayAs: target)
    }

    // MARK: - 쓰기

    func submitComposer() {
        let title = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        guard let created = try? repository.add(title: title) else { return }
        composerText = ""
        reload()
        selected = created
        loadDrafts()
    }

    func toggleCompleted(_ item: TodoItem) {
        try? repository.setCompleted(id: item.id, isCompleted: !item.isCompleted)
        refresh(item.id)
    }

    func clearSchedule(_ id: UUID) {
        try? repository.setSchedule(id: id, startDate: nil, deadline: nil)
        refresh(id)
    }

    /// 시작을 옮길 때 이미 정한 소요 시간은 유지한다.
    func setStartDate(_ id: UUID, date: Date) {
        guard let item = try? repository.todo(id: id) else { return }
        let duration = item.startDate.flatMap { start in
            item.deadline.map { $0.timeIntervalSince(start) }
        }
        let deadline = duration.flatMap { $0 > 0 ? date.addingTimeInterval($0) : nil }
        try? repository.setSchedule(id: id, startDate: date, deadline: deadline)
        refresh(id)
    }

    func setStartDay(_ id: UUID, dayOffset: Int) {
        guard let item = try? repository.todo(id: id) else { return }
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: dayOffset, to: todayReferenceDate) ?? todayReferenceDate
        let time = item.startDate.map { calendar.dateComponents([.hour, .minute], from: $0) }
            ?? DateComponents(hour: 9, minute: 0)
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = time.hour
        components.minute = time.minute
        setStartDate(id, date: calendar.date(from: components) ?? day)
    }

    func setDuration(_ id: UUID, minutes: Int) {
        guard minutes > 0,
              let item = try? repository.todo(id: id),
              let startDate = item.startDate else { return }
        let deadline = startDate.addingTimeInterval(TimeInterval(minutes * 60))
        try? repository.setSchedule(id: id, startDate: startDate, deadline: deadline)
        refresh(id)
    }

    func setDeadline(_ id: UUID, date: Date) {
        guard let item = try? repository.todo(id: id),
              item.startDate.map({ date >= $0 }) ?? true else { return }
        try? repository.setSchedule(id: id, startDate: item.startDate, deadline: date)
        refresh(id)
    }

    func clearDeadline(_ id: UUID) {
        guard let item = try? repository.todo(id: id) else { return }
        try? repository.setSchedule(id: id, startDate: item.startDate, deadline: nil)
        refresh(id)
    }

    func setReminderList(_ id: UUID, listID: String) {
        try? repository.setReminderList(id: id, listID: listID)
        refresh(id)
    }

    func toggleReminder(_ item: TodoItem) {
        if item.isLinkedToReminders {
            unlink(item.id)
        } else {
            loadReminderLists()
            link(item.id)
        }
    }

    /// 끌어다 놓기. 놓인 묶음에 맞게 날짜·완료가 다시 정해진다.
    func move(idString: String, to bucket: TodoBucket) {
        guard let id = UUID(uuidString: idString) else { return }
        try? repository.place(id: id, into: bucket, now: todayReferenceDate)
        refresh(id)
        selected = try? repository.todo(id: id)
        loadDrafts()
    }

    func restore(_ id: UUID) {
        try? repository.restore(id: id)
        refresh(id)
        selected = try? repository.todo(id: id)
        loadDrafts()
    }

    func emptyRecentlyDeleted() {
        try? repository.emptyRecentlyDeleted()
        if selected?.isRecentlyDeleted == true { selected = nil }
        reload()
    }

    // MARK: - 삭제(되돌릴 틈을 준다)

    /// 바로 지우지 않고 1.5초 «취소» 를 받는다. 그동안 행이 빨간 막대로 바뀐다.
    func armPendingDelete(_ id: UUID) {
        commitPendingDeleteIfNeeded()
        if selected?.id == id { selected = nil; clearDrafts() }
        pendingDeleteID = id
        pendingDeleteTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1_500))
            guard let self, !Task.isCancelled, self.pendingDeleteID == id else { return }
            self.pendingDeleteID = nil
            self.pendingDeleteTask = nil
            self.finishDelete(id)
        }
    }

    func cancelPendingDelete() {
        pendingDeleteTask?.cancel()
        pendingDeleteTask = nil
        pendingDeleteID = nil
    }

    /// 화면을 벗어날 때. 기다리던 삭제는 확정한다 — 취소할 사람이 없어졌으므로.
    func commitPendingDeleteIfNeeded() {
        let id = pendingDeleteID
        pendingDeleteTask?.cancel()
        pendingDeleteTask = nil
        pendingDeleteID = nil
        guard let id else { return }
        finishDelete(id)
    }

    // MARK: - 편집

    /// 제목·메모 칸이 바뀌었다. 타건마다 저장하지 않는다.
    func draftChanged() {
        guard let id = selected?.id else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.persistDraft(id)
        }
    }

    func flush() {
        saveTask?.cancel()
        saveTask = nil
        if let id = selected?.id { persistDraft(id) }
    }

    // MARK: - 내부

    private func finishDelete(_ id: UUID) {
        let item = try? repository.todo(id: id)
        if item?.isRecentlyDeleted == true {
            try? repository.deletePermanently(id: id)
        } else {
            try? repository.moveToRecentlyDeleted(id: id)
        }
        if selected?.id == id { selected = nil }
        reload()
    }

    private func link(_ id: UUID) {
        reminderStatusMessage = "연결 중..."
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.repository.linkReminder(id: id)
                self.reminderStatusMessage = "연동됨"
            } catch {
                self.reminderStatusMessage = error.localizedDescription
            }
            self.refresh(id)
        }
    }

    private func unlink(_ id: UUID) {
        do {
            try repository.unlinkReminder(id: id)
            reminderStatusMessage = "연동 안 함"
        } catch {
            reminderStatusMessage = error.localizedDescription
        }
        refresh(id)
    }

    private func persistDraft(_ id: UUID) {
        let joined = TodoItem.joined(title: titleDraft, note: noteDraft)
        guard joined != selected?.content else { return }
        try? repository.updateContent(id: id, content: joined)
        refresh(id)
    }

    /// 한 건이 바뀌었을 때. 고른 항목을 다시 읽고 목록을 다시 묶는다.
    ///
    /// 목록을 통째로 다시 읽는 것은 낭비로 보이지만, 한 건만 고쳐도 **묶음이 바뀔 수 있다**
    /// (오늘 → 완료, 예정 → 오늘). 자리를 직접 옮기려면 그 규칙을 여기에 한 벌 더 두게 된다.
    private func refresh(_ id: UUID) {
        if selected?.id == id { selected = try? repository.todo(id: id) }
        reload()
    }

    /// 고른 항목이 사라졌으면(삭제·검색으로 걸러짐) 첫 항목으로 옮긴다.
    private func syncSelection() {
        if let selected,
           visible.contains(where: { $0.id == selected.id })
            || recentlyDeleted.contains(where: { $0.id == selected.id }) {
            return
        }
        selected = visible.first
        loadDrafts()
    }

    private func loadDrafts() {
        guard let selected else { return clearDrafts() }
        let parts = selected.split
        titleDraft = parts.title
        noteDraft = parts.note
    }

    private func clearDrafts() {
        titleDraft = ""
        noteDraft = ""
    }
}
