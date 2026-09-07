import XCTest
@testable import 호롱호롱

/// 할 일이 **어느 미리알림 목록에 속하는지** 정하는 규칙을 못 박는다.
///
/// 두 화면(할 일 상세 · 팝오버 기록 탭)이 같은 답을 내야 해서 규칙을 한 곳에 뒀다.
/// OS 없이 검사한다 — 목록 배열만 주면 되는 순수 계산이어야 한다.
final class ReminderListPolicyTests: XCTestCase {

    private let work = ReminderListOption(id: "A", title: "업무 일정", isDefault: false)
    private let records = ReminderListOption(id: "B", title: "기록", isDefault: true)
    private var lists: [ReminderListOption] { [work, records] }

    private func todo(listID: String?, linked: Bool) -> TodoItem {
        TodoItem(
            id: UUID(),
            content: "할 일",
            startDate: nil,
            deadline: nil,
            isCompleted: false,
            completionStateChangedAt: nil,
            deletedAt: nil,
            isLinkedToReminders: linked,
            reminderCalendarIdentifier: listID,
            isPinned: false,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func testStoredIdentifierWins() {
        XCTAssertEqual(ReminderListPolicy.list(for: todo(listID: "A", linked: true), in: lists), work)
    }

    /// 식별자가 없으면 미리알림 앱이 기본 목록에 넣는다. 화면도 그렇게 보여야 한다.
    func testLinkedTodoWithoutIdentifierFallsBackToDefault() {
        XCTAssertEqual(ReminderListPolicy.list(for: todo(listID: nil, linked: true), in: lists), records)
    }

    /// **연동하지 않은 할 일은 어느 목록에도 속하지 않는다.** 기본 목록을 붙이면
    /// 미리알림에 없는 할 일이 있는 것처럼 보인다.
    func testUnlinkedTodoHasNoList() {
        XCTAssertNil(ReminderListPolicy.list(for: todo(listID: nil, linked: false), in: lists))
    }

    /// 사용자가 미리알림 앱에서 목록을 지웠을 수 있다. 그때도 연동 여부가 기준이다.
    func testVanishedListFallsBackByLinkage() {
        XCTAssertEqual(ReminderListPolicy.list(for: todo(listID: "없는목록", linked: true), in: lists), records)
        XCTAssertNil(ReminderListPolicy.list(for: todo(listID: "없는목록", linked: false), in: lists))
    }

    func testNoListsAtAll() {
        XCTAssertNil(ReminderListPolicy.list(for: todo(listID: "A", linked: true), in: []))
    }
}
