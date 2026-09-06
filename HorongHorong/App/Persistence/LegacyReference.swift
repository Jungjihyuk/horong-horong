import Foundation
import SwiftData

/// V3~V5 가 **디스크에 남긴** `Reference` 의 모양. 얼려 둔 사본이다.
///
/// ⚠️ **이 파일은 고치지 않는다.**
///
/// `LegacyDiary.swift`·`LegacyAchievementGoalRecord.swift` 와 같은 이유다 —
/// `HorongHorongSchemaV3`·`V4`·`V5` 가 살아 있는 `Reference` 를 가리키면, 그 타입에 필드를
/// 더하는 순간 **선언된 세 버전의 모양이 함께 바뀐다.** 새 버전을 만들어도 V5 와 checksum 이
/// 같아져 `Duplicate version checksums detected` 로 저장소 열기가 통째로 거부된다.
///
/// 엔티티가 이어지도록 타입 이름은 `Reference` 로 두고 이름공간만 다르게 둔다.
///
/// 여기 없는 것: `kindRaw`, `title`, `url`, `body`, `colorRaw`, `isWidget`,
/// `widgetX`, `widgetY`. 전부 V6 에서 더해졌다.
enum LegacyReferenceSchema {
    @Model
    final class Reference {
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
}
