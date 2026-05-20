import HotKey
import AppKit

@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    private var quickMemoHotKey: HotKey?
    private var quickMemoHandler: (@MainActor () -> Void)?

    private init() {}

    func setup(onQuickMemo: @escaping @MainActor () -> Void) {
        quickMemoHandler = onQuickMemo
        registerQuickMemo()
    }

    /// HotkeyStore.quickMemo 가 바뀌면 호출돼 현재 핸들러를 그대로 유지한 채 키 조합만 갱신한다.
    func reregisterQuickMemo() {
        registerQuickMemo()
    }

    private func registerQuickMemo() {
        guard let handler = quickMemoHandler else { return }
        let combo = HotkeyStore.shared.quickMemo
        guard let key = Key(carbonKeyCode: combo.keyCode) else {
            quickMemoHotKey = nil
            return
        }
        quickMemoHotKey = HotKey(key: key, modifiers: combo.modifiers)
        quickMemoHotKey?.keyDownHandler = {
            Task { @MainActor in
                handler()
            }
        }
    }
}
