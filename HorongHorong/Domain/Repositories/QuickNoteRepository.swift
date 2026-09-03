import Foundation

/// Quick Note 를 읽고 쓴다. 구현은 `Data/Repositories/` 에 있다.
///
/// **경계를 넘는 것은 값 타입뿐이다** — `Memo`(`@Model`)는 이 프로토콜에 등장하지 않는다.
@MainActor
protocol QuickNoteRepository {
    /// 고정한 것 먼저, 그 다음 최근에 고친 순.
    ///
    /// `limit` 은 **고정하지 않은 쪽에만** 걸린다. 고정한 기록은 몇 건 안 되고 항상 맨 위에
    /// 있어야 하는데, 한 번에 잘라 오면 고정한 것이 51번째에 있을 때 아예 안 보인다.
    func notes(matching query: String, limit: Int) throws -> [QuickNote]

    /// 목록과 무관하게 한 건만. 고른 항목이 현재 페이지 밖일 수 있어서 필요하다.
    func note(id: UUID) throws -> QuickNote?

    @discardableResult
    func add(content: String, icon: String?) throws -> QuickNote

    func updateContent(id: UUID, content: String) throws
    func setPinned(id: UUID, isPinned: Bool) throws

    /// Todo 로 보낸다 — 이 기록은 Quick Note 목록에서 사라진다.
    ///
    /// **왜 `TodoRepository` 가 아니라 여기 있나**: 저장소에서 일어나는 일은 «섹션 값을 바꾼다»
    /// 한 줄이고, 부르는 쪽도 Quick Note 화면뿐이다. Todo 쪽에서도 되돌리는 기능이 생기면
    /// 그때 «섹션을 옮긴다» 를 별도 계약으로 뺀다. `[확인 필요]`
    func promoteToTodo(id: UUID) throws

    func delete(id: UUID) throws
}
