import SwiftUI

/// 취침·기상 시각을 끌어서 정하는 24시간 축 타임라인.
///
/// **끄는 동안에는 저장하지 않는다.** 손을 뗄 때 한 번만 `onCommit` 을 부른다 —
/// 매 프레임 저장하면 SwiftData 가 한 번의 드래그로 수백 번 쓰기를 한다.
///
/// **저장과 «다 적었다» 는 다른 사건이다.** 수면 하나를 적으려면 취침·기상 손잡이를 둘 다
/// 잡아야 하는데, 손을 뗄 때마다 접어 버리면 나머지 하나를 만지려고 매번 다시 펴야 한다.
/// 그래서 손을 떼면 값만 남기고, 접는 일은 «완료» 를 누를 때만 `onFinish` 로 알린다.
///
/// 값만 받는 구조체라 `Equatable` 이 성립한다. 닫힘(클로저)은 비교에서 뺀다 — 매번 새로 만들어져
/// 비교에 넣으면 항상 «달라졌다» 가 되어 `Equatable` 을 다는 의미가 사라진다.
struct DiarySleepTimeline: View, Equatable {
    let day: Date
    /// 저장된 수면. 아직 기록이 없으면 `nil` 이고 기본 구간이 «유령» 으로 보인다.
    let window: DiarySleepWindow?
    let axis: DiarySleepAxis
    let calendar: Calendar
    /// 손잡이를 놓을 때마다. 값만 남긴다.
    let onCommit: (Date, Date) -> Void
    /// «완료» 를 눌렀을 때. 저장한 뒤 부모가 접는다.
    let onFinish: () -> Void
    let onClear: () -> Void

    @State private var draft: DiarySleepWindow?

    /// 눈금선은 설정한 간격을 그대로 쓰되, 라벨은 폭에 맞춰 솎아 낸다 —
    /// 15시간 축에 1시간 간격 라벨 16개는 좁은 폭에서 서로를 덮는다.

    private static let barSpace = "diary.sleep.bar"
    private let barHeight: CGFloat = 30
    private let handleWidth: CGFloat = 13

    nonisolated static func == (lhs: DiarySleepTimeline, rhs: DiarySleepTimeline) -> Bool {
        lhs.day == rhs.day && lhs.window == rhs.window && lhs.axis == rhs.axis && lhs.calendar == rhs.calendar
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                VStack(alignment: .leading, spacing: 5) {
                    tickLabels(width: width)
                    bar(width: width)
                }
            }
            .frame(height: barHeight + 19)
            summaryRow
        }
        .onChange(of: window) { _, _ in draft = nil }
    }

    // MARK: - 축

    private func tickLabels(width: CGFloat) -> some View {
        Canvas { context, size in
            for tick in axis.ticks(maximumCount: Int(width / 26)) {
                let x = min(max(tick.fraction * width, 9), width - 9)
                context.draw(
                    Text(String(format: "%02d", tick.hour))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary),
                    at: CGPoint(x: x, y: size.height / 2)
                )
            }
        }
        .frame(height: 14)
        .allowsHitTesting(false)
    }

    private func bar(width: CGFloat) -> some View {
        let current = effective
        let startX = position(of: current.start, width: width)
        let endX = position(of: current.end, width: width)

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(PopoverChrome.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(PopoverChrome.border, lineWidth: 0.5)
                )
                .overlay(tickLines(width: width))

            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(PopoverChrome.accent.opacity(isGhost ? 0.18 : 0.42))
                .frame(width: max(endX - startX, 2))
                .offset(x: startX)
                .allowsHitTesting(false)

            handle(.bed, x: startX, width: width)
            handle(.wake, x: endX, width: width)
        }
        .frame(height: barHeight)
        .coordinateSpace(name: Self.barSpace)
        .accessibilityLabel("수면 시각")
        .accessibilityValue(DiarySleepText.range(current))
    }

    private func tickLines(width: CGFloat) -> some View {
        Canvas { context, size in
            for tick in axis.ticks where tick.fraction > 0 && tick.fraction < 1 {
                var path = Path()
                let x = tick.fraction * width
                path.move(to: CGPoint(x: x, y: 4))
                path.addLine(to: CGPoint(x: x, y: size.height - 4))
                context.stroke(path, with: .color(PopoverChrome.divider.opacity(0.6)), lineWidth: 0.6)
            }
        }
        .allowsHitTesting(false)
    }

    private func handle(_ kind: Handle, x: CGFloat, width: CGFloat) -> some View {
        Capsule()
            .fill(PopoverChrome.accent)
            .overlay(
                Capsule().stroke(PopoverChrome.surface, lineWidth: 1.5)
            )
            .frame(width: handleWidth, height: barHeight)
            .offset(x: x - handleWidth / 2)
            .opacity(isGhost ? 0.55 : 1)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.barSpace))
                    .onChanged { value in updateDraft(kind, x: value.location.x, width: width) }
                    .onEnded { _ in commit() }
            )
            .help(kind == .bed ? "취침" : "기상")
            .accessibilityLabel(kind == .bed ? "취침 시각" : "기상 시각")
    }

    // MARK: - 요약

    private var summaryRow: some View {
        HStack(spacing: 8) {
            Text(DiarySleepText.range(effective))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(isGhost ? PopoverChrome.inkTertiary : PopoverChrome.ink)
                .monospacedDigit()
            Spacer(minLength: 0)
            if isGhost {
                // 기본 구간이 이미 맞다면 손잡이를 건드릴 이유가 없다. 누르는 순간이 곧 «다 적었다» 다.
                Button("이대로 기록") { finish() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.accent)
            } else {
                if window != nil {
                    Button("지우기") { onClear() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                }
                Button("완료") { finish() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.accent)
            }
        }
    }

    // MARK: - 내부

    private enum Handle { case bed, wake }

    /// 끌고 있는 값 → 저장된 값 → 기본 구간 순으로 본다.
    private var effective: DiarySleepWindow {
        draft ?? window ?? DiarySleepWindowPolicy.defaultWindow(for: day, axis: axis, calendar: calendar)
    }

    /// 아직 저장되지 않아 «이렇게 적으면 됩니다» 만 보여 주는 상태.
    private var isGhost: Bool { window == nil && draft == nil }

    private func position(of date: Date, width: CGFloat) -> CGFloat {
        DiarySleepWindowPolicy.fraction(of: date, day: day, axis: axis, calendar: calendar) * width
    }

    private func updateDraft(_ handle: Handle, x: CGFloat, width: CGFloat) {
        let base = effective
        let dragged = DiarySleepWindowPolicy.date(
            atFraction: x / width,
            day: day,
            axis: axis,
            calendar: calendar
        )
        // 두 손잡이가 서로를 지나치면 «기상이 취침보다 빠른» 구간이 된다. 최소 길이만큼 띄워 막는다.
        let minimum = Double(DiarySleepWindowPolicy.minimumMinutes) * 60
        switch handle {
        case .bed:
            draft = DiarySleepWindow(start: min(dragged, base.end.addingTimeInterval(-minimum)), end: base.end)
        case .wake:
            draft = DiarySleepWindow(start: base.start, end: max(dragged, base.start.addingTimeInterval(minimum)))
        }
    }

    private func commit() {
        let window = effective
        onCommit(window.start, window.end)
    }

    /// 저장한 뒤 «끝났다» 를 알린다. 저장을 한 번 더 하는 이유는 유령 상태에서 바로 눌렀을 때
    /// 아직 아무것도 안 남아 있기 때문이다.
    private func finish() {
        commit()
        onFinish()
    }
}
