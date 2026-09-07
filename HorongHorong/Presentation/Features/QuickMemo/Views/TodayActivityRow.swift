import SwiftUI

/// 시간축 한 줄. 값만 비교해 다른 Todo 변경으로 인한 재렌더링을 막는다(R3).
///
/// **왼쪽 알약이 이 줄의 상태다.** 예전에는 시각·점·동그라미·제목·메뉴가 한 줄에 나란히 놓여
/// 어느 것이 지금 하는 일인지 훑어서는 알 수 없었다. 지금은 진행 중인 일만 알약이 꽉 찬 색이고
/// 다가올 일은 옅게, 끝낸 일은 물러난 회색이라 색만 보고도 오늘의 흐름이 읽힌다.
struct TodoTimelineRow: View, Equatable {
    let item: TodoTimelineItem
    let reminderTitle: String?
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item == rhs.item && lhs.reminderTitle == rhs.reminderTitle
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// 「지났는데 아직」 색. 강조색(주황)과는 구분되어야 하지만 경고등처럼 튀어서도 안 된다 —
    /// 늦었다고 다그치는 화면이 되면 열기가 싫어진다. 크림색 바탕에 어울리는 흐린 테라코타.
    private static let overdueTint = Color(red: 0.76, green: 0.42, blue: 0.36)

    private var isUnscheduled: Bool { item.todo.startDate == nil }
    private var isCompleted: Bool { item.todo.isCompleted }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            rail
            VStack(alignment: .leading, spacing: 2) {
                if let scheduleText {
                    Text(scheduleText)
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isCompleted ? PopoverChrome.inkTertiary : PopoverChrome.inkSecondary)
                }
                Text(item.todo.displayTitle)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(isCompleted ? PopoverChrome.inkTertiary : PopoverChrome.ink)
                    .strikethrough(isCompleted, color: PopoverChrome.inkTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                metaRow
            }
            Spacer(minLength: 4)
            trailingControls
        }
        .padding(.vertical, 5)
        .padding(.trailing, 2)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 왼쪽 시간축

    /// 알약 하나가 곧 시간축이다.
    ///
    /// 예전에는 알약 뒤로 세로선을 그어 «축» 을 만들었는데, 알약 위아래로 주황 선이 삐죽
    /// 새어 나와 그은 자국처럼 보였다. 선을 지우고 알약만 남기니 줄 간격이 곧 시간의 간격으로
    /// 읽힌다 — 지금 어디쯤인지는 «지금» 표시가 이미 알려 준다.
    ///
    /// **크기는 고정이다.** 줄 높이만큼 늘였더니 미리알림 배지가 한 줄 더 붙은 할 일만
    /// 알약이 길쭉해져서, 같은 «완료» 인데 위아래 모양이 달라 보였다. 표시가 달라지는 이유는
    /// 할 일의 **상태** 하나뿐이어야 한다 — 글이 몇 줄인지는 상태가 아니다.
    private var rail: some View {
        Capsule(style: .continuous)
            .fill(capsuleFill)
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(capsuleStroke, lineWidth: 1)
            )
            .overlay(
                Image(systemName: capsuleSymbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(capsuleInk)
            )
            .frame(width: 24, height: 30)
    }

    private var capsuleSymbol: String {
        if isCompleted { return "checkmark" }
        if isUnscheduled { return "tray" }
        switch item.state {
        case .active: return "hourglass"
        // 느낌표는 «틀렸다» 고 나무라는 기호다. 모래가 다 내려간 시계가
        // 「시간이 지났다」 는 말을 그대로 그린다 — 진행 중 기호와도 한 벌이 된다.
        case .elapsed: return "hourglass.bottomhalf.filled"
        default: return "clock"
        }
    }

    private var capsuleFill: Color {
        if isCompleted { return PopoverChrome.inkTertiary.opacity(0.14) }
        if isUnscheduled { return PopoverChrome.surfaceAlt }
        switch item.state {
        // 꽉 찬 색은 «지금 하는 일» 하나만 갖는다. 여러 줄이 동시에 진하면 어디를 봐야 할지 모른다.
        case .active: return PopoverChrome.accent
        case .elapsed: return Self.overdueTint.opacity(0.16)
        default: return PopoverChrome.accentSoft
        }
    }

    private var capsuleInk: Color {
        if isCompleted || isUnscheduled { return PopoverChrome.inkTertiary }
        switch item.state {
        case .active: return .white
        case .elapsed: return Self.overdueTint
        default: return PopoverChrome.accent
        }
    }

    private var capsuleStroke: Color {
        if isCompleted { return .clear }
        if isUnscheduled { return PopoverChrome.divider }
        switch item.state {
        case .active: return .clear
        case .elapsed: return Self.overdueTint.opacity(0.35)
        default: return PopoverChrome.accent.opacity(0.3)
        }
    }

    // MARK: - 오른쪽 조작

    private var trailingControls: some View {
        HStack(spacing: 2) {
            // 메뉴는 마우스를 올렸을 때만 나온다. 늘 떠 있으면 줄마다 점 세 개가 붙어
            // 정작 눈이 가야 할 완료 표시와 경쟁한다.
            Menu {
                Button("편집", action: onEdit)
                Button(isCompleted ? "완료 해제" : "완료", action: onToggle)
                Divider()
                Button("삭제", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .frame(width: 16, height: 20)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 16)
            .opacity(isHovering ? 1 : 0)

            Button(action: onToggle) {
                stateMark.frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(isCompleted ? "완료 해제" : "완료")
        }
        .padding(.top, 1)
    }

    @ViewBuilder private var stateMark: some View {
        switch item.state {
        case .active(let progress):
            ZStack {
                Circle().stroke(PopoverChrome.accent.opacity(0.22), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(PopoverChrome.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .padding(1)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 17))
                .foregroundStyle(PopoverChrome.accent)
        default:
            Image(systemName: "circle")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(PopoverChrome.accent.opacity(0.5))
        }
    }

    // MARK: - 글

    /// «09:00 – 10:00 · 1시간». 소요 시간은 분으로 적지 않고 사람 말로 옮긴다.
    private var scheduleText: String? {
        guard let start = item.todo.startDate else { return nil }
        let startText = Self.timeFormatter.string(from: start)
        guard let end = item.todo.deadline, end > start else { return startText }
        let endText = Self.timeFormatter.string(from: end)
        guard let minutes = item.todo.durationMinutes else { return "\(startText) – \(endText)" }
        return "\(startText) – \(endText) · \(TodoDurationText.title(minutes: minutes))"
    }

    @ViewBuilder private var metaRow: some View {
        let badges = metaBadges
        if !badges.isEmpty {
            HStack(spacing: 4) {
                ForEach(badges, id: \.text) { badge in
                    Text(badge.text)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(badge.tint)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(badge.tint.opacity(0.12), in: Capsule())
                        .lineLimit(1)
                }
            }
            .padding(.top, 1)
        }
    }

    private struct MetaBadge {
        let text: String
        let tint: Color
    }

    /// 상태와 미리알림 목록을 작은 알약으로. 완료한 일은 아무 말도 붙이지 않는다 —
    /// 끝난 줄에 «30분 지남» 이 남아 있으면 아직 할 일이 있는 것처럼 읽힌다.
    private var metaBadges: [MetaBadge] {
        var badges: [MetaBadge] = []
        if !isCompleted {
            switch item.state {
            case .active(let progress):
                badges.append(MetaBadge(text: "진행 중 \(Int((progress * 100).rounded()))%", tint: PopoverChrome.accent))
            case .elapsed(let minutes):
                badges.append(MetaBadge(text: minutes > 0 ? "\(minutes)분 지남" : "지금", tint: Self.overdueTint))
            case .upcoming(let minutes):
                if minutes > 0 { badges.append(MetaBadge(text: "\(minutes)분 후", tint: PopoverChrome.inkTertiary)) }
            case .completed:
                break
            }
        }
        if let reminderTitle {
            badges.append(MetaBadge(text: reminderTitle, tint: PopoverChrome.inkTertiary))
        }
        return badges
    }
}
