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
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
        panel.hasShadow = true
        panel.backgroundColor = .clear
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("🌙")
                    .font(.title2)
                Text("자리 비우셨나요?")
                    .font(.headline)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(categoryEmoji)
                    Text(appName)
                        .font(.callout)
                        .fontWeight(.medium)
                    Text("(\(category))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(rangeText)
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.semibold)
                Text("입력이 없었던 시간: \(durationText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("이 시간을 작업 시간으로 인정할까요?")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button {
                    onAway()
                } label: {
                    Text("자리 비웠어요")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)

                Button {
                    onConfirm()
                } label: {
                    Text("작업 중이었어요  ⏎")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
