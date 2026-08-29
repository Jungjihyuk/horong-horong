import AppKit
import SwiftUI
import OSLog

enum CompanionOverlayMousePolicy {
    static func shouldIgnoreMouseEvents(
        at point: CGPoint,
        spriteRect: CGRect,
        contentRect: CGRect,
        isMenuVisible: Bool
    ) -> Bool {
        // 메뉴를 연 직후에는 커서가 캐릭터와 카드 사이의 투명한 간격을 지난다.
        // 이때 창 전체를 클릭 통과 상태로 바꾸면 메뉴 버튼까지 입력을 잃는다.
        guard !isMenuVisible else { return false }
        return !spriteRect.contains(point) && !contentRect.contains(point)
    }
}

/// 컴패니언이 사는 투명 오버레이 창.
/// 평소에는 앱을 활성화시키지 않고 메뉴바보다 아래(`.floating`)에 떠 있으며,
/// 투명한 영역의 클릭은 아래 창으로 통과시켜 작업을 가리지 않는다.
/// 대화 모드에서는 입력을 받아야 하므로 그때만 키 윈도우가 된다.
@MainActor
final class CompanionOverlayPanel {
    private var panel: CompanionPanel?
    private let state: CompanionPresentationState
    private var spriteOrigin: CGPoint = .zero
    private var isExpanded = false
    /// 뷰가 알려준 카드 자리. 창 왼쪽 위가 원점이라 쓸 때 아래 기준으로 뒤집는다.
    private var contentFrame: CGRect = .zero
    private var mouseMonitors: [Any] = []
    private var clickThroughTimer: Timer?
    private static let log = Logger(subsystem: "com.horonghorong.app", category: "CompanionHit")
    /// 말풍선을 캐릭터 아래에 그리는 중인지. 화면 위쪽에 붙어 자리가 없을 때 뒤집는다.
    private var isCardBelow = false

    init(state: CompanionPresentationState) {
        self.state = state
    }

    var isVisible: Bool { panel?.isVisible == true }

    private var currentSize: CGSize {
        isExpanded ? Constants.companionExpandedOverlaySize : Constants.companionOverlaySize
    }

    /// 캐릭터가 실제로 그려지는 자리.
    /// 말풍선이 위로 뜨면 캐릭터는 창 아래쪽에, 아래로 뒤집히면 창 위쪽에 있다.
    private var spriteRect: CGRect {
        let size = currentSize
        let spriteSize = Constants.companionSpriteSize
        return CGRect(
            x: (size.width - spriteSize.width) / 2,
            y: isCardBelow ? size.height - spriteSize.height : 0,
            width: spriteSize.width,
            height: spriteSize.height
        )
    }

    /// 카드(메뉴·대화·말풍선)가 화면에 있는 상태인지. `CompanionView.card` 의 분기와 같은 조건.
    private var isCardVisible: Bool {
        state.isMenuVisible || state.isChatting || state.bubble != nil
    }

    /// 말풍선·대화창·메뉴가 그려진 자리를 창 좌표(아래 기준)로 바꾼 것.
    private var contentRect: CGRect {
        guard !contentFrame.isEmpty else { return .zero }
        return CGRect(
            x: contentFrame.minX,
            y: currentSize.height - contentFrame.maxY,
            width: contentFrame.width,
            height: contentFrame.height
        )
    }

    /// 설정에서 말풍선 크기를 바꿨을 때 창을 다시 맞춘다.
    func refreshSize() {
        guard panel != nil, isExpanded else { return }
        applyFrame()
    }

    func show() {
        guard panel == nil else {
            panel?.orderFrontRegardless()
            return
        }

        let panel = CompanionPanel(
            contentRect: NSRect(origin: .zero, size: currentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary,
        ]
        panel.onCancel = { [weak self] in
            self?.state.onCloseChat()
        }
        // 오른쪽 클릭은 뷰가 아니라 창에서 받는다.
        // 캐릭터 위(하단 중앙 스프라이트 영역)를 눌렀을 때만 메뉴를 연다.
        panel.onRightClick = { [weak self] pointInPanel in
            guard let self, self.spriteRect.contains(pointInPanel) else { return }
            self.state.onRequestMenu()
        }

        let hostingView = NSHostingView(
            rootView: CompanionView(state: state) { [weak self] frame in
                guard let self, self.contentFrame != frame else { return }
                // 카드가 떠 있는 동안 들어오는 0 크기 보고는, 사라지는 옛 레이아웃이 뒤늦게
                // 남기는 값이다(작은 창 기준 좌표로 도착한다). 그대로 받으면 카드 자리가
                // 지워져 카드 위 클릭이 아래 창으로 통과한다 — 입력란도 닫기 버튼도 죽는다.
                if frame.isEmpty, self.isCardVisible { return }
                self.contentFrame = frame
                Self.log.notice("contentFrame=\(NSStringFromRect(frame), privacy: .public) winSize=\(NSStringFromSize(self.currentSize), privacy: .public) expanded=\(self.isExpanded) chatting=\(self.state.isChatting)")
                // 카드 높이를 알아야 위/아래를 정할 수 있다. 창이 열릴 때는 아직 재기 전이다.
                self.applyFrame()
            }
        )
        // 콘텐츠 크기로 창을 되돌리지 않게 막는다.
        // 그대로 두면 말풍선이 나타날 때마다 창 크기가 이 뷰와 `applyFrame()` 사이에서 튄다.
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: currentSize)
        panel.contentView = hostingView

        panel.orderFrontRegardless()
        self.panel = panel
        applyFrame()
        startMouseTracking()
    }

    func hide() {
        stopMouseTracking()
        clickThroughTimer?.invalidate()
        clickThroughTimer = nil
        panel?.orderOut(nil)
        panel = nil
        isExpanded = false
        contentFrame = .zero
    }

    /// 창 크기와 입력 수용 여부를 함께 정한다.
    /// 창은 캐릭터를 기준으로 늘어나므로(위, 자리가 없으면 아래) 캐릭터는 제자리에 남는다.
    /// 브리핑은 넓게 띄우되 입력은 받지 않아 사용자의 타이핑을 가로채지 않는다.
    func setPresentation(expanded: Bool, acceptsInput: Bool) {
        guard let panel else {
            isExpanded = expanded
            return
        }
        // 창 크기 조건은 CompanionView.overlaySize 와 같아야 한다. 어긋나면 뷰는 큰 레이아웃으로
        // 그리는데 창만 작아져 카드가 창 밖으로 나가고, contentRect 가 어긋나 카드 영역의
        // 클릭이 통과된다(커서도 안 뜨고 닫기 버튼도 안 눌린다).
        let expanded = expanded || state.isChatting
        Self.log.notice("setPresentation expanded=\(expanded) acceptsInput=\(acceptsInput || self.state.isChatting) chatting=\(self.state.isChatting) menu=\(self.state.isMenuVisible)")
        let sizeChanged = isExpanded != expanded
        isExpanded = expanded
        if sizeChanged { applyFrame() }

        // 말풍선·메뉴는 창 크기만 바꾸면 된다. 그때 입력까지 끄면 대화가 열려 있는데 입력만
        // 죽는다. 되살리는 경로가 beginChat 뿐인데 그쪽은 대화 중이면 guard 에 막혀 교착된다.
        let acceptsInput = acceptsInput || state.isChatting

        guard panel.isChatMode != acceptsInput else { return }
        panel.isChatMode = acceptsInput

        if acceptsInput {
            // 텍스트 입력을 받으려면 키 윈도우가 되어야 한다.
            // 다만 앱 전체를 활성화하지는 않는다. 그러면 쓰던 창이 뒤로 밀린다.
            // nonactivatingPanel 은 앱을 앞으로 끌어내지 않고도 키 윈도우가 될 수 있다.
            panel.makeKeyAndOrderFront(nil)
        } else {
            // key 는 직접 내려놓을 수 없다. resignKey() 는 «너 key 아니게 됐다» 를 알리는
            // override point 라, 창만 정리되고 NSApp 의 key 등록은 그대로 남는다.
            // 내렸다 다시 올리면 AppKit 이 다음 key 를 정상적으로 고른다.
            if panel.isKeyWindow { panel.orderOut(nil) }
            panel.orderFrontRegardless()
        }
    }

    /// 스프라이트 좌하단 위치를 받아 창 원점으로 변환해 옮긴다.
    /// 창은 스프라이트보다 넓으므로 가로 중앙 정렬 오프셋을 빼준다.
    func move(spriteOrigin: CGPoint) {
        self.spriteOrigin = spriteOrigin
        applyFrame()
    }

    private func applyFrame(forcingCardPlacement: Bool = false) {
        guard let panel else { return }
        let size = currentSize
        let dx = (size.width - Constants.companionSpriteSize.width) / 2
        updateCardPlacement(force: forcingCardPlacement)
        // 뒤집혔을 때는 캐릭터가 창 위쪽에 있으므로 그만큼 창을 내려 잡는다.
        let y = isCardBelow
            ? spriteOrigin.y + Constants.companionSpriteSize.height - size.height
            : spriteOrigin.y
        panel.setFrame(
            NSRect(
                x: spriteOrigin.x - dx,
                y: y,
                width: size.width,
                height: size.height
            ),
            display: true
        )
        panel.contentView?.frame = NSRect(origin: .zero, size: size)
        // 캐릭터가 걸어다니면 커서가 가만히 있어도 창 밑의 그림이 바뀐다.
        updateClickThrough()
    }

    /// 말풍선은 늘 캐릭터 위에 둔다.
    /// 화면 위쪽에 붙어 정말 자리가 없을 때만, 그리고 아래에 자리가 있을 때만 내린다.
    ///
    /// 창 높이가 아니라 실제로 그려진 카드 높이로 잰다.
    /// 창은 말풍선이 커질 때를 대비해 넉넉히 잡아두므로, 창 높이로 재면
    /// 화면 위에 아직 여유가 많은데도 화면 중턱에서 미리 뒤집힌다.
    private func updateCardPlacement(force: Bool) {
        // 끌고 가는 도중에 뒤집으면 SwiftUI 가 캐릭터 뷰를 새로 만들면서
        // 잡고 있던 드래그 제스처가 끊긴다. 버튼을 뗄 때 다시 잡는다.
        guard force || NSEvent.pressedMouseButtons == 0 else { return }

        let cardHeight = contentFrame.height
        let spriteTop = spriteOrigin.y + Constants.companionSpriteSize.height
        var cardBelow = false
        if cardHeight > 0, let visible = screenContainingSprite()?.visibleFrame {
            let fitsAbove = spriteTop + Self.cardSpacing + cardHeight <= visible.maxY
            let fitsBelow = spriteOrigin.y - Self.cardSpacing - cardHeight >= visible.minY
            cardBelow = !fitsAbove && fitsBelow
        }

        guard isCardBelow != cardBelow else { return }
        isCardBelow = cardBelow
        state.isCardBelow = cardBelow
    }

    /// 캐릭터와 말풍선 사이 간격. 뷰의 `VStack` 간격과 같아야 자리 계산이 맞는다.
    private static let cardSpacing: CGFloat = 6

    /// 캐릭터가 올라가 있는 화면. 여러 대를 쓰면 화면마다 위쪽 한계가 다르다.
    private func screenContainingSprite() -> NSScreen? {
        let point = CGPoint(
            x: spriteOrigin.x + Constants.companionSpriteSize.width / 2,
            y: spriteOrigin.y + Constants.companionSpriteSize.height / 2
        )
        return NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    /// 캐릭터와 말풍선이 그려진 자리에서만 창이 클릭을 받게 한다.
    ///
    /// 창은 캐릭터보다 훨씬 넓어서(말풍선이 뜰 자리를 미리 잡아둔다) 나머지는 늘 투명하다.
    /// 그런데 macOS 는 투명한 픽셀이라고 클릭을 통과시켜 주지 않고, 뷰에서 판정 영역을
    /// 좁혀도(`contentShape`) 창이 이미 이벤트를 삼킨 뒤라 아래 앱까지 닿지 않는다.
    /// 그래서 커서가 캐릭터 밖에 있는 동안에는 창 자체를 이벤트에서 비켜 둔다.
    private func updateClickThrough() {
        guard let panel else { return }
        // 드래그 도중에 창을 비키면 끌던 캐릭터를 놓치므로 버튼을 뗄 때까지 미룬다.
        guard NSEvent.pressedMouseButtons == 0 else { return }
        let point = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        let shouldIgnoreMouseEvents = CompanionOverlayMousePolicy.shouldIgnoreMouseEvents(
            at: point,
            spriteRect: spriteRect,
            contentRect: contentRect,
            isMenuVisible: state.isMenuVisible
        )
        // 값이 같아도 대입하면 그때마다 윈도우 서버까지 다녀와 커서가 끊긴다.
        guard panel.ignoresMouseEvents != shouldIgnoreMouseEvents else { return }
        panel.ignoresMouseEvents = shouldIgnoreMouseEvents
        Self.log.notice("clickThrough=\(shouldIgnoreMouseEvents) point=\(NSStringFromPoint(point), privacy: .public) sprite=\(NSStringFromRect(self.spriteRect), privacy: .public) content=\(NSStringFromRect(self.contentRect), privacy: .public) winSize=\(NSStringFromSize(self.currentSize), privacy: .public) chatting=\(self.state.isChatting) menu=\(self.state.isMenuVisible)")
    }

    /// 커서가 캐릭터 안팎을 드나드는지 짧은 주기로 직접 확인한다.
    ///
    /// 마우스 이벤트에만 기대면 놓치는 자리가 있다. 대화 중에는 창이 키 윈도우가 되고
    /// 캐릭터도 걷지 않아 `applyFrame` 이 멈추는데, 이때 이동 이벤트까지 오지 않으면
    /// 통과 상태가 굳어 대화창의 닫기 버튼이 눌리지 않는다.
    /// 계산은 1µs 도 안 되고 값이 바뀔 때만 창에 쓰므로 주기적으로 봐도 부담이 없다.
    private func startMouseTracking() {
        guard mouseMonitors.isEmpty else { return }
        clickThroughTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateClickThrough() }
        }
        // 버튼을 뗀 순간에는 드래그 중 미뤄둔 말풍선 방향을 바로 잡아준다.
        let mask: NSEvent.EventTypeMask = [.leftMouseUp, .rightMouseUp]
        let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyFrame(forcingCardPlacement: true) }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.applyFrame(forcingCardPlacement: true) }
            return event
        }
        mouseMonitors = [global, local].compactMap { $0 }
    }

    private func stopMouseTracking() {
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors.removeAll()
    }
}

private final class CompanionPanel: NSPanel {
    /// 대화 중일 때만 입력을 받는다. 평소엔 눌러도 호롱호롱이 앞으로 나오지 않는다.
    var isChatMode = false

    /// 창은 캐릭터보다 훨씬 크고 위쪽 대부분이 말풍선용 빈자리다.
    /// 기본 제약을 두면 이 빈자리가 메뉴바에 먼저 걸려 캐릭터가 화면 위까지 못 올라간다.
    /// 위치는 활동 영역에 맞춰 이미 계산해 두므로 요청한 자리를 그대로 쓴다.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
    var onCancel: (() -> Void)?
    var onRightClick: ((NSPoint) -> Void)?

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(convertPoint(fromScreen: NSEvent.mouseLocation))
    }

    override var canBecomeKey: Bool { isChatMode }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
