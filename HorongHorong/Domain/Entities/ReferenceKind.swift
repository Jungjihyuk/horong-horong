import Foundation

/// 참고 자료의 갈래.
///
/// **저장되는 사실이다.** 예전에는 첫 줄이 URL 인지 보고 읽을 때마다 추측했다
/// (`MemoClassifier.looksLikeURL`). 그러면 제목을 앞줄에 적는 순간 링크가 아니게 되어,
/// 제목과 주소를 따로 적을 방법이 없었다.
enum ReferenceKind: String, CaseIterable, Identifiable, Sendable {
    case link
    case note

    var id: String { rawValue }

    var title: String {
        switch self {
        case .link: return "링크"
        case .note: return "쪽지"
        }
    }
}
