import AppKit
import SwiftUI

struct QuickMemoView: View {
    var onSave: (String, String) -> Void
    var onCancel: () -> Void

    @AppStorage(Constants.AppStorageKey.menubarIcon)
    private var menubarIconRaw: String = Constants.defaultMenubarIcon

    @State private var memoContent: String = ""
    @State private var selectedIcon: String = MemoIcon.defaultIcon
    @FocusState private var isTextFieldFocused: Bool

    private var menubarIcon: Constants.MenubarIconStyle {
        Constants.MenubarIconStyle(rawValue: menubarIconRaw) ?? .horong
    }

    var body: some View {
        VStack(spacing: 24) {
            header
            editor
            footer
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(width: Constants.quickMemoPanelWidth, height: Constants.quickMemoPanelHeight)
        .background(quickMemoBackground)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color(red: 0.95, green: 0.80, blue: 0.62).opacity(0.55), lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            closeButton
                .padding(.top, 12)
                .padding(.leading, 12)
        }
        .background(QuickMemoShortcutBridge(onCommandReturn: save))
        .onExitCommand {
            onCancel()
        }
        .onAppear {
            focusEditor()
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Menu {
                ForEach(MemoIcon.options, id: \.self) { icon in
                    Button {
                        selectedIcon = icon
                    } label: {
                        Text("\(icon) \(MemoIcon.label(for: icon))")
                    }
                }
            } label: {
                HStack(spacing: 14) {
                    Text(selectedIcon)
                        .font(.system(size: 30))
                        .frame(width: 56, height: 56)
                        .background(Color(red: 1.0, green: 0.80, blue: 0.68), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(MemoIcon.label(for: selectedIcon))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.58, green: 0.27, blue: 0.08))
                        HStack(spacing: 4) {
                            Text("카테고리 바꾸기")
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.58, green: 0.45, blue: 0.34).opacity(0.72))
                    }
                }
            }
            .buttonStyle(.plain)
            .help("카테고리 바꾸기")

            Spacer()

            Image(menubarIcon.imageName)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .accessibilityLabel("메뉴바 아이콘")
        }
    }

    private var closeButton: some View {
        Button {
            onCancel()
        } label: {
            Circle()
                .fill(Color(red: 1.0, green: 0.36, blue: 0.32))
                .frame(width: 14, height: 14)
                .overlay(
                    Circle()
                        .stroke(Color(red: 0.72, green: 0.16, blue: 0.14).opacity(0.65), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.escape, modifiers: [])
        .help("닫기")
        .accessibilityLabel("닫기")
    }

    private var editor: some View {
        TextEditor(text: $memoContent)
            .font(.system(size: 20, weight: .regular, design: .rounded))
            .foregroundStyle(Color(red: 0.22, green: 0.18, blue: 0.15))
            .focused($isTextFieldFocused)
            .frame(height: 138)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color(red: 0.34, green: 0.34, blue: 0.34).opacity(0.72), lineWidth: 1.2)
            )
            .overlay(alignment: .topLeading) {
                if memoContent.isEmpty {
                    Text("빠르게 메모하세요...")
                        .font(.system(size: 20, weight: .regular, design: .rounded))
                        .foregroundStyle(Color(red: 0.68, green: 0.57, blue: 0.47).opacity(0.58))
                        .padding(.horizontal, 26)
                        .padding(.vertical, 23)
                        .allowsHitTesting(false)
                }
            }
    }

    private var footer: some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                shortcutKey("⌘")
                shortcutKey("↩")
                Text("저장")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.58, green: 0.45, blue: 0.34).opacity(0.72))
            }

            Spacer()

            Button {
                save()
            } label: {
                Text("저장")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 88, height: 46)
                    .background(Color(red: 0.63, green: 0.31, blue: 0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    private var quickMemoBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.93, blue: 0.84),
                Color(red: 1.0, green: 0.90, blue: 0.78)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func shortcutKey(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(red: 0.58, green: 0.45, blue: 0.34).opacity(0.72))
            .frame(width: 26, height: 22)
            .background(Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color(red: 0.83, green: 0.73, blue: 0.62).opacity(0.55), lineWidth: 1)
            )
    }

    private func save() {
        guard !memoContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onSave(memoContent, selectedIcon)
    }

    private func focusEditor() {
        DispatchQueue.main.async {
            isTextFieldFocused = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isTextFieldFocused = true
        }
    }
}

private struct QuickMemoShortcutBridge: NSViewRepresentable {
    var onCommandReturn: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCommandReturn: onCommandReturn)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.install(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onCommandReturn = onCommandReturn
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var onCommandReturn: () -> Void
        private weak var view: NSView?
        private var monitor: Any?

        init(onCommandReturn: @escaping () -> Void) {
            self.onCommandReturn = onCommandReturn
        }

        func install(for view: NSView) {
            self.view = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.view?.window else {
                    return event
                }
                guard event.modifierFlags.contains(.command), (event.keyCode == 36 || event.keyCode == 76) else {
                    return event
                }
                self.onCommandReturn()
                return nil
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            removeMonitor()
        }
    }
}
