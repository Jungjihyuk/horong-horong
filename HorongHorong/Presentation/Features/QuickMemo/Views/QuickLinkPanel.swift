import AppKit
import SwiftUI

@MainActor
final class QuickLinkPanel {
    private var panel: NSPanel?

    func toggle(repository: ReferenceRepository, clipboard: ClipboardGateway) {
        if panel?.isVisible == true {
            close()
            return
        }
        show(repository: repository, clipboard: clipboard)
    }

    private func show(repository: ReferenceRepository, clipboard: ClipboardGateway) {
        let panel = QuickLinkWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 270),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.center()

        let viewModel = QuickLinkViewModel(repository: repository, clipboard: clipboard)
        panel.contentView = NSHostingView(rootView: QuickLinkCaptureView(
            viewModel: viewModel,
            onSave: { [weak self] in
                guard viewModel.save() else { return }
                self?.close()
            },
            onCancel: { [weak self] in self?.close() }
        ).appearanceAccentTint(.popover))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private final class QuickLinkWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct QuickLinkCaptureView: View {
    @State var viewModel: QuickLinkViewModel
    let onSave: () -> Void
    let onCancel: () -> Void
    @FocusState private var focus: Field?

    private enum Field { case url, title }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("빠른 링크")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.ink)
                    Text("클립보드의 주소를 References에 저장합니다")
                        .font(.system(size: 11.5, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                }
                Spacer()
                Text("⌘⇧L")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
            }

            VStack(spacing: 9) {
                TextField("https://example.com", text: $viewModel.urlText)
                    .focused($focus, equals: .url)
                TextField("제목 (비우면 도메인 사용)", text: $viewModel.titleText)
                    .focused($focus, equals: .title)
            }
            .textFieldStyle(.roundedBorder)

            HStack {
                if let error = viewModel.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                } else {
                    Text("⌘↩ 저장 · Esc 닫기")
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.inkTertiary)
                }
                Spacer()
                Button("취소", action: onCancel).keyboardShortcut(.cancelAction)
                Button("저장", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!viewModel.canSave)
            }
        }
        .padding(24)
        .frame(width: 420, height: 270)
        .background(PopoverChrome.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(PopoverChrome.border, lineWidth: 1))
        .onAppear {
            viewModel.loadClipboard()
            DispatchQueue.main.async { focus = viewModel.canSave ? .title : .url }
        }
        .onExitCommand(perform: onCancel)
    }
}
