import AppKit
import SwiftUI
import SwiftData

@MainActor
final class QuickMemoPresentationState: ObservableObject {
    @Published var savesAsTodayTask: Bool

    init(savesAsTodayTask: Bool) {
        self.savesAsTodayTask = savesAsTodayTask
    }
}

@MainActor
final class QuickMemoPanel {
    private var panel: NSPanel?
    private var presentationState: QuickMemoPresentationState?

    func toggle(modelContext: ModelContext) {
        if let panel = panel, panel.isVisible {
            close()
            return
        }
        show(modelContext: modelContext, savesAsTodayTask: false)
    }

    func showTodayTask(modelContext: ModelContext) {
        if let panel, panel.isVisible {
            presentationState?.savesAsTodayTask = true
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }
        show(modelContext: modelContext, savesAsTodayTask: true)
    }

    private func show(modelContext: ModelContext, savesAsTodayTask: Bool) {
        let presentationState = QuickMemoPresentationState(
            savesAsTodayTask: savesAsTodayTask
        )
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
            presentationState: presentationState,
            onSave: { [weak self] content, icon in
                let memo = Memo(
                    content: content,
                    icon: icon,
                    section: presentationState.savesAsTodayTask ? .todo : .quickNote
                )
                if presentationState.savesAsTodayTask {
                    memo.startDate = Date()
                }
                modelContext.insert(memo)
                do {
                    try modelContext.save()
                    if presentationState.savesAsTodayTask {
                        NotificationManager.shared.cancel(
                            identifier: Constants.todayPlanningReminderNotificationIdentifier
                        )
                    }
                    self?.close()
                    return true
                } catch {
                    modelContext.delete(memo)
                    print("빠른 메모 저장 실패: \(error.localizedDescription)")
                    return false
                }
            },
            onCancel: { [weak self] in
                self?.close()
            }
        )
        .appearanceAccentTint(.popover)

        self.presentationState = presentationState
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
                self?.presentationState = nil
            }
        })
    }
}

private final class QuickMemoWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
