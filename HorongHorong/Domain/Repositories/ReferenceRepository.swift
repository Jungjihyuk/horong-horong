import Foundation

/// 참고 자료를 읽고 쓴다. 구현은 `Data/Repositories/` 에 있다.
///
/// **경계를 넘는 것은 값 타입뿐이다** — `Memo`(`@Model`)는 이 프로토콜에 등장하지 않는다.
///
/// `limit` 을 시그니처에 드러낸 이유: 참고 자료는 상한 없이 는다.
/// «전부 주세요» 를 부르는 쪽이 실수로 쓰지 못하게 개수를 반드시 말하게 한다.
@MainActor
protocol ReferenceRepository {
    /// 최근에 고친 순서로 `limit` 개. `query` 가 있으면 본문에서 찾는다.
    func references(matching query: String, limit: Int) throws -> [ReferenceItem]

    /// 목록과 무관하게 한 건만. 고른 항목이 현재 페이지 밖일 수 있어서 필요하다.
    func reference(id: UUID) throws -> ReferenceItem?

    @discardableResult
    func add(content: String) throws -> ReferenceItem

    func updateContent(id: UUID, content: String) throws
    func delete(id: UUID) throws
}
