import Foundation
import SwiftData

/// 빠른 메모(Quick Note) 영속 모델.
///
/// SQLite 테이블: `ZQUICKNOTE`
@Model
final class QuickNote {
    var id: UUID
    var content: String
    var icon: String?
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        content: String = "",
        icon: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isPinned: Bool = false,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.content = content
        self.icon = icon
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.deletedAt = deletedAt
    }
}

extension QuickNote {
    var isRecentlyDeleted: Bool {
        deletedAt != nil
    }
}
