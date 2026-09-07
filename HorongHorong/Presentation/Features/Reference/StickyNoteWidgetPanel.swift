import AppKit
import SwiftUI

/// 화면 위에 떠 있는 쪽지 한 장.
///
/// `QuickMemoPanel` 의 설정을 그대로 본떴다 — borderless `NSPanel` 은 그냥 두면 키 입력을
/// 못 받아 글자를 쓸 수 없다. `canBecomeKey` 를 여는 것이 이 클래스의 존재 이유다.
final class StickyNoteWindow: NSPanel {
    /// borderless 패널의 기본값은 `false` 다. 열지 않으면 위젯에서 타이핑이 안 된다.
    override var canBecomeKey: Bool { true }
    /// 주 창은 되지 않는다. 쪽지가 앱의 «본 창» 행세를 하면 메뉴가 따라붙는다.
    override var canBecomeMain: Bool { false }
}

/// 떠 있는 쪽지 창들의 주인.
///
/// **기존 보조 창은 전부 단일 인스턴스**(`var panel: NSPanel?`)지만 쪽지는 여러 장이 동시에
/// 떠야 한다. 그래서 id 로 키를 잡는다.
@MainActor
final class StickyNoteWidgetPresenter {
    private var windows: [UUID: StickyNoteWindow] = [:]
    private var moveObservers: [UUID: NSObjectProtocol] = [:]
    /// 창을 끌 때마다 저장하면 한 번 옮기는 데 수백 번 쓰기가 된다. 멈춘 뒤 한 번만 남긴다.
    private var moveTasks: [UUID: Task<Void, Never>] = [:]
    private var resizeObservers: [UUID: NSObjectProtocol] = [:]
    private var resizeTasks: [UUID: Task<Void, Never>] = [:]

    private let repository: ReferenceRepository

    private static let defaultSize = CGSize(width: 224, height: 210)
    /// 접었을 때 남는 높이. 제목 줄 하나가 딱 들어간다.
    static let collapsedHeight: CGFloat = 34
    private static let minimumSize = CGSize(width: 170, height: 120)

    /// 모든 창 위. 브라우저를 보면서도 쪽지가 보인다.
    private static let frontLevel = NSWindow.Level.floating
    /// 모든 창 뒤 — 바탕화면 아이콘 바로 위. 방해하지 않지만 창을 치우면 거기 있다.
    private static let backLevel = NSWindow.Level(
        rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
    )
    private static let maximumSize = CGSize(width: 620, height: 720)

    /// 저장소가 바뀌었다는 알림. «위젯으로 꺼내기» 를 누른 것도 결국 저장이므로,
    /// 화면이 AppKit 을 직접 부르지 않고 이 한 곳에서 창을 열고 닫는다.
    private var changeObserver: NSObjectProtocol?

    init(repository: ReferenceRepository) {
        self.repository = repository
        changeObserver = NotificationCenter.default.addObserver(
            forName: ReferenceChangeBroadcast.name,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let id = ReferenceChangeBroadcast.id(from: notification) else { return }
            MainActor.assumeIsolated { self?.syncWindow(for: id) }
        }
    }

    /// 저장된 «위젯으로 꺼냄» 상태에 창을 맞춘다.
    private func syncWindow(for id: UUID) {
        guard let item = try? repository.reference(id: id) else {
            close(id)
            return
        }
        guard item.isWidget else {
            close(id)
            return
        }
        if let window = windows[id] {
            // 이미 떠 있으면 저장된 앞뒤 상태만 맞춘다.
            window.level = Self.level(behind: item.isWidgetBehind)
        } else {
            open(item)
        }
    }

    /// 앱을 켤 때 꺼내 두었던 쪽지를 되살린다.
    func restoreAll() {
        guard let notes = try? repository.widgetNotes() else { return }
        for note in notes { open(note) }
    }

    func open(_ item: ReferenceItem) {
        guard item.kind == .note else { return }
        if let existing = windows[item.id] {
            existing.orderFrontRegardless()
            return
        }

        let expandedSize = Self.clamp(item.widgetSize ?? Self.defaultSize)
        let window = StickyNoteWindow(
            contentRect: NSRect(origin: .zero, size: expandedSize),
            // `.resizable` 이 있어야 테두리를 끌어 크기를 바꿀 수 있다. borderless 라 눈에 보이는
            // 손잡이는 없지만 가장자리가 그대로 손잡이 노릇을 한다.
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isFloatingPanel = true
        window.level = Self.level(behind: item.isWidgetBehind)
        // **`NSPanel` 의 기본값이 `true` 다.** 그대로 두면 브라우저 등 다른 앱을 누르는 순간
        // 쪽지가 사라진다 — 창 위에 붙여 두는 것이 이 위젯의 존재 이유이므로 꺼야 한다.
        window.hidesOnDeactivate = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        // 포스트잇은 아무 데나 잡아 끌 수 있어야 한다. 제목 표시줄이 없으니 배경이 손잡이다.
        window.isMovableByWindowBackground = true
        window.animationBehavior = .utilityWindow
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false

        window.contentMinSize = Self.minimumSize
        window.contentMaxSize = Self.maximumSize
        window.contentView = NSHostingView(
            rootView: StickyNoteWidgetView(
                item: item,
                repository: repository,
                onClose: { [weak self] in self?.dismiss(item.id) },
                onToggleCollapse: { [weak self] in self?.toggleCollapse(item.id) },
                onToggleDepth: { [weak self] in self?.toggleDepth(item.id) }
            )
        )
        window.setFrameOrigin(origin(for: item, size: expandedSize))
        applyCollapse(item.isWidgetCollapsed, to: window, expandedHeight: expandedSize.height)
        window.orderFrontRegardless()

        windows[item.id] = window
        observeGeometry(of: window, id: item.id)
    }

    /// 창만 닫는다. 저장된 «위젯으로 꺼냄» 상태는 그대로다(앱 종료 시 등).
    func close(_ id: UUID) {
        for store in [\StickyNoteWidgetPresenter.moveObservers, \.resizeObservers] {
            if let observer = self[keyPath: store].removeValue(forKey: id) {
                NotificationCenter.default.removeObserver(observer)
            }
        }
        moveTasks.removeValue(forKey: id)?.cancel()
        resizeTasks.removeValue(forKey: id)?.cancel()
        windows.removeValue(forKey: id)?.orderOut(nil)
    }

    func closeAll() {
        for id in windows.keys { close(id) }
    }

    // MARK: - 내부

    /// 위젯에서 ✕ 를 눌렀을 때. 창을 닫고 «내려놓음» 을 저장한다.
    private func dismiss(_ id: UUID) {
        close(id)
        try? repository.update(id: id, ReferenceChange(isWidget: false))
        ReferenceChangeBroadcast.post(id: id)
    }

    /// 맨 앞과 맨 뒤를 오간다.
    ///
    /// **창을 다시 만들지 않고 레벨만 바꾼다** — 다시 만들면 편집 중이던 글자가 날아간다.
    private func toggleDepth(_ id: UUID) {
        guard let window = windows[id], let item = try? repository.reference(id: id) else { return }
        let behind = !item.isWidgetBehind
        window.level = Self.level(behind: behind)
        // 맨 뒤로 보낼 때는 앞으로 끌어올리지 않는다. 맨 앞으로 올 때만 올린다.
        if !behind { window.orderFrontRegardless() }

        try? repository.update(id: id, ReferenceChange(isWidgetBehind: behind))
        ReferenceChangeBroadcast.post(id: id)
    }

    private static func level(behind: Bool) -> NSWindow.Level {
        behind ? backLevel : frontLevel
    }

    /// 제목만 남기고 접거나 다시 편다.
    ///
    /// **창 높이를 직접 줄인다.** SwiftUI 안에서 내용만 감추면 빈 종이가 그대로 남아
    /// 화면을 가리는 넓이는 하나도 줄지 않는다.
    private func toggleCollapse(_ id: UUID) {
        guard let window = windows[id], let item = try? repository.reference(id: id) else { return }
        let collapsed = !item.isWidgetCollapsed
        // 접기 직전의 높이가 다시 펼 높이다. 접힌 높이를 저장하면 펼 곳을 잃는다.
        let expandedHeight = collapsed ? window.frame.height : (item.widgetSize?.height ?? Self.defaultSize.height)

        applyCollapse(collapsed, to: window, expandedHeight: expandedHeight)
        try? repository.update(
            id: id,
            ReferenceChange(
                widgetSize: CGSize(width: window.frame.width, height: expandedHeight),
                isWidgetCollapsed: collapsed
            )
        )
        ReferenceChangeBroadcast.post(id: id)
    }

    /// 접힘 상태를 창에 반영한다. **위쪽 모서리를 붙잡아** 아래로만 줄인다 —
    /// macOS 좌표는 아래가 원점이라 그냥 높이를 줄이면 창이 제자리에서 위로 솟는다.
    private func applyCollapse(_ collapsed: Bool, to window: StickyNoteWindow, expandedHeight: CGFloat) {
        let height = collapsed ? Self.collapsedHeight : expandedHeight
        var frame = window.frame
        frame.origin.y += frame.height - height
        frame.size.height = height
        window.setFrame(frame, display: true, animate: false)

        // 접힌 동안에는 세로로 끌 수 없게 막는다. 안 막으면 접힌 창을 늘려 빈 종이를 만든다.
        window.contentMinSize = CGSize(width: Self.minimumSize.width, height: collapsed ? height : Self.minimumSize.height)
        window.contentMaxSize = CGSize(width: Self.maximumSize.width, height: collapsed ? height : Self.maximumSize.height)
    }

    private func origin(for item: ReferenceItem, size: CGSize) -> NSPoint {
        if let saved = item.widgetPosition {
            return NSPoint(x: saved.x, y: saved.y)
        }
        // 한 번도 안 옮긴 쪽지는 화면 오른쪽 위에 둔다. 가운데는 하던 일을 가린다.
        guard let screen = NSScreen.main?.visibleFrame else { return NSPoint(x: 200, y: 200) }
        return NSPoint(x: screen.maxX - size.width - 40, y: screen.maxY - size.height - 40)
    }

    private static func clamp(_ size: CGSize) -> CGSize {
        CGSize(
            width: min(max(size.width, minimumSize.width), maximumSize.width),
            height: min(max(size.height, minimumSize.height), maximumSize.height)
        )
    }

    private func observeGeometry(of window: StickyNoteWindow, id: UUID) {
        moveObservers[id] = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            guard let origin = window?.frame.origin else { return }
            MainActor.assumeIsolated { self?.schedulePositionSave(id: id, origin: origin) }
        }

        resizeObservers[id] = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            guard let window else { return }
            let size = window.frame.size
            MainActor.assumeIsolated { self?.scheduleSizeSave(id: id, size: size) }
        }
    }

    private func schedulePositionSave(id: UUID, origin: NSPoint) {
        moveTasks[id]?.cancel()
        moveTasks[id] = debounced { [weak self] in
            // 위치만 바꾸므로 목록 순서(`updatedAt`)는 건드리지 않는다.
            try? self?.repository.update(
                id: id,
                ReferenceChange(widgetPosition: CGPoint(x: origin.x, y: origin.y))
            )
        }
    }

    private func scheduleSizeSave(id: UUID, size: CGSize) {
        resizeTasks[id]?.cancel()
        resizeTasks[id] = debounced { [weak self] in
            guard let self else { return }
            // 접는 것도 리사이즈 알림을 부른다. 접힌 높이를 «펼친 높이» 로 적으면
            // 다시 폈을 때 제목 줄만 남는다.
            guard (try? self.repository.reference(id: id))?.isWidgetCollapsed == false else { return }
            try? self.repository.update(id: id, ReferenceChange(widgetSize: size))
        }
    }

    /// 끄는 동안 매 프레임 저장하지 않도록 멈춘 뒤 한 번만 남긴다.
    private func debounced(_ work: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            work()
        }
    }
}
