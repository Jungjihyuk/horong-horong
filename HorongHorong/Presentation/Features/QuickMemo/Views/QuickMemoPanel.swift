import AppKit
import SwiftUI

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

    func toggle(todos: TodoRepository, quickNotes: QuickNoteRepository) {
        if let panel = panel, panel.isVisible {
            close()
            return
        }
        show(todos: todos, quickNotes: quickNotes, savesAsTodayTask: false)
    }

    func showTodayTask(todos: TodoRepository, quickNotes: QuickNoteRepository) {
        if let panel, panel.isVisible {
            presentationState?.savesAsTodayTask = true
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }
        show(todos: todos, quickNotes: quickNotes, savesAsTodayTask: true)
    }

    private func show(todos: TodoRepository, quickNotes: QuickNoteRepository, savesAsTodayTask: Bool) {
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
                do {
                    // 「오늘 할 일」이면 지금 시각으로 시작하는 할 일, 아니면 그냥 기록.
                    // 오늘 계획 알림을 끄는 것도 저장소가 함께 한다.
                    if presentationState.savesAsTodayTask {
                        try todos.addTodayTask(content: content, icon: icon)
                    } else {
                        try quickNotes.add(content: content, icon: icon)
                    }
                    self?.close()
                    return true
                } catch {
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
