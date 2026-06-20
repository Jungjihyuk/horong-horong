import AppKit
import SwiftUI

@MainActor
final class IdlePromptPanel {
    static let shared = IdlePromptPanel()

    private var panel: NSPanel?
    private var isPresenting: Bool { panel?.isVisible == true }

    private init() {}

    var isShowing: Bool { isPresenting }

    func show(
        appName: String,
        categoryEmoji: String,
        category: String,
        startedAt: Date,
        endedAt: Date,
        onConfirm: @escaping () -> Void,
        onAway: @escaping () -> Void
    ) {
        close(animated: false)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 366),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .utilityWindow
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelFrame = panel.frame
            let x = screenFrame.midX - panelFrame.width / 2
            let y = screenFrame.midY - panelFrame.height / 2 + 80
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        let contentView = IdlePromptView(
            appName: appName,
            categoryEmoji: categoryEmoji,
            category: category,
            startedAt: startedAt,
            endedAt: endedAt,
            onConfirm: { [weak self] in
                onConfirm()
                self?.close(animated: true)
            },
            onAway: { [weak self] in
                onAway()
                self?.close(animated: true)
            }
        )

        panel.contentView = NSHostingView(rootView: contentView)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        panel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }

        self.panel = panel
    }

    func close(animated: Bool = true) {
        guard let panel else { return }
        if !animated {
            panel.orderOut(nil)
            self.panel = nil
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.panel?.orderOut(nil)
                self?.panel = nil
            }
        })
    }
}

private struct IdlePromptView: View {
    let appName: String
    let categoryEmoji: String
    let category: String
    let startedAt: Date
    let endedAt: Date
    let onConfirm: () -> Void
    let onAway: () -> Void

    private var durationText: String {
        let seconds = Int(endedAt.timeIntervalSince(startedAt))
        let minutes = seconds / 60
        let remainderSeconds = seconds % 60
        if minutes == 0 {
            return "\(remainderSeconds)초"
        } else if remainderSeconds == 0 {
            return "\(minutes)분"
        } else {
            return "\(minutes)분 \(remainderSeconds)초"
        }
    }

    private var rangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: startedAt)) ~ \(formatter.string(from: endedAt))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            appBadge
                .frame(maxWidth: .infinity, alignment: .center)
            timeCard
            description
            actions
        }
        .padding(.horizontal, 29)
        .padding(.top, 28)
        .padding(.bottom, 29)
        .frame(width: 500, height: 366)
        .background(PopoverChrome.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(PopoverChrome.border, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(PopoverChrome.accent)
                .frame(width: 9, height: 9)
                .padding(4)
                .background(PopoverChrome.accentSoft.opacity(0.42), in: Circle())

            Text("잠시 자리를 비우셨나요?")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(PopoverChrome.ink)

            Spacer(minLength: 0)
        }
    }

    private var appBadge: some View {
        HStack(spacing: 6) {
            Text("마지막 사용 앱 ·")
            Text("\(categoryEmoji) \(appName)")
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(PopoverChrome.inkSecondary)
        .lineLimit(1)
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(PopoverChrome.surfaceAlt, in: Capsule())
    }

    private var timeCard: some View {
        VStack(spacing: 12) {
            Text(rangeText)
                .font(.system(size: 38, weight: .bold, design: .monospaced))
                .foregroundStyle(PopoverChrome.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text("감지된 시간 \(durationText)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PopoverChrome.inkTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(PopoverChrome.surfaceAlt.opacity(0.78), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(PopoverChrome.border, lineWidth: 1)
        )
    }

    private var description: some View {
        Text("표시된 시간 동안 움직임이 없어 자리 비움으로 감지했어요.")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(PopoverChrome.inkTertiary)
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                onAway()
            } label: {
                Text("자리 비움")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(IdlePromptSecondaryButtonStyle())

            Button {
                onConfirm()
            } label: {
                Text("작업 시간으로 유지")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(IdlePromptPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 2)
    }
}

private struct IdlePromptPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(PopoverChrome.accentInk)
            .padding(.vertical, 13)
            .padding(.horizontal, 18)
            .background(
                PopoverChrome.accent
                    .opacity(configuration.isPressed ? 0.86 : 1),
                in: Capsule()
            )
            .shadow(
                color: PopoverChrome.accent.opacity(configuration.isPressed ? 0.08 : 0.22),
                radius: configuration.isPressed ? 4 : 10,
                x: 0,
                y: configuration.isPressed ? 1 : 4
            )
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct IdlePromptSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(PopoverChrome.inkSecondary)
            .padding(.vertical, 13)
            .padding(.horizontal, 18)
            .background(Color.white.opacity(configuration.isPressed ? 0.44 : 0.55), in: Capsule())
            .shadow(
                color: PopoverChrome.ink.opacity(configuration.isPressed ? 0.03 : 0.08),
                radius: configuration.isPressed ? 2 : 6,
                x: 0,
                y: configuration.isPressed ? 1 : 3
            )
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

#Preview {
    IdlePromptView(
        appName: "카카오톡",
        categoryEmoji: "💬",
        category: "소통",
        startedAt: Date(timeIntervalSince1970: 1_718_000_520),
        endedAt: Date(timeIntervalSince1970: 1_718_000_595),
        onConfirm: {},
        onAway: {}
    )
}
