import Foundation

/// 기록이 어느 섹션에 속하는지. `Memo.sectionRaw` 로 저장된다.
enum MemoSection: String, CaseIterable, Identifiable {
    case quickNote
    case todo
    case reference

    var id: String { rawValue }
}
