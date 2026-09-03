import Foundation

/// 할 일을 읽고 쓴다. 구현은 `Data/Repositories/` 에 있다.
///
/// **경계를 넘는 것은 값 타입뿐이다** — `Memo`(`@Model`)는 이 프로토콜에 등장하지 않는다.
///
/// 미리알림 연동·로컬 알림 예약도 여기 있다. 그 서비스들이 `Memo` 를 인자로 받기 때문에
/// 밖으로 내보내면 `@Model` 이 Presentation 까지 새어 나온다. **부수효과를 저장과 같은
/// 곳에 두는 편이, 화면이 «저장하고 나서 알림도 다시 걸어라» 를 기억하는 것보다 안전하다.**
@MainActor
protocol TodoRepository {
    /// 살아 있는 할 일 전부(최근 삭제·보관 제외).
    ///
    /// **개수를 제한하지 않는다.** 묶음(지남/오늘/예정/언젠가/완료)은 «지금» 을 기준으로
    /// 계산하는 값이라 SQL 정렬·필터로 표현할 수 없다 — 앞 50건만 가져오면 그 50건 안에서만
    /// 나뉜다. 대신 보관·삭제는 술어로 걸러 DB 에서 떨군다. `[확인 필요]`
    func activeTodos(matching query: String) throws -> [TodoItem]

    /// 최근 삭제함. 지운 시각 역순.
    func recentlyDeleted(matching query: String) throws -> [TodoItem]

    func todo(id: UUID) throws -> TodoItem?

    /// 무언가에 **연결할 대상**으로 고를 할 일. 완료·보관한 것도 포함한다 —
    /// 이미 연결해 둔 것을 다시 찾을 수 있어야 하기 때문이다.
    func linkableTodos(matching query: String) throws -> [TodoItem]

    /// 오늘 오전 9시로 시작일을 잡아 추가한다.
    @discardableResult
    func add(title: String) throws -> TodoItem

    func updateContent(id: UUID, content: String) throws
    func setCompleted(id: UUID, isCompleted: Bool) throws

    /// 날짜를 정한다. `nil` 이면 시작·마감을 모두 지운다(«언젠가»로 간다).
    ///
    /// 시작만 있는 할 일은 시작을, 마감이 있으면 마감을 옮긴다 — 뒤집힘 방지는 모델이 한다.
    func setWhen(id: UUID, date: Date?) throws

    /// 끌어다 놓은 묶음에 맞게 날짜·완료 상태를 다시 정한다.
    func place(id: UUID, into bucket: TodoBucket, now: Date) throws

    func setReminderList(id: UUID, listID: String) throws

    /// 목록 맨 위에 붙여 둔다.
    func setPinned(id: UUID, isPinned: Bool) throws
    func setIcon(id: UUID, icon: String) throws

    /// 미리알림 앱과 연결한다. 실패하면 던진다 — 메시지는 화면이 보여준다.
    func linkReminder(id: UUID) async throws
    /// 이미 연결된 할 일의 내용을 미리알림 쪽에 다시 쓴다.
    func syncReminder(id: UUID) async throws
    func unlinkReminder(id: UUID) throws

    func moveToRecentlyDeleted(id: UUID) throws
    func restore(id: UUID) throws
    func deletePermanently(id: UUID) throws
    func emptyRecentlyDeleted() throws

    /// 미리알림 앱의 목록들. 연동 대상 고르기에 쓴다.
    func reminderLists() async throws -> [ReminderListOption]
}
