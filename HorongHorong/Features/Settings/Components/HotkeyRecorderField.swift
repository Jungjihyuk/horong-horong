import SwiftUI
import AppKit

/// 클릭 시 녹화 모드로 들어가 다음 키 입력을 단축키 조합으로 받는다.
/// 한 가지 이상의 모디파이어(⌃ ⌥ ⌘ ⇧)가 함께 눌리지 않으면 무시한다 (글로벌 단축키 안전장치).
/// Esc 는 녹화 취소.
struct HotkeyRecorderField: View {
    @Binding var combo: HotkeyCombo
    @State private var isRecording: Bool = false
    @State private var isHovering: Bool = false
    @State private var monitor: Any? = nil

    var body: some View {
        Button(action: toggleRecording) {
            HStack(spacing: 5) {
                if isRecording {
                    Text("● 키를 누르세요")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(SettingsTheme.accent)
                } else {
                    ForEach(Array(combo.displayParts.enumerated()), id: \.offset) { idx, key in
                        if idx > 0 {
                            Text("+")
                                .font(.caption2)
                                .foregroundStyle(SettingsTheme.accent.opacity(0.6))
                        }
                        Text(key)
                            .font(.caption.monospacedDigit().weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(SettingsTheme.accent.opacity(0.14))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(SettingsTheme.accent.opacity(0.35), lineWidth: 0.5)
                            )
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isRecording
                          ? SettingsTheme.accent.opacity(0.10)
                          : (isHovering ? SettingsTheme.accent.opacity(0.06) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(SettingsTheme.accent.opacity(isRecording ? 0.7 : (isHovering ? 0.55 : 0.35)),
                            lineWidth: isRecording ? 1.2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(isRecording ? "Esc 로 취소" : "클릭해서 단축키 변경")
        .onDisappear(perform: stopCapture)
    }

    private func toggleRecording() {
        if isRecording {
            stopCapture()
            isRecording = false
        } else {
            isRecording = true
            startCapture()
        }
    }

    private func startCapture() {
        stopCapture()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Esc → 취소.
            if event.keyCode == 53 {
                stopCapture()
                isRecording = false
                return nil
            }

            let mods = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .subtracting(.capsLock)
            let required: NSEvent.ModifierFlags = [.command, .control, .option]
            // 글로벌 단축키는 보통 ⌘/⌃/⌥ 중 하나는 필요. Shift 단독은 거부.
            guard !mods.intersection(required).isEmpty else { return nil }

            combo = HotkeyCombo(
                keyCode: UInt32(event.keyCode),
                modifierRaw: mods.rawValue
            )
            stopCapture()
            isRecording = false
            return nil
        }
    }

    private func stopCapture() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }
}
