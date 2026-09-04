import Foundation

/// 참고 자료 한 건. 자주 여는 링크이거나 짧은 쪽지다.
///
/// **값 타입이다.** 저장은 `Reference`(`@Model`)가 하지만 그건 Data 계층에 남고,
/// 화면·ViewModel 은 이 타입만 본다. 그래야 저장 기술을 바꿔도 화면이 안 바뀐다.
struct ReferenceItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let content: String
    let updatedAt: Date

    /// 목록에 보일 한 줄. 규칙은 `NoteText` 에 있다 — Quick Note 와 같은 규칙을 쓴다.
    var title: String { NoteText.title(of: content) }

    var isLink: Bool { MemoClassifier.looksLikeURL(content) }
    var linkURL: URL? { MemoClassifier.firstURL(in: content) }
}
