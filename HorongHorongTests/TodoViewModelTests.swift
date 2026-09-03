import XCTest
@testable import 호롱호롱

/// **화면을 띄우지 않고** 묶기·선택·삭제 흐름을 검사한다.
///
/// 예전에는 이 동작이 `TodoBrowserView.makeSnapshot()` 안에 있어서 확인하려면 앱을 실행하고
/// 눈으로 봐야 했다. 계층을 나눈 이유 중 하나가 이것이다.
@MainActor
final class TodoViewModelTests: XCTestCase {
    /// 저장소를 흉내 내는 가짜. SwiftData 도 EventKit 도 알림도 쓰지 않는다.
    private final class FakeRepository: TodoRepository {
        var items: [TodoItem] = []
        var lists: [ReminderListOption] = []
        private(set) var activeFetchCount = 0
        var linkShouldFail = false

        func activeTodos(matching query: String) throws -> [TodoItem] {
            activeFetchCount += 1
            return filter(items.filter { !$0.isRecentlyDeleted }, query)
        }

        func recentlyDeleted(matching query: String) throws -> [TodoItem] {
            filter(items.filter(\.isRecentlyDeleted), query)
                .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
        }

        func todo(id: UUID) throws -> TodoItem? { items.first { $0.id == id } }

        func linkableTodos(matching query: String) throws -> [TodoItem] { filter(items, query) }

        @discardableResult
        func add(title: String) throws -> TodoItem {
            let made = TodoItem(
                id: UUID(), content: title, startDate: Date(), deadline: nil,
                isCompleted: false, deletedAt: nil, isLinkedToReminders: false,
                reminderCalendarIdentifier: nil,
                icon: nil, isPinned: false, createdAt: Date(), updatedAt: Date()
            )
            items.append(made)
            return made
        }

        func updateContent(id: UUID, content: String) throws {
            replace(id) { $0.with(content: content) }
        }

        func setCompleted(id: UUID, isCompleted: Bool) throws {
            replace(id) { $0.with(isCompleted: isCompleted) }
        }

        func setSchedule(id: UUID, startDate: Date?, deadline: Date?) throws {
            replace(id) {
                $0.with(startDate: .some(startDate), deadline: .some(deadline))
            }
        }

        func place(id: UUID, into bucket: TodoBucket, now: Date) throws {
            replace(id) { item in
                // 실제 구현과 같은 규칙을 쓴다. 여기서 흉내만 내면 테스트가 아무것도 못 지킨다.
                let placed = TodoBucket.placement(
                    into: bucket,
                    startDate: item.startDate,
                    deadline: item.deadline,
                    isCompleted: item.isCompleted,
                    now: now
                )
                return item
                    .with(startDate: .some(placed.startDate), deadline: .some(placed.deadline))
                    .with(isCompleted: placed.isCompleted)
                    .with(deletedAt: .some(nil))
            }
        }

        func setPinned(id: UUID, isPinned: Bool) throws {
            replace(id) { $0.withPinned(isPinned) }
        }

        func setIcon(id: UUID, icon: String) throws {
            replace(id) { $0.withIcon(icon) }
        }

        func setReminderList(id: UUID, listID: String) throws {
            replace(id) { $0.with(reminderCalendarIdentifier: .some(listID)) }
        }

        func reminderLists() async throws -> [ReminderListOption] { lists }

        func linkReminder(id: UUID) async throws {
            if linkShouldFail { throw CocoaError(.fileNoSuchFile) }
            replace(id) { $0.with(isLinkedToReminders: true) }
        }

        func syncReminder(id: UUID) async throws {}

        func unlinkReminder(id: UUID) throws {
            replace(id) { $0.with(isLinkedToReminders: false) }
        }

        func moveToRecentlyDeleted(id: UUID) throws {
            replace(id) { $0.with(deletedAt: .some(Date())) }
        }

        func restore(id: UUID) throws {
            replace(id) { $0.with(deletedAt: .some(nil)) }
        }

        func deletePermanently(id: UUID) throws { items.removeAll { $0.id == id } }

        func emptyRecentlyDeleted() throws { items.removeAll(where: \.isRecentlyDeleted) }

        private func filter(_ source: [TodoItem], _ query: String) -> [TodoItem] {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return source }
            return source.filter { $0.content.localizedCaseInsensitiveContains(trimmed) }
        }

        private func replace(_ id: UUID, _ change: (TodoItem) -> TodoItem) {
            guard let index = items.firstIndex(where: { $0.id == id }) else { return }
            items[index] = change(items[index])
        }
    }

    // MARK: - 준비

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
    }

    private func item(
        _ content: String,
        start: Date? = nil,
        deadline: Date? = nil,
        completed: Bool = false,
        linked: Bool = false,
        deletedAt: Date? = nil
    ) -> TodoItem {
        TodoItem(
            id: UUID(), content: content, startDate: start, deadline: deadline,
            isCompleted: completed, deletedAt: deletedAt, isLinkedToReminders: linked,
            reminderCalendarIdentifier: nil,
            icon: nil, isPinned: false, createdAt: Date(), updatedAt: Date()
        )
    }

    private func makeFilled() -> (TodoViewModel, FakeRepository) {
        let repository = FakeRepository()
        repository.items = [
            item("어제 할 일", start: day(-1)),
            item("오늘 할 일", start: day(0)),
            item("내일 할 일", start: day(1)),
            item("날짜 없는 할 일"),
            item("끝낸 할 일", start: day(0), completed: true),
            item("지운 할 일", start: day(0), deletedAt: Date())
        ]
        return (TodoViewModel(repository: repository), repository)
    }

    // MARK: - 묶기

    func testBucketsSplitByDate() {
        let (viewModel, _) = makeFilled()
        viewModel.reload()

        XCTAssertEqual(viewModel.overdue.map(\.displayTitle), ["어제 할 일"])
        XCTAssertEqual(viewModel.today.map(\.displayTitle), ["오늘 할 일"])
        XCTAssertEqual(viewModel.upcoming.map(\.displayTitle), ["내일 할 일"])
        XCTAssertEqual(viewModel.someday.map(\.displayTitle), ["날짜 없는 할 일"])
        XCTAssertEqual(viewModel.completed.map(\.displayTitle), ["끝낸 할 일"])
        XCTAssertEqual(viewModel.recentlyDeleted.map(\.displayTitle), ["지운 할 일"])
    }

    /// 한 번 그릴 때 한 번만 가져온다. 예전 구조에서는 body 평가마다 전량 순회가 12~17회였다.
    func testReloadFetchesOnce() {
        let (viewModel, repository) = makeFilled()
        viewModel.reload()

        XCTAssertEqual(repository.activeFetchCount, 1)
    }

    func testGroupsSortByDueDate() {
        let repository = FakeRepository()
        repository.items = [
            item("모레", start: day(2)),
            item("내일", start: day(1)),
            item("사흘 뒤", start: day(3))
        ]
        let viewModel = TodoViewModel(repository: repository)
        viewModel.reload()

        XCTAssertEqual(viewModel.upcoming.map(\.displayTitle), ["내일", "모레", "사흘 뒤"])
    }

    /// 연동 수는 **끝나지 않은** 할 일만 센다.
    func testLinkedCountIgnoresCompleted() {
        let repository = FakeRepository()
        repository.items = [
            item("연동 · 진행", start: day(0), linked: true),
            item("연동 · 완료", start: day(0), completed: true, linked: true),
            item("연동 안 함", start: day(0))
        ]
        let viewModel = TodoViewModel(repository: repository)
        viewModel.reload()

        XCTAssertEqual(viewModel.linkedCount, 1)
    }

    func testSearchFiltersAndReloads() {
        let (viewModel, repository) = makeFilled()
        viewModel.reload()
        let before = repository.activeFetchCount

        viewModel.searchText = "내일"

        XCTAssertGreaterThan(repository.activeFetchCount, before)
        XCTAssertEqual(viewModel.upcoming.count, 1)
        XCTAssertTrue(viewModel.today.isEmpty)
    }

    // MARK: - 쓰기

    func testToggleCompletedMovesBucket() {
        let (viewModel, _) = makeFilled()
        viewModel.reload()
        let target = try! XCTUnwrap(viewModel.today.first)

        viewModel.toggleCompleted(target)

        XCTAssertTrue(viewModel.today.isEmpty)
        XCTAssertEqual(viewModel.completed.count, 2)
    }

    func testSubmitComposerAddsAndSelects() {
        let (viewModel, _) = makeFilled()
        viewModel.reload()

        viewModel.composerText = "새 할 일"
        viewModel.submitComposer()

        XCTAssertEqual(viewModel.selected?.displayTitle, "새 할 일")
        XCTAssertEqual(viewModel.composerText, "")
        XCTAssertEqual(viewModel.titleDraft, "새 할 일")
    }

    func testBlankComposerIsIgnored() {
        let (viewModel, repository) = makeFilled()
        viewModel.reload()
        let before = repository.items.count

        viewModel.composerText = "  \n "
        viewModel.submitComposer()

        XCTAssertEqual(repository.items.count, before)
        XCTAssertFalse(viewModel.canSubmitComposer)
    }

    func testClearScheduleMovesToSomeday() {
        let (viewModel, _) = makeFilled()
        viewModel.reload()
        let target = try! XCTUnwrap(viewModel.today.first)

        viewModel.clearSchedule(target.id)

        XCTAssertTrue(viewModel.today.isEmpty)
        XCTAssertEqual(viewModel.someday.count, 2)
    }

    func testSetDurationCalculatesDeadlineFromStart() {
        let start = day(0)
        let repository = FakeRepository()
        let target = item("집중할 일", start: start)
        repository.items = [target]
        let viewModel = TodoViewModel(repository: repository)
        viewModel.reload()

        viewModel.setDuration(target.id, minutes: 90)

        let changed = try! XCTUnwrap(repository.items.first)
        XCTAssertEqual(changed.startDate, start)
        XCTAssertEqual(changed.deadline, start.addingTimeInterval(90 * 60))
        XCTAssertEqual(changed.durationMinutes, 90)
    }

    func testMovingStartPreservesDuration() {
        let start = day(0)
        let repository = FakeRepository()
        let target = item(
            "옮길 일",
            start: start,
            deadline: start.addingTimeInterval(30 * 60)
        )
        repository.items = [target]
        let viewModel = TodoViewModel(repository: repository)
        viewModel.reload()
        let movedStart = start.addingTimeInterval(3 * 60 * 60)

        viewModel.setStartDate(target.id, date: movedStart)

        let changed = try! XCTUnwrap(repository.items.first)
        XCTAssertEqual(changed.startDate, movedStart)
        XCTAssertEqual(changed.deadline, movedStart.addingTimeInterval(30 * 60))
        XCTAssertEqual(changed.durationMinutes, 30)
    }

    func testEditingDeadlineRecalculatesDuration() {
        let start = day(0)
        let repository = FakeRepository()
        let target = item("늘릴 일", start: start, deadline: start.addingTimeInterval(30 * 60))
        repository.items = [target]
        let viewModel = TodoViewModel(repository: repository)
        viewModel.reload()

        viewModel.setDeadline(target.id, date: start.addingTimeInterval(150 * 60))

        XCTAssertEqual(repository.items.first?.durationMinutes, 150)
    }

    func testDeadlineBeforeStartIsIgnored() {
        let start = day(0)
        let repository = FakeRepository()
        let target = item("범위 검사", start: start, deadline: start.addingTimeInterval(60 * 60))
        repository.items = [target]
        let viewModel = TodoViewModel(repository: repository)
        viewModel.reload()

        viewModel.setDeadline(target.id, date: start.addingTimeInterval(-60))

        XCTAssertEqual(repository.items.first?.deadline, start.addingTimeInterval(60 * 60))
    }

    func testClearingDeadlineKeepsStart() {
        let start = day(0)
        let repository = FakeRepository()
        let target = item("종료만 지울 일", start: start, deadline: start.addingTimeInterval(60 * 60))
        repository.items = [target]
        let viewModel = TodoViewModel(repository: repository)
        viewModel.reload()

        viewModel.clearDeadline(target.id)

        XCTAssertEqual(repository.items.first?.startDate, start)
        XCTAssertNil(repository.items.first?.deadline)
    }

    /// 끌어다 놓으면 그 묶음의 규칙대로 날짜·완료가 다시 정해진다.
    func testMoveIntoBucketRepositionsItem() {
        let (viewModel, _) = makeFilled()
        viewModel.reload()
        let target = try! XCTUnwrap(viewModel.someday.first)

        viewModel.move(idString: target.id.uuidString, to: .today)

        XCTAssertTrue(viewModel.someday.isEmpty)
        XCTAssertEqual(viewModel.today.count, 2)
        XCTAssertEqual(viewModel.selected?.id, target.id)
    }

    func testMoveIgnoresUnknownIdentifier() {
        let (viewModel, _) = makeFilled()
        viewModel.reload()

        viewModel.move(idString: "not-a-uuid", to: .today)

        XCTAssertEqual(viewModel.today.count, 1)
    }

    // MARK: - 삭제와 되돌리기

    /// 첫 삭제는 최근 삭제로 간다. 되돌릴 여지를 남기기 위해서다.
    func testDeleteMovesToRecentlyDeleted() {
        let (viewModel, _) = makeFilled()
        viewModel.reload()
        let target = try! XCTUnwrap(viewModel.today.first)

        viewModel.armPendingDelete(target.id)
        viewModel.commitPendingDeleteIfNeeded()

        XCTAssertTrue(viewModel.today.isEmpty)
        XCTAssertEqual(viewModel.recentlyDeleted.count, 2)
    }

    /// 최근 삭제에 있는 것을 또 지우면 완전히 사라진다.
    func testDeletingAlreadyDeletedRemovesPermanently() {
        let (viewModel, repository) = makeFilled()
        viewModel.reload()
        let target = try! XCTUnwrap(viewModel.recentlyDeleted.first)

        viewModel.armPendingDelete(target.id)
        viewModel.commitPendingDeleteIfNeeded()

        XCTAssertTrue(viewModel.recentlyDeleted.isEmpty)
        XCTAssertFalse(repository.items.contains { $0.id == target.id })
    }

    func testCancelPendingDeleteKeepsItem() {
        let (viewModel, _) = makeFilled()
        viewModel.reload()
        let target = try! XCTUnwrap(viewModel.today.first)

        viewModel.armPendingDelete(target.id)
        viewModel.cancelPendingDelete()
        viewModel.commitPendingDeleteIfNeeded()

        XCTAssertEqual(viewModel.today.count, 1)
        XCTAssertNil(viewModel.pendingDeleteID)
    }

    func testRestoreBringsItemBack() {
        let (viewModel, _) = makeFilled()
        viewModel.reload()
        let target = try! XCTUnwrap(viewModel.recentlyDeleted.first)

        viewModel.restore(target.id)

        XCTAssertTrue(viewModel.recentlyDeleted.isEmpty)
        XCTAssertEqual(viewModel.today.count, 2)
        XCTAssertEqual(viewModel.selected?.id, target.id)
    }

    func testEmptyRecentlyDeletedClearsGroup() {
        let (viewModel, _) = makeFilled()
        viewModel.reload()

        viewModel.emptyRecentlyDeleted()

        XCTAssertTrue(viewModel.recentlyDeleted.isEmpty)
    }

    // MARK: - 선택과 편집

    /// 고른 항목이 사라지면 다음 항목으로 옮긴다. 빈 상세 화면이 남지 않게.
    func testSelectionMovesWhenSelectedDisappears() {
        let (viewModel, _) = makeFilled()
        viewModel.reload()
        let target = try! XCTUnwrap(viewModel.overdue.first)
        viewModel.select(target.id)

        viewModel.armPendingDelete(target.id)
        viewModel.commitPendingDeleteIfNeeded()

        XCTAssertNotEqual(viewModel.selected?.id, target.id)
        XCTAssertNotNil(viewModel.selected)
    }

    /// 제목·메모 두 칸이 본문 한 덩어리로 되돌아간다. 빈 줄이 사라지면 안 된다.
    func testDraftSplitAndJoinRoundTrips() {
        let target = item("제목\n\n메모 첫 줄\n둘째 줄")
        XCTAssertEqual(target.split.title, "제목")
        XCTAssertEqual(target.split.note, "\n메모 첫 줄\n둘째 줄")
        XCTAssertEqual(
            TodoItem.joined(title: target.split.title, note: target.split.note),
            target.content
        )

        XCTAssertEqual(TodoItem.joined(title: "제목만", note: "   "), "제목만", "빈 메모는 붙이지 않는다")
        XCTAssertEqual(item("").displayTitle, "제목 없음")
    }

    func testSelectLoadsDrafts() {
        let (viewModel, _) = makeFilled()
        viewModel.reload()
        let target = try! XCTUnwrap(viewModel.upcoming.first)

        viewModel.select(target.id)

        XCTAssertEqual(viewModel.titleDraft, "내일 할 일")
        XCTAssertEqual(viewModel.noteDraft, "")
    }

    // MARK: - 미리알림

    func testToggleReminderLinksAndUnlinks() async {
        let (viewModel, _) = makeFilled()
        viewModel.reload()
        let target = try! XCTUnwrap(viewModel.today.first)

        viewModel.toggleReminder(target)
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(viewModel.today.first?.isLinkedToReminders, true)
        XCTAssertEqual(viewModel.reminderStatusMessage, "연동됨")

        viewModel.toggleReminder(try! XCTUnwrap(viewModel.today.first))
        XCTAssertEqual(viewModel.today.first?.isLinkedToReminders, false)
        XCTAssertEqual(viewModel.reminderStatusMessage, "연동 안 함")
    }

    /// 연결에 실패하면 «연동됨» 으로 남기지 않고 이유를 보여준다.
    func testLinkFailureShowsMessage() async {
        let (viewModel, repository) = makeFilled()
        repository.linkShouldFail = true
        viewModel.reload()
        let target = try! XCTUnwrap(viewModel.today.first)

        viewModel.toggleReminder(target)
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(viewModel.today.first?.isLinkedToReminders, false)
        XCTAssertFalse(viewModel.reminderStatusMessage.isEmpty)
        XCTAssertNotEqual(viewModel.reminderStatusMessage, "연동됨")
    }
}

/// 값 타입을 «한 군데만 바꾼 사본» 으로 만든다. 가짜 저장소 전용이라 테스트 안에 둔다.
///
/// `Optional` 필드는 «안 바꿈» 과 «nil 로 바꿈» 을 구분해야 해서 이중 옵셔널을 받는다.
private extension TodoItem {
    func withPinned(_ value: Bool) -> TodoItem {
        TodoItem(
            id: id, content: content, startDate: startDate, deadline: deadline,
            isCompleted: isCompleted, deletedAt: deletedAt,
            isLinkedToReminders: isLinkedToReminders,
            reminderCalendarIdentifier: reminderCalendarIdentifier,
            icon: icon, isPinned: value, createdAt: createdAt, updatedAt: updatedAt
        )
    }

    func withIcon(_ value: String) -> TodoItem {
        TodoItem(
            id: id, content: content, startDate: startDate, deadline: deadline,
            isCompleted: isCompleted, deletedAt: deletedAt,
            isLinkedToReminders: isLinkedToReminders,
            reminderCalendarIdentifier: reminderCalendarIdentifier,
            icon: value, isPinned: isPinned, createdAt: createdAt, updatedAt: updatedAt
        )
    }

    func with(
        content: String? = nil,
        startDate: Date?? = nil,
        deadline: Date?? = nil,
        isCompleted: Bool? = nil,
        deletedAt: Date?? = nil,
        isLinkedToReminders: Bool? = nil,
        reminderCalendarIdentifier: String?? = nil
    ) -> TodoItem {
        TodoItem(
            id: id,
            content: content ?? self.content,
            startDate: startDate ?? self.startDate,
            deadline: deadline ?? self.deadline,
            isCompleted: isCompleted ?? self.isCompleted,
            deletedAt: deletedAt ?? self.deletedAt,
            isLinkedToReminders: isLinkedToReminders ?? self.isLinkedToReminders,
            reminderCalendarIdentifier: reminderCalendarIdentifier ?? self.reminderCalendarIdentifier,
            icon: icon,
            isPinned: isPinned,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
