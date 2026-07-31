import AppKit
import SwiftUI

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

    init(state: CompanionPresentationState) {
        self.state = state
    }

    var isVisible: Bool { panel?.isVisible == true }

    private var currentSize: CGSize {
        isExpanded ? Constants.companionExpandedOverlaySize : Constants.companionOverlaySize
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
            guard let self else { return }
            let size = self.currentSize
            let spriteRect = NSRect(
                x: (size.width - Constants.companionSpriteSize.width) / 2,
                y: 0,
                width: Constants.companionSpriteSize.width,
                height: Constants.companionSpriteSize.height
            )
            guard spriteRect.contains(pointInPanel) else { return }
            self.state.onRequestMenu()
        }

        let hostingView = NSHostingView(rootView: CompanionView(state: state))
        // 콘텐츠 크기로 창을 되돌리지 않게 막는다.
        // 그대로 두면 말풍선이 나타날 때마다 창 크기가 이 뷰와 `applyFrame()` 사이에서 튄다.
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: currentSize)
        panel.contentView = hostingView

        panel.orderFrontRegardless()
        self.panel = panel
        applyFrame()
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        isExpanded = false
    }

    /// 창 크기와 입력 수용 여부를 함께 정한다.
    /// 창은 위쪽으로만 늘어나므로 캐릭터는 제자리에 남는다.
    /// 브리핑은 넓게 띄우되 입력은 받지 않아 사용자의 타이핑을 가로채지 않는다.
    func setPresentation(expanded: Bool, acceptsInput: Bool) {
        guard let panel else {
            isExpanded = expanded
            return
        }
        let sizeChanged = isExpanded != expanded
        isExpanded = expanded
        if sizeChanged { applyFrame() }

        guard panel.isChatMode != acceptsInput else { return }
        panel.isChatMode = acceptsInput

        if acceptsInput {
            // 텍스트 입력을 받으려면 키 윈도우가 되어야 한다.
            // 다만 앱 전체를 활성화하지는 않는다. 그러면 쓰던 창이 뒤로 밀린다.
            // nonactivatingPanel 은 앱을 앞으로 끌어내지 않고도 키 윈도우가 될 수 있다.
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.resignKey()
            panel.orderFrontRegardless()
        }
    }

    /// 스프라이트 좌하단 위치를 받아 창 원점으로 변환해 옮긴다.
    /// 창은 스프라이트보다 넓으므로 가로 중앙 정렬 오프셋을 빼준다.
    func move(spriteOrigin: CGPoint) {
        self.spriteOrigin = spriteOrigin
        applyFrame()
    }

    private func applyFrame() {
        guard let panel else { return }
        let size = currentSize
        let dx = (size.width - Constants.companionSpriteSize.width) / 2
        panel.setFrame(
            NSRect(
                x: spriteOrigin.x - dx,
                y: spriteOrigin.y,
                width: size.width,
                height: size.height
            ),
            display: true
        )
        panel.contentView?.frame = NSRect(origin: .zero, size: size)
    }
}

private final class CompanionPanel: NSPanel {
    /// 대화 중일 때만 입력을 받는다. 평소엔 눌러도 호롱호롱이 앞으로 나오지 않는다.
    var isChatMode = false
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
