import Foundation

/// 참고 자료 한 건. 자주 여는 링크이거나 짧은 쪽지다.
///
/// **값 타입이다.** 저장은 `Memo`(`@Model`)가 하지만 그건 Data 계층에 남고,
/// 화면·ViewModel 은 이 타입만 본다. 그래야 저장 기술을 바꿔도 화면이 안 바뀐다.
struct Reference: Identifiable, Equatable, Sendable {
    let id: UUID
    let content: String
    let updatedAt: Date

    /// 목록에 보일 한 줄.
    ///
    /// `Memo.titleLine` 과 같은 규칙이다. 지금은 일부러 각자 두었다 —
    /// Entity 가 `@Model` 을 알면 의존 방향이 뒤집힌다.
    /// Quick Note·Todo 도 옮길 때 `Domain/Policies` 로 합친다. `[확인 필요]`
    var title: String {
        content
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? "제목 없음"
    }

    var isLink: Bool { MemoClassifier.looksLikeURL(content) }
    var linkURL: URL? { MemoClassifier.firstURL(in: content) }
}
