import AppKit
import SwiftUI

/// 컴패니언이 사는 투명 오버레이 창.
/// 앱을 활성화시키지 않고(`nonactivatingPanel`), 메뉴바보다 아래(`.floating`)에 떠 있으며,
/// 투명한 영역의 클릭은 아래 창으로 통과시켜 작업을 가리지 않는다.
@MainActor
final class CompanionOverlayPanel {
    private var panel: NSPanel?
    private let state: CompanionPresentationState

    init(state: CompanionPresentationState) {
        self.state = state
    }

    var isVisible: Bool { panel?.isVisible == true }

    func show() {
        guard panel == nil else {
            panel?.orderFrontRegardless()
            return
        }

        let panel = CompanionPanel(
            contentRect: NSRect(origin: .zero, size: Constants.companionOverlaySize),
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

        let hostingView = NSHostingView(rootView: CompanionView(state: state))
        hostingView.frame = NSRect(origin: .zero, size: Constants.companionOverlaySize)
        panel.contentView = hostingView

        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// 스프라이트 좌하단 위치를 받아 창 원점으로 변환해 옮긴다.
    /// 창은 스프라이트보다 넓으므로 가로 중앙 정렬 오프셋을 빼준다.
    func move(spriteOrigin: CGPoint) {
        let dx = (Constants.companionOverlaySize.width - Constants.companionSpriteSize.width) / 2
        panel?.setFrameOrigin(NSPoint(x: spriteOrigin.x - dx, y: spriteOrigin.y))
    }
}

private final class CompanionPanel: NSPanel {
    /// 컴패니언을 눌러도 호롱호롱이 앞으로 나오지 않도록 키 윈도우가 되지 않는다.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
