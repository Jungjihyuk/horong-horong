import Foundation

/// 참고 자료 한 건. 자주 여는 링크이거나 붙여 두는 쪽지다.
///
/// **값 타입이다.** 저장은 `Reference`(`@Model`)가 하지만 그건 Data 계층에 남고,
/// 화면·ViewModel 은 이 타입만 본다. 그래야 저장 기술을 바꿔도 화면이 안 바뀐다.
struct ReferenceItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: ReferenceKind
    let title: String
    /// 링크의 주소. 쪽지에는 없다.
    let url: String?
    /// 쪽지 본문. 링크에는 비어 있다.
    let body: String
    let color: ReferenceNoteColor
    /// 위젯 창으로 꺼내 두었는가.
    let isWidget: Bool
    /// 꺼내 둔 창의 화면 좌표. 한 번도 옮기지 않았으면 `nil` 이고 화면 가운데에 뜬다.
    let widgetPosition: CGPoint?
    /// 꺼내 둔 창의 크기. **접혀 있어도 펼쳤을 때의 높이**를 담는다.
    let widgetSize: CGSize?
    /// 제목만 남기고 접어 두었는가.
    let isWidgetCollapsed: Bool
    /// 모든 창 **뒤**(바탕화면 쪽)에 두는가. `false` 면 맨 앞에 떠 있다.
    let isWidgetBehind: Bool
    let updatedAt: Date

    init(
        id: UUID,
        kind: ReferenceKind,
        title: String,
        url: String? = nil,
        body: String = "",
        color: ReferenceNoteColor = .fallback,
        isWidget: Bool = false,
        widgetPosition: CGPoint? = nil,
        widgetSize: CGSize? = nil,
        isWidgetCollapsed: Bool = false,
        isWidgetBehind: Bool = false,
        updatedAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.url = url
        self.body = body
        self.color = color
        self.isWidget = isWidget
        self.widgetPosition = widgetPosition
        self.widgetSize = widgetSize
        self.isWidgetCollapsed = isWidgetCollapsed
        self.isWidgetBehind = isWidgetBehind
        self.updatedAt = updatedAt
    }

    /// 목록과 상세가 함께 쓰는 표시용 제목. 비어 있으면 갈래에 맞는 자리표시를 준다.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return trimmed }
        return kind == .link ? "제목 없음" : "쪽지"
    }

    /// 열 수 있는 주소. `https://` 를 빠뜨린 입력도 살려 준다.
    var linkURL: URL? {
        guard kind == .link, let url else { return nil }
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let parsed = URL(string: trimmed), parsed.scheme != nil { return parsed }
        return URL(string: "https://\(trimmed)")
    }

    /// 카드에 보일 도메인. `www.` 는 떼어 낸다 — 아홉 카드가 전부 www 로 시작하면 구별이 안 된다.
    var host: String? {
        guard let host = linkURL?.host() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// 참고 자료에서 **바꿀 것만** 담는 묶음.
///
/// 필드마다 setter 를 두면 프로토콜이 여덟 개가 되고, 화면이 두 필드를 고칠 때 저장이 두 번 나간다.
/// `nil` 은 «건드리지 않음» 이다.
struct ReferenceChange: Equatable, Sendable {
    var title: String?
    var url: String?
    var body: String?
    var color: ReferenceNoteColor?
    var isWidget: Bool?
    var widgetPosition: CGPoint?
    var widgetSize: CGSize?
    var isWidgetCollapsed: Bool?
    var isWidgetBehind: Bool?

    init(
        title: String? = nil,
        url: String? = nil,
        body: String? = nil,
        color: ReferenceNoteColor? = nil,
        isWidget: Bool? = nil,
        widgetPosition: CGPoint? = nil,
        widgetSize: CGSize? = nil,
        isWidgetCollapsed: Bool? = nil,
        isWidgetBehind: Bool? = nil
    ) {
        self.title = title
        self.url = url
        self.body = body
        self.color = color
        self.isWidget = isWidget
        self.widgetPosition = widgetPosition
        self.widgetSize = widgetSize
        self.isWidgetCollapsed = isWidgetCollapsed
        self.isWidgetBehind = isWidgetBehind
    }
}
