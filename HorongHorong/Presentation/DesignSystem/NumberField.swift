import SwiftUI
import AppKit

/// 클릭해서 포커스한 뒤에만 스크롤·키보드 화살표로 값을 조정할 수 있는 숫자 입력 필드.
/// - 타이핑: 범위 안의 수가 되는 즉시 바인딩에 반영 (Enter/포커스 해제 시 clamp 확정).
/// - 스크롤: 포커스된 상태에서만 수신, 임계치 누적으로 과한 점프 방지.
/// - ↑/↓ 키: 포커스된 상태에서 step 만큼 가감 (기본 TextField 커서 이동을 가로챔 — 숫자 필드에선 의도된 동작).
struct NumberField: View {
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...999
    var step: Int = 1
    var suffix: String = ""
    var width: CGFloat = 60
    /// Enter 를 눌렀을 때 확정된 값과 함께 부른다. 팝오버의 «적용» 처럼
    /// **입력을 마치는 동작이 곧 완료**인 자리에서 쓴다.
    var onCommit: ((Int) -> Void)? = nil

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
                .onSubmit {
                    commit()
                    onCommit?(value)
                }
                // 타이핑한 값을 바로 바인딩에 흘린다. 예전에는 Enter 나 포커스 해제까지 들고
                // 있었는데, macOS 에서 버튼을 눌러도 텍스트 필드는 first responder 를 놓지
                // 않는다 — 그래서 «45» 를 치고 «적용» 을 눌러도 직전 값이 적용됐다.
                .onChange(of: text) { _, newText in
                    // 범위 밖은 아직 흘리지 않는다. 여기서 clamp 하면 «5» 를 치는 도중
                    // 하한으로 튀어 올라 뒤에 이어 칠 «0» 이 갈 곳을 잃는다. 확정은 commit 이 한다.
                    guard let parsed = Int(newText.trimmingCharacters(in: .whitespaces)),
                          range.contains(parsed), parsed != value else { return }
                    value = parsed
                }
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
                    .fixedSize()
            }
        }
        .onAppear { text = "\(value)" }
        .onChange(of: value) { _, newValue in
            // 이미 같은 수를 치고 있는 중이면 건드리지 않는다 — 다시 써 넣으면 커서가 튄다.
            guard Int(text.trimmingCharacters(in: .whitespaces)) != newValue else { return }
            text = "\(newValue)"
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
