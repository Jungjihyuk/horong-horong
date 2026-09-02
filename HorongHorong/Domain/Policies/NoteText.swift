import Foundation

/// 자유 서식 본문에서 목록에 보일 조각을 뽑는다.
///
/// **한 곳에 모은 이유**: 같은 규칙이 `Memo.titleLine`(Data)과 `Reference.title`(Domain)에
/// 따로 있었다. 참고 자료를 옮길 때는 «Entity 가 `@Model` 을 알면 의존 방향이 뒤집힌다» 는
/// 이유로 일부러 각자 두고 `[확인 필요]` 를 남겼는데, Quick Note 가 세 번째 사본이 될 참이라
/// 지금 합친다(CLAUDE.md §3 «두 개 이상일 때 분리»).
///
/// 순수 함수만 둔다 — 저장도 시간도 보지 않는다.
enum NoteText {
    /// 비어 있지 않은 첫 줄. 전부 비었으면 «제목 없음».
    static func title(of content: String) -> String {
        lines(of: content).first ?? "제목 없음"
    }

    /// 첫 줄을 뺀 나머지를 한 줄로 이은 것. 첫 줄뿐이면 `nil`.
    static func rest(of content: String) -> String? {
        let lines = lines(of: content)
        guard lines.count > 1 else { return nil }
        return lines.dropFirst().joined(separator: " ")
    }

    private static func lines(of content: String) -> [String] {
        content
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
