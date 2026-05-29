import AppKit
import SwiftUI
import SwiftData

@MainActor
final class QuickMemoPanel {
    private var panel: NSPanel?

    func toggle(modelContext: ModelContext) {
        if let panel = panel, panel.isVisible {
            close()
            return
        }
        show(modelContext: modelContext)
    }

    private func show(modelContext: ModelContext) {
        let panel = QuickMemoWindow(
            contentRect: NSRect(x: 0, y: 0, width: Constants.quickMemoPanelWidth, height: Constants.quickMemoPanelHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
        panel.hasShadow = true
        panel.backgroundColor = .clear

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelFrame = panel.frame
            let x = screenFrame.midX - panelFrame.width / 2
            let y = screenFrame.midY - panelFrame.height / 2 + 100
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        let contentView = QuickMemoView(
            onSave: { [weak self] content, icon in
                let memo = Memo(content: content, icon: icon)
                modelContext.insert(memo)
                try? modelContext.save()
                self?.close()
            },
            onCancel: { [weak self] in
                self?.close()
            }
        )

        panel.contentView = NSHostingView(rootView: contentView)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        panel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }

        self.panel = panel
    }

    func close() {
        guard let panel else { return }
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

private final class QuickMemoWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
