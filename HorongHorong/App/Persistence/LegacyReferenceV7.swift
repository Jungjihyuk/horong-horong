import Foundation
import SwiftData

/// V7 이 **디스크에 남긴** `Reference` 의 모양. 얼려 둔 사본이다.
///
/// ⚠️ **이 파일은 고치지 않는다.**
///
/// `LegacyReference.swift`(V3~V5)·`LegacyReferenceV6.swift` 와 같은 이유다. V8 에서 위젯의
/// 앞뒤 순서를 더하면서 V7 도 살아 있는 타입을 계속 가리켰다면 두 버전의 checksum 이 같아져
/// `Duplicate version checksums detected` 로 저장소가 열리지 않는다.
///
/// 여기 없는 것: `widgetBehind`. V8 에서 더해졌다.
enum LegacyReferenceV7Schema {
    @Model
    final class Reference {
        var id: UUID
        /// 갈래가 생기기 전의 본문 한 덩어리. **지우지 않는다** — 옛 기록의 원본이고,
        /// 백필이 틀렸을 때 되돌릴 근거가 여기밖에 없다.
        var content: String
        var icon: String?
        var createdAt: Date
        var updatedAt: Date
        var isPinned: Bool
        var deletedAt: Date?

        /// V6 에서 더한 구조. 옛 행은 전부 `nil` 이고 앱 시작 때 한 번 백필된다.
        var kindRaw: String?
        var title: String?
        var url: String?
        var body: String?
        var colorRaw: String?
        var isWidget: Bool?
        var widgetX: Double?
        var widgetY: Double?
        /// V7 에서 더한 창 기하. `widgetHeight` 는 **펼쳤을 때의 높이**다 — 접힌 채로 저장하면
        /// 다시 펼 높이를 잃는다.
        var widgetWidth: Double?
        var widgetHeight: Double?
        var widgetCollapsed: Bool?

        init(
            id: UUID = UUID(),
            content: String = "",
            icon: String? = nil,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            isPinned: Bool = false,
            deletedAt: Date? = nil,
            kindRaw: String? = nil,
            title: String? = nil,
            url: String? = nil,
            body: String? = nil,
            colorRaw: String? = nil,
            isWidget: Bool? = nil,
            widgetX: Double? = nil,
            widgetY: Double? = nil,
            widgetWidth: Double? = nil,
            widgetHeight: Double? = nil,
            widgetCollapsed: Bool? = nil
        ) {
            self.id = id
            self.content = content
            self.icon = icon
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.isPinned = isPinned
            self.deletedAt = deletedAt
            self.kindRaw = kindRaw
            self.title = title
            self.url = url
            self.body = body
            self.colorRaw = colorRaw
            self.isWidget = isWidget
            self.widgetX = widgetX
            self.widgetY = widgetY
            self.widgetWidth = widgetWidth
            self.widgetHeight = widgetHeight
            self.widgetCollapsed = widgetCollapsed
        }
    }
}
