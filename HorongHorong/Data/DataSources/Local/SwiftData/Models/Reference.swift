import Foundation
import SwiftData

/// 참고 자료(Reference) 영속 모델.
///
/// SQLite 테이블: `ZREFERENCE`
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
    /// V8. 모든 창 **뒤**(바탕화면 쪽)에 둘 것인가. `nil`·`false` 면 맨 앞이다.
    var widgetBehind: Bool?

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
        widgetCollapsed: Bool? = nil,
        widgetBehind: Bool? = nil
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
        self.widgetBehind = widgetBehind
    }
}

extension Reference {
    var isRecentlyDeleted: Bool {
        deletedAt != nil
    }

    /// 백필 전이라 갈래가 없으면 옛 규칙(첫 줄이 URL 인가)으로 읽는다.
    /// 저장된 값이 생기기 전까지도 화면이 링크와 쪽지를 갈라 보여 줄 수 있어야 한다.
    var kind: ReferenceKind {
        if let kindRaw, let parsed = ReferenceKind(rawValue: kindRaw) { return parsed }
        return MemoClassifier.looksLikeURL(content) ? .link : .note
    }

    var noteColor: ReferenceNoteColor { ReferenceNoteColor.resolve(colorRaw) }

    /// 위젯 창의 마지막 자리. 둘 중 하나라도 없으면 «한 번도 안 옮김» 이다.
    var widgetPosition: CGPoint? {
        guard let widgetX, let widgetY else { return nil }
        return CGPoint(x: widgetX, y: widgetY)
    }

    /// 위젯 창의 마지막 크기(펼친 상태 기준).
    var widgetSize: CGSize? {
        guard let widgetWidth, let widgetHeight else { return nil }
        return CGSize(width: widgetWidth, height: widgetHeight)
    }
}
