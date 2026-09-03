import HotKey
import AppKit

@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    private var quickMemoHotKey: HotKey?
    private var menuBarPopoverHotKey: HotKey?
    private var timerToggleHotKey: HotKey?
    private var quickMemoHandler: (@MainActor () -> Void)?
    private var menuBarPopoverHandler: (@MainActor () -> Void)?
    private var timerToggleHandler: (@MainActor () -> Void)?

    private init() {}

    func setup(
        onQuickMemo: @escaping @MainActor () -> Void,
        onMenuBarPopover: @escaping @MainActor () -> Void,
        onTimerToggle: @escaping @MainActor () -> Void
    ) {
        quickMemoHandler = onQuickMemo
        menuBarPopoverHandler = onMenuBarPopover
        timerToggleHandler = onTimerToggle
        registerQuickMemo()
        registerMenuBarPopover()
        registerTimerToggle()
    }

    /// HotkeyStore.quickMemo 가 바뀌면 호출돼 현재 핸들러를 그대로 유지한 채 키 조합만 갱신한다.
    func reregisterQuickMemo() {
        registerQuickMemo()
    }

    func reregisterMenuBarPopover() {
        registerMenuBarPopover()
    }

    func reregisterTimerToggle() {
        registerTimerToggle()
    }

    private func registerQuickMemo() {
        guard let handler = quickMemoHandler else { return }
        quickMemoHotKey = makeHotKey(
            combo: HotkeyStore.shared.quickMemo,
            handler: handler
        )
    }

    private func registerMenuBarPopover() {
        guard let handler = menuBarPopoverHandler else { return }
        menuBarPopoverHotKey = makeHotKey(
            combo: HotkeyStore.shared.menuBarPopover,
            handler: handler
        )
    }

    private func registerTimerToggle() {
        guard let handler = timerToggleHandler else { return }
        timerToggleHotKey = makeHotKey(
            combo: HotkeyStore.shared.timerToggle,
            handler: handler
        )
    }

    private func makeHotKey(
        combo: HotkeyCombo,
        handler: @escaping @MainActor () -> Void
    ) -> HotKey? {
        guard let key = Key(carbonKeyCode: combo.keyCode) else {
            return nil
        }
        let hotKey = HotKey(key: key, modifiers: combo.modifiers)
        hotKey.keyDownHandler = {
            Task { @MainActor in
                handler()
            }
        }
        return hotKey
    }
}
