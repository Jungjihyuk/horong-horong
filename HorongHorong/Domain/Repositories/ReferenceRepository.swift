import Foundation

/// 참고 자료를 읽고 쓴다. 구현은 `Data/Repositories/` 에 있다.
///
/// **경계를 넘는 것은 값 타입뿐이다** — `Reference`(`@Model`)는 이 프로토콜에 등장하지 않는다.
///
/// `limit` 을 시그니처에 드러낸 이유: 참고 자료는 상한 없이 는다.
/// «전부 주세요» 를 부르는 쪽이 실수로 쓰지 못하게 개수를 반드시 말하게 한다.
@MainActor
protocol ReferenceRepository {
    /// 최근에 고친 순서로 `limit` 개. `query` 가 있으면 제목·주소·본문에서 찾는다.
    ///
    /// `kind` 가 `nil` 이면 «전체» 다. **거르는 일을 저장소가 하는 이유**: 화면이 받아서 거르면
    /// «더 있는가» 를 세는 계산이 걸러지기 전 개수를 보게 되어 다음 쪽이 있는데도 없다고 한다.
    func references(matching query: String, kind: ReferenceKind?, limit: Int) throws -> [ReferenceItem]

    /// 목록과 무관하게 한 건만. 고른 항목이 현재 페이지 밖일 수 있어서 필요하다.
    func reference(id: UUID) throws -> ReferenceItem?

    /// 빈 항목을 만들고 상세에서 채운다. 제목도 주소도 아직 없는 상태가 정상이다.
    @discardableResult
    func add(kind: ReferenceKind) throws -> ReferenceItem

    /// 바꿀 필드만 담아 한 번에 쓴다.
    @discardableResult
    func update(id: UUID, _ change: ReferenceChange) throws -> ReferenceItem?

    func delete(id: UUID) throws

    /// 위젯으로 꺼내 둔 쪽지만. 앱을 켤 때 창을 되살리는 데 쓴다.
    func widgetNotes() throws -> [ReferenceItem]
}
