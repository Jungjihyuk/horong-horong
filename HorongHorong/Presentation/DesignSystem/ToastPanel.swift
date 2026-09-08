import AppKit
import SwiftUI

@MainActor
final class ToastPanel {
    static let shared = ToastPanel()

    typealias DismissalHandler = @MainActor @Sendable () -> Void

    enum Style {
        case standard
        case timerAlert

        var size: NSSize {
            switch self {
            case .standard:
                return NSSize(width: 360, height: 76)
            case .timerAlert:
                return NSSize(width: 384, height: 86.4)
            }
        }

        /// 구형 macOS의 `.hudWindow` 대신 `.borderless`를 사용한다 —
        /// `.hudWindow`는 2000년대 레거시 HUD 프레임을 강제해 호롱호롱 테마 스타일과 충돌했다.
        var styleMask: NSWindow.StyleMask {
            switch self {
            case .standard, .timerAlert:
                return [.borderless, .nonactivatingPanel]
            }
        }
    }

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private var dismissalHandler: DismissalHandler?

    private init() {}

    func show(icon: String, title: String, subtitle: String, duration: TimeInterval = 4.0) {
        show(
            icon: icon,
            title: title,
            subtitle: subtitle,
            detail: nil,
            duration: duration,
            style: .standard,
            onDismiss: nil
        )
    }

    func showTimerAlert(
        title: String,
        subtitle: String,
        detail: String? = nil,
        duration: TimeInterval = 4.0,
        onDismiss: DismissalHandler? = nil
    ) {
        show(
            icon: "",
            title: title,
            subtitle: subtitle,
            detail: detail,
            duration: duration,
            style: .timerAlert,
            onDismiss: onDismiss
        )
    }

    private func show(
        icon: String,
        title: String,
        subtitle: String,
        detail: String?,
        duration: TimeInterval,
        style: Style,
        onDismiss: DismissalHandler?
    ) {
        dismiss()

        let size = style.size
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: style.styleMask,
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let toastView = ToastView(
            icon: icon,
            title: title,
            subtitle: subtitle,
            detail: detail,
            style: style
        ) { [weak self] in
            self?.dismiss()
        }
        panel.contentView = NSHostingView(rootView: toastView)

        // 백그라운드 앱에서 NSScreen.main은 주 디스플레이만 반환하므로,
        // 사용자가 실제로 보고 있는(마우스가 있는) 화면에 토스트를 띄운다.
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first {
            NSMouseInRect(mouseLocation, $0.frame, false)
        } ?? NSScreen.main
        if let screen = targetScreen {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - size.width - 16
            let y = screenFrame.maxY - size.height - 8
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        self.panel = panel
        dismissalHandler = onDismiss

        NSSound.beep()

        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil

        let dismissalHandler = self.dismissalHandler
        self.dismissalHandler = nil

        guard let panel else {
            dismissalHandler?()
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self, weak panel] in
            MainActor.assumeIsolated {
                panel?.orderOut(nil)
                if self?.panel === panel {
                    self?.panel = nil
                }
                dismissalHandler?()
            }
        })
    }

    func waitUntilDismissed() async {
        while panel != nil {
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return
            }
        }
    }
}

struct ToastView: View {
    let icon: String
    let title: String
    let subtitle: String
    let detail: String?
    let style: ToastPanel.Style
    var onDismiss: () -> Void

    @State private var isDismissHovered = false

    var body: some View {
        switch style {
        case .standard:
            standardBody
        case .timerAlert:
            timerAlertBody
        }
    }

    /// 일반 토스트 (실험실 실행 결과, 클립보드 복사, 설정 알림 등)
    /// 호롱호롱 테마(`PopoverChrome`)의 서피스·보더·폰트를 적용하고,
    /// 아이콘을 정갈한 배지에 담아 현대적인 플로팅 알림 카드로 표현한다.
    private var standardBody: some View {
        HStack(spacing: 12) {
            if !icon.isEmpty {
                ZStack {
                    RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous)
                        .fill(PopoverChrome.surfaceAlt)
                    RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous)
                        .stroke(PopoverChrome.divider, lineWidth: PopoverChrome.borderWidth)
                    Text(icon)
                        .font(.system(size: 18))
                }
                .frame(width: 38, height: 38)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: PopoverChrome.isGamePixel ? .monospaced : .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: PopoverChrome.isGamePixel ? .monospaced : .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(isDismissHovered ? PopoverChrome.ink : PopoverChrome.inkTertiary)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(isDismissHovered ? PopoverChrome.surfaceAlt : Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isDismissHovered = $0 }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 360, height: 76)
        .background {
            ZStack {
                if PopoverChrome.isGamePixel {
                    RoundedRectangle(cornerRadius: PopoverChrome.radius(16), style: .continuous)
                        .fill(PopoverChrome.pixelShadow)
                        .offset(x: 3, y: 3)
                }
                RoundedRectangle(cornerRadius: PopoverChrome.radius(16), style: .continuous)
                    .fill(PopoverChrome.surface)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: PopoverChrome.radius(16), style: .continuous)
                .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
        )
    }

    private var timerAlertBody: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(PopoverChrome.accent)
                .frame(width: 10.8, height: 10.8)
                .padding(.top, 4.8)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15.6, weight: .bold, design: PopoverChrome.isGamePixel ? .monospaced : .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 14.4, weight: .semibold, design: PopoverChrome.isGamePixel ? .monospaced : .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .lineLimit(1)

                if let detail {
                    Text(detail)
                        .font(.system(size: 13.2, weight: .medium, design: PopoverChrome.isGamePixel ? .monospaced : .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 15.6)
        .padding(.trailing, 16.8)
        .padding(.top, 14.4)
        .padding(.bottom, 12)
        .frame(width: 384, height: 86.4, alignment: .topLeading)
        .background {
            ZStack {
                if PopoverChrome.isGamePixel {
                    RoundedRectangle(cornerRadius: PopoverChrome.radius(16.8), style: .continuous)
                        .fill(PopoverChrome.pixelShadow)
                        .offset(x: 3, y: 3)
                }
                RoundedRectangle(cornerRadius: PopoverChrome.radius(16.8), style: .continuous)
                    .fill(PopoverChrome.surface)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: PopoverChrome.radius(16.8), style: .continuous)
                .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
        )
    }
}
