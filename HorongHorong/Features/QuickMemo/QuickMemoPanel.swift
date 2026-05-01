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
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Constants.quickMemoPanelWidth, height: 200),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel, .hudWindow],
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

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelFrame = panel.frame
            let x = screenFrame.midX - panelFrame.width / 2
            let y = screenFrame.midY - panelFrame.height / 2 + 100
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        let contentView = QuickMemoView(
            onSave: { [weak self] content in
                let memo = Memo(content: content)
                modelContext.insert(memo)
                try? modelContext.save()
                self?.close()
            },
            onCancel: { [weak self] in
                self?.close()
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
