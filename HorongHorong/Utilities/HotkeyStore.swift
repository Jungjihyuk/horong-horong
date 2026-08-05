import AppKit
import Foundation
import Observation

/// 사용자가 지정한 단축키 조합. Carbon 키 코드 + NSEvent.ModifierFlags 의 rawValue.
struct HotkeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var modifierRaw: UInt

    var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifierRaw) }

    /// 기본 퀵 메모 단축키: ⌘ + ⇧ + N. (N 의 carbon keyCode 는 45)
    static let defaultQuickMemo = HotkeyCombo(
        keyCode: 45,
        modifierRaw: NSEvent.ModifierFlags([.command, .shift]).rawValue
    )

    /// 기본 메뉴바 팝오버 단축키: ⌃ + ⌥ + Space.
    static let defaultMenuBarPopover = HotkeyCombo(
        keyCode: 49,
        modifierRaw: NSEvent.ModifierFlags([.control, .option]).rawValue
    )

    /// 기본 타이머 시작/일시정지 단축키: ⌃ + ⌥ + P.
    static let defaultTimerToggle = HotkeyCombo(
        keyCode: 35,
        modifierRaw: NSEvent.ModifierFlags([.control, .option]).rawValue
    )

    /// 메뉴바 / 단축키 패널에 보여줄 ["⌘", "⇧", "N"] 형태의 토큰 배열.
    var displayParts: [String] {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option)  { parts.append("⌥") }
        if modifiers.contains(.shift)   { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(HotkeyCombo.keyLabel(for: keyCode))
        return parts
    }

    static func keyLabel(for keyCode: UInt32) -> String {
        switch keyCode {
        case 0:   return "A"
        case 1:   return "S"
        case 2:   return "D"
        case 3:   return "F"
        case 4:   return "H"
        case 5:   return "G"
        case 6:   return "Z"
        case 7:   return "X"
        case 8:   return "C"
        case 9:   return "V"
        case 11:  return "B"
        case 12:  return "Q"
        case 13:  return "W"
        case 14:  return "E"
        case 15:  return "R"
        case 16:  return "Y"
        case 17:  return "T"
        case 18:  return "1"
        case 19:  return "2"
        case 20:  return "3"
        case 21:  return "4"
        case 22:  return "6"
        case 23:  return "5"
        case 24:  return "="
        case 25:  return "9"
        case 26:  return "7"
        case 27:  return "-"
        case 28:  return "8"
        case 29:  return "0"
        case 30:  return "]"
        case 31:  return "O"
        case 32:  return "U"
        case 33:  return "["
        case 34:  return "I"
        case 35:  return "P"
        case 36:  return "↩"
        case 37:  return "L"
        case 38:  return "J"
        case 39:  return "'"
        case 40:  return "K"
        case 41:  return ";"
        case 42:  return "\\"
        case 43:  return ","
        case 44:  return "/"
        case 45:  return "N"
        case 46:  return "M"
        case 47:  return "."
        case 48:  return "⇥"
        case 49:  return "Space"
        case 50:  return "`"
        case 51:  return "⌫"
        case 53:  return "⎋"
        case 117: return "⌦"
        case 122: return "F1"
        case 120: return "F2"
        case 99:  return "F3"
        case 118: return "F4"
        case 96:  return "F5"
        case 97:  return "F6"
        case 98:  return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:  return "#\(keyCode)"
        }
    }
}

/// 사용자가 커스터마이즈한 전역 단축키 조합을 UserDefaults 에 보관하고 변경을 HotKeyManager 에 전파한다.
@MainActor
@Observable
final class HotkeyStore {
    static let shared = HotkeyStore()

    private static let quickMemoKey = "hotkey.quickMemo"
    private static let menuBarPopoverKey = "hotkey.menuBarPopover"
    private static let timerToggleKey = "hotkey.timerToggle"

    var quickMemo: HotkeyCombo {
        didSet {
            persist(quickMemo, forKey: Self.quickMemoKey)
            HotKeyManager.shared.reregisterQuickMemo()
        }
    }

    var menuBarPopover: HotkeyCombo {
        didSet {
            persist(menuBarPopover, forKey: Self.menuBarPopoverKey)
            HotKeyManager.shared.reregisterMenuBarPopover()
        }
    }

    var timerToggle: HotkeyCombo {
        didSet {
            persist(timerToggle, forKey: Self.timerToggleKey)
            HotKeyManager.shared.reregisterTimerToggle()
        }
    }

    private init() {
        quickMemo = Self.storedCombo(
            forKey: Self.quickMemoKey,
            defaultValue: .defaultQuickMemo
        )
        menuBarPopover = Self.storedCombo(
            forKey: Self.menuBarPopoverKey,
            defaultValue: .defaultMenuBarPopover
        )
        timerToggle = Self.storedCombo(
            forKey: Self.timerToggleKey,
            defaultValue: .defaultTimerToggle
        )
    }

    func resetQuickMemoToDefault() {
        quickMemo = .defaultQuickMemo
    }

    func resetMenuBarPopoverToDefault() {
        menuBarPopover = .defaultMenuBarPopover
    }

    func resetTimerToggleToDefault() {
        timerToggle = .defaultTimerToggle
    }

    private static func storedCombo(
        forKey key: String,
        defaultValue: HotkeyCombo
    ) -> HotkeyCombo {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(HotkeyCombo.self, from: data) else {
            return defaultValue
        }
        return decoded
    }

    private func persist(_ combo: HotkeyCombo, forKey key: String) {
        if let data = try? JSONEncoder().encode(combo) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
