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
    private var isChatting = false

    init(state: CompanionPresentationState) {
        self.state = state
    }

    var isVisible: Bool { panel?.isVisible == true }

    private var currentSize: CGSize {
        isChatting ? Constants.companionChatOverlaySize : Constants.companionOverlaySize
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

        let hostingView = NSHostingView(rootView: CompanionView(state: state))
        hostingView.frame = NSRect(origin: .zero, size: currentSize)
        panel.contentView = hostingView

        panel.orderFrontRegardless()
        self.panel = panel
        applyFrame()
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        isChatting = false
    }

    /// 대화 모드 전환. 창은 위쪽으로만 늘어나므로 캐릭터는 제자리에 남는다.
    func setChatting(_ chatting: Bool) {
        guard isChatting != chatting else { return }
        isChatting = chatting
        guard let panel else { return }

        panel.isChatMode = chatting
        applyFrame()

        if chatting {
            // 텍스트 입력을 받으려면 키 윈도우가 되어야 한다.
            NSApp.activate(ignoringOtherApps: true)
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

    override var canBecomeKey: Bool { isChatMode }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
