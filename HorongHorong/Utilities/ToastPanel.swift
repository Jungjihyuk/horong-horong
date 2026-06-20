import AppKit
import SwiftUI

@MainActor
final class ToastPanel {
    static let shared = ToastPanel()

    enum Style {
        case standard
        case timerAlert

        var size: NSSize {
            switch self {
            case .standard:
                return NSSize(width: 320, height: 72)
            case .timerAlert:
                return NSSize(width: 384, height: 86.4)
            }
        }

        var styleMask: NSWindow.StyleMask {
            switch self {
            case .standard:
                return [.nonactivatingPanel, .fullSizeContentView, .hudWindow]
            case .timerAlert:
                return [.borderless, .nonactivatingPanel]
            }
        }
    }

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(icon: String, title: String, subtitle: String, duration: TimeInterval = 4.0) {
        show(icon: icon, title: title, subtitle: subtitle, detail: nil, duration: duration, style: .standard)
    }

    func showTimerAlert(title: String, subtitle: String, detail: String? = nil, duration: TimeInterval = 4.0) {
        show(icon: "", title: title, subtitle: subtitle, detail: detail, duration: duration, style: .timerAlert)
    }

    private func show(
        icon: String,
        title: String,
        subtitle: String,
        detail: String?,
        duration: TimeInterval,
        style: Style
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

        if let screen = NSScreen.main {
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

        NSSound.beep()

        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil

        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel = nil
        })
    }
}

struct ToastView: View {
    let icon: String
    let title: String
    let subtitle: String
    let detail: String?
    let style: ToastPanel.Style
    var onDismiss: () -> Void

    var body: some View {
        switch style {
        case .standard:
            standardBody
        case .timerAlert:
            timerAlertBody
        }
    }

    private var standardBody: some View {
        HStack(spacing: 12) {
            Text(icon)
                .font(.system(size: 28))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 320, height: 72)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
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
                    .font(.system(size: 15.6, weight: .bold))
                    .foregroundStyle(PopoverChrome.ink)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 14.4, weight: .semibold))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .lineLimit(1)

                if let detail {
                    Text(detail)
                        .font(.system(size: 13.2, weight: .medium))
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
        .background(PopoverChrome.surface, in: RoundedRectangle(cornerRadius: 16.8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16.8, style: .continuous)
                .stroke(PopoverChrome.border, lineWidth: 1)
        )
    }
}
