import SwiftUI
import AppKit
import ObjectiveC.runtime

/// SwiftUI 뷰에서 호스팅 NSWindow 를 잡아 NSWindow 단의 styleMask·toolbar 등을 조정한다.
struct WindowAccessor: NSViewRepresentable {
    let onResolved: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            onResolved(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    /// 호스팅 NSWindow 에 한 번 콜백을 흘려준다. 설정 윈도우 트래픽 라이트·툴바 커스터마이즈에 사용.
    func configureHostWindow(_ configure: @escaping (NSWindow) -> Void) -> some View {
        background(WindowAccessor(onResolved: configure))
    }
}

/// 트래픽 라이트(닫기/최소화/확대) 위치에 추가 여백을 준다.
/// macOS 가 리사이즈/메인 전환마다 layoutIfNeeded 로 버튼을 기본 위치로 되돌리므로
/// 첫 적용 시점의 원본 frame 을 기억하고, 그 위치에서 dx/dy 를 더한 절대 좌표로 매번 다시 적용한다.
@MainActor
final class TrafficLightInsetController {
    private weak var window: NSWindow?
    private let dx: CGFloat
    private let dy: CGFloat
    private var originalFrames: [NSWindow.ButtonType: NSRect] = [:]
    private var tasks: [Task<Void, Never>] = []
    private static let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

    init(window: NSWindow, dx: CGFloat, dy: CGFloat) {
        self.window = window
        self.dx = dx
        self.dy = dy
        captureOriginal()
        apply()

        observe(name: NSWindow.didResizeNotification, on: window)
        observe(name: NSWindow.didBecomeMainNotification, on: window)
        observe(name: NSWindow.didChangeOcclusionStateNotification, on: window)
    }

    deinit {
        // Task.cancel 은 nonisolated 라 deinit 에서 호출 가능. 등록된 observer 는 자체 cancellation 으로 해제됨.
        for task in tasks { task.cancel() }
    }

    private func observe(name: Notification.Name, on window: NSWindow) {
        let task = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: name, object: window) {
                self?.apply()
            }
        }
        tasks.append(task)
    }

    private func captureOriginal() {
        guard let window else { return }
        for kind in Self.kinds {
            guard let button = window.standardWindowButton(kind) else { continue }
            originalFrames[kind] = button.frame
        }
    }

    private func apply() {
        guard let window else { return }
        for kind in Self.kinds {
            guard let button = window.standardWindowButton(kind),
                  let original = originalFrames[kind] else { continue }
            button.frame = NSRect(
                x: original.origin.x + dx,
                y: original.origin.y + dy,
                width: original.size.width,
                height: original.size.height
            )
        }
    }
}

nonisolated(unsafe) private var trafficLightControllerKey: UInt8 = 0
nonisolated(unsafe) private var sidebarToggleControllerKey: UInt8 = 0

@MainActor
final class SettingsSidebarToggleController: NSObject {
    private weak var window: NSWindow?
    private let accessory = NSTitlebarAccessoryViewController()
    private let button = NSButton()
    private var action: (() -> Void)?
    private var isSidebarVisible = true

    init(window: NSWindow) {
        self.window = window
        super.init()

        let container = NSView(frame: NSRect(x: 0, y: 0, width: Self.expandedWidth, height: 28))
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        let baseImage = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Toggle sidebar")
        button.image = baseImage?.withSymbolConfiguration(symbolConfig)
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.target = self
        button.action = #selector(toggleSidebar)
        button.toolTip = "사이드바 숨기기"
        button.frame = NSRect(x: Self.expandedWidth - 36, y: 0, width: 32, height: 28)
        container.addSubview(button)

        accessory.view = container
        accessory.layoutAttribute = .leading
        window.addTitlebarAccessoryViewController(accessory)
    }

    func update(isSidebarVisible: Bool, action: @escaping () -> Void) {
        self.isSidebarVisible = isSidebarVisible
        self.action = action
        button.toolTip = isSidebarVisible ? "사이드바 숨기기" : "사이드바 펴기"
        layoutButton()
    }

    private func layoutButton() {
        let width = isSidebarVisible ? Self.expandedWidth : Self.collapsedWidth
        accessory.view.frame.size = NSSize(width: width, height: 28)
        button.frame = NSRect(x: width - 36, y: 0, width: 32, height: 28)
    }

    @objc private func toggleSidebar() {
        action?()
    }

    private static let expandedWidth = SettingsTheme.sidebarWidth - 78
    private static let collapsedWidth: CGFloat = 62
}

extension NSWindow {
    /// 윈도우 수명동안 살아남는 컨트롤러 핸들. associated object 로 보유.
    var horongTrafficLightController: TrafficLightInsetController? {
        get { objc_getAssociatedObject(self, &trafficLightControllerKey) as? TrafficLightInsetController }
        set { objc_setAssociatedObject(self, &trafficLightControllerKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    var horongSidebarToggleController: SettingsSidebarToggleController? {
        get { objc_getAssociatedObject(self, &sidebarToggleControllerKey) as? SettingsSidebarToggleController }
        set { objc_setAssociatedObject(self, &sidebarToggleControllerKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
}
