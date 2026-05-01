import HotKey
import AppKit

@MainActor
final class HotKeyManager {
    private var quickMemoHotKey: HotKey?

    func setup(onQuickMemo: @escaping @MainActor () -> Void) {
        quickMemoHotKey = HotKey(key: .n, modifiers: [.command, .shift])
        quickMemoHotKey?.keyDownHandler = {
            Task { @MainActor in
                onQuickMemo()
            }
        }
    }

    func updateQuickMemoHotKey(key: Key, modifiers: NSEvent.ModifierFlags, handler: @escaping @MainActor () -> Void) {
        quickMemoHotKey = HotKey(key: key, modifiers: modifiers)
        quickMemoHotKey?.keyDownHandler = {
            Task { @MainActor in
                handler()
            }
        }
    }
}
