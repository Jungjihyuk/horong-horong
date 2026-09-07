import Foundation

/// 쪽지의 종이 색.
///
/// 한 색이 **종이(paper)·접힌 모서리(edge)·글씨(ink)** 세 값으로 온다. 배경만 바꾸면 노란 종이
/// 위에 검은 글씨가 얹혀 인쇄물처럼 보인다 — 포스트잇은 글씨도 종이색을 따라간다.
///
/// **여기는 hex 문자열만 둔다.** Domain 은 SwiftUI 를 모르므로 `Color` 변환은
/// Presentation 의 `ReferencePalette` 가 한다.
enum ReferenceNoteColor: String, CaseIterable, Identifiable, Sendable {
    case yellow
    case pink
    case blue
    case green
    case cream

    var id: String { rawValue }

    /// 저장된 값이 깨졌거나 없을 때. 옛 기록은 색이 없다.
    static let fallback = ReferenceNoteColor.yellow

    static func resolve(_ raw: String?) -> ReferenceNoteColor {
        raw.flatMap(ReferenceNoteColor.init(rawValue:)) ?? .fallback
    }

    var paperHex: String {
        switch self {
        case .yellow: return "FDEFB9"
        case .pink: return "FBD9DE"
        case .blue: return "D6E6F5"
        case .green: return "DCEDCE"
        case .cream: return "F6E8D2"
        }
    }

    var edgeHex: String {
        switch self {
        case .yellow: return "F4E09A"
        case .pink: return "F3C3CB"
        case .blue: return "BFD6EC"
        case .green: return "C6E0B3"
        case .cream: return "EBD8BB"
        }
    }

    var inkHex: String {
        switch self {
        case .yellow: return "6B5A22"
        case .pink: return "7A4450"
        case .blue: return "3C5872"
        case .green: return "4A6438"
        case .cream: return "6B563A"
        }
    }
}
