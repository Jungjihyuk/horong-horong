import SwiftUI
import AppKit

/// 클릭해서 포커스한 뒤에만 스크롤·키보드 화살표로 값을 조정할 수 있는 숫자 입력 필드.
/// - 타이핑은 항상 가능 (Enter/포커스 해제 시 확정, 범위 clamp).
/// - 스크롤: 포커스된 상태에서만 수신, 임계치 누적으로 과한 점프 방지.
/// - ↑/↓ 키: 포커스된 상태에서 step 만큼 가감 (기본 TextField 커서 이동을 가로챔 — 숫자 필드에선 의도된 동작).
struct NumberField: View {
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...999
    var step: Int = 1
    var suffix: String = ""
    var width: CGFloat = 60

    @FocusState private var isFocused: Bool
    @State private var text: String = ""
    @State private var monitor: Any? = nil
    @State private var scrollAccumulator: CGFloat = 0

    var body: some View {
        HStack(spacing: 4) {
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .font(.callout.monospacedDigit())
                .frame(width: width)
                .focused($isFocused)
                .onSubmit(commit)
                .onChange(of: isFocused) { _, nowFocused in
                    if nowFocused {
                        installMonitor()
                    } else {
                        removeMonitor()
                        commit()
                    }
                }

            if !suffix.isEmpty {
                Text(suffix)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { text = "\(value)" }
        .onChange(of: value) { _, newValue in
            let s = "\(newValue)"
            if s != text { text = s }
        }
        .onDisappear { removeMonitor() }
    }

    private func adjust(by delta: Int) {
        let clamped = min(max(range.lowerBound, value + delta), range.upperBound)
        if clamped != value {
            value = clamped
            text = "\(clamped)"
        }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let parsed = Int(trimmed) {
            let clamped = min(max(range.lowerBound, parsed), range.upperBound)
            value = clamped
            text = "\(clamped)"
        } else {
            // 잘못된 입력이면 현재 값으로 되돌림
            text = "\(value)"
        }
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        scrollAccumulator = 0
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .keyDown]) { event in
            if event.type == .scrollWheel {
                scrollAccumulator += event.scrollingDeltaY
                let threshold: CGFloat = 8
                var changed = false
                while scrollAccumulator >= threshold {
                    adjust(by: step)
                    scrollAccumulator -= threshold
                    changed = true
                }
                while scrollAccumulator <= -threshold {
                    adjust(by: -step)
                    scrollAccumulator += threshold
                    changed = true
                }
                // 값 조정이 일어났을 때만 이벤트 소비 — 범위 경계에서 더 못 가면 정상 스크롤로 흐르게
                return changed ? nil : event
            } else if event.type == .keyDown {
                switch event.keyCode {
                case 126: // Up Arrow
                    adjust(by: step)
                    return nil
                case 125: // Down Arrow
                    adjust(by: -step)
                    return nil
                default:
                    return event
                }
            }
            return event
        }
    }

    private func removeMonitor() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }
}
