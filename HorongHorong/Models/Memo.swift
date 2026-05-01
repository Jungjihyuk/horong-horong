import Foundation
import SwiftData

@Model
final class Memo {
    var id: UUID
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool

    init(content: String) {
        self.id = UUID()
        self.content = content
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isPinned = false
    }
}
