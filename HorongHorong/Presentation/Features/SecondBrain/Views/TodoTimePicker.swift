import SwiftUI

/// «직접 고르기» 패널 — 오전·오후, 시, 분을 고른다.
///
/// `DatePicker` 대신 격자를 쓴다. 스테퍼는 8시에서 21시로 가려면 열세 번을 눌러야 하고,
/// 상세 패널은 좁아서 휠 피커가 들어갈 자리가 없다.
///
struct TodoTimePicker: View {
    /// 지금 걸려 있는 시각.
    let hour: Int
    let minute: Int
    let onPick: (Int, Int) -> Void

    private var isAfternoon: Bool { hour >= 12 }
    /// 24시간 값을 12시간 눈금으로. 0시와 12시는 둘 다 «12» 자리다.
    private var displayHour: Int {
        let twelve = hour % 12
        return twelve == 0 ? 12 : twelve
    }

    var body: some View {
        VStack(spacing: 6) {
            meridiemRow
            hourGrid
        }
        .padding(9)
        .background(PopoverChrome.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    // MARK: - 오전 · 오후

    private var meridiemRow: some View {
        HStack(spacing: 4) {
            meridiemButton("오전", afternoon: false)
            meridiemButton("오후", afternoon: true)
            Spacer(minLength: 0)
            Text("분")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
            minuteMenu
        }
    }

    private var minuteMenu: some View {
        Menu {
            ForEach(0..<60, id: \.self) { value in
                Button("\(String(format: "%02d", value))분") {
                    onPick(hour, value)
                }
            }
        } label: {
            Text("\(String(format: "%02d", minute))")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
                .frame(width: 42, height: 26)
                .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .menuStyle(.borderlessButton)
    }

    private func meridiemButton(_ title: String, afternoon: Bool) -> some View {
        let selected = isAfternoon == afternoon
        return Button {
            // 오전↔오후만 바꾼다. 8시를 고른 뒤 «오후» 를 누르면 20시가 되어야 자연스럽다.
            onPick(hourValue(display: displayHour, afternoon: afternoon), minute)
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(selected ? PopoverChrome.ink : PopoverChrome.inkTertiary)
                .frame(width: 62, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? PopoverChrome.card : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 시

    private var hourGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
            ForEach(1...12, id: \.self) { display in
                hourButton(display)
            }
        }
    }

    private func hourButton(_ display: Int) -> some View {
        let selected = displayHour == display
        return Button {
            onPick(hourValue(display: display, afternoon: isAfternoon), minute)
        } label: {
            Text("\(display)")
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(selected ? TodoPickPalette.ink : PopoverChrome.inkSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 27)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? TodoPickPalette.fill : PopoverChrome.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(selected ? TodoPickPalette.stroke : Color.clear, lineWidth: 1.3)
                )
        }
        .buttonStyle(.plain)
    }

    /// 12시간 눈금을 24시간 값으로. «오전 12시» 는 0시, «오후 12시» 는 12시다.
    private func hourValue(display: Int, afternoon: Bool) -> Int {
        let normalized = display % 12
        return afternoon ? normalized + 12 : normalized
    }
}

/// 시작·마감 시각을 세밀하게 맞추는 휠 피커.
/// macOS의 DatePicker는 날짜까지 함께 노출하면 일정 카드가 불필요하게 커지므로,
/// 시와 분만 각각 휠로 보여 주고 선택 즉시 상위 ViewModel에 전달한다.
struct TodoWheelTimePicker: View {
    let date: Date
    let onPick: (Date) -> Void

    private var calendar: Calendar { .current }

    var body: some View {
        HStack(spacing: 8) {
            wheelColumn(
                values: Array(0..<24),
                selected: calendar.component(.hour, from: date),
                label: { String(format: "%02d시", $0) },
                onSelect: { onPick(TodoDayTime.applying(hour: $0, minute: calendar.component(.minute, from: date), to: date)) }
            )
            wheelColumn(
                values: Array(0..<60),
                selected: calendar.component(.minute, from: date),
                label: { String(format: "%02d분", $0) },
                onSelect: { onPick(TodoDayTime.applying(hour: calendar.component(.hour, from: date), minute: $0, to: date)) }
            )
        }
        .padding(8)
        .background(PopoverChrome.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func wheelColumn(
        values: [Int],
        selected: Int,
        label: @escaping (Int) -> String,
        onSelect: @escaping (Int) -> Void
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(values, id: \.self) { value in
                        Button {
                            onSelect(value)
                        } label: {
                            Text(label(value))
                                .font(.system(size: value == selected ? 15 : 13, weight: value == selected ? .heavy : .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(value == selected ? PopoverChrome.ink : PopoverChrome.inkTertiary)
                                .frame(width: 82, height: 28)
                        }
                        .buttonStyle(.plain)
                        .id(value)
                    }
                }
                .padding(.vertical, 42)
            }
            .scrollIndicators(.hidden)
            .frame(width: 90, height: 112)
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(TodoPickPalette.stroke.opacity(0.8), lineWidth: 1)
                    .frame(height: 30)
                    .allowsHitTesting(false)
            }
            // 배치 «도중» 에 스크롤하면 LazyVStack 이 새 항목을 만들고 그게 다시 배치를 불러
            // 트랜잭션이 중첩된다. 한 턴 뒤로 미룬다.
            .onAppear { proxy.scrollAfterLayout(to: selected) }
            .onChange(of: selected) { _, value in
                proxy.scrollAfterLayout(to: value, animation: .easeOut(duration: 0.12))
            }
        }
    }
}
