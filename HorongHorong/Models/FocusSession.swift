import Foundation
import SwiftData

@Model
final class FocusSession {
    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var focusMinutes: Int
    var breakMinutes: Int
    var completed: Bool
    // 사용자가 선택한 통계 카테고리 (nil 이면 미지정 — 과거 기록 호환용)
    var category: String?

    init(focusMinutes: Int, breakMinutes: Int, category: String? = nil) {
        self.id = UUID()
        self.startedAt = Date()
        self.focusMinutes = focusMinutes
        self.breakMinutes = breakMinutes
        self.completed = false
        self.category = category
    }
}
