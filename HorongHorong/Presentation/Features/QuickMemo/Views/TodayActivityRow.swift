import SwiftUI

/// 시간축 한 줄. 값만 비교해 다른 Todo 변경으로 인한 재렌더링을 막는다(R3).
///
/// **왼쪽 알약이 이 줄의 상태다.** 예전에는 시각·점·동그라미·제목·메뉴가 한 줄에 나란히 놓여
/// 어느 것이 지금 하는 일인지 훑어서는 알 수 없었다. 지금은 진행 중인 일만 알약이 꽉 찬 색이고
/// 다가올 일은 옅게, 끝낸 일은 물러난 회색이라 색만 보고도 오늘의 흐름이 읽힌다.
struct TodoTimelineRow: View, Equatable {
    let item: TodoTimelineItem
    let railIsElapsed: Bool
    let reminderTitle: String?
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item == rhs.item && lhs.railIsElapsed == rhs.railIsElapsed && lhs.reminderTitle == rhs.reminderTitle
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// 「지났는데 아직」 은 강조색으로 칠할 수 없다. 이 테마의 강조색이 이미 주황이라
    /// 다가올 일과 구분이 안 된다. 붉은 기를 조금 더 준 색을 따로 둔다.
    private static let overdueTint = Color(red: 0.84, green: 0.33, blue: 0.26)

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

    /// 세로선 위에 알약을 얹는다. 알약이 줄 높이만큼 늘어나 붙어 있는 일정은 한 덩어리로,
    /// 사이가 뜬 일정은 선만 남아 «비어 있는 시간» 으로 보인다.
    private var rail: some View {
        ZStack {
            Rectangle()
                .fill(railIsElapsed ? PopoverChrome.accent.opacity(0.35) : PopoverChrome.divider)
                .frame(width: 2)
                .frame(maxHeight: .infinity)

            Capsule(style: .continuous)
                .fill(capsuleFill)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(capsuleStroke, lineWidth: 1)
                )
                .overlay(
                    Image(systemName: capsuleSymbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(capsuleInk)
                )
                .frame(width: 24)
                .frame(maxHeight: .infinity)
                .padding(.vertical, 1)
        }
        .frame(width: 24)
    }

    private var capsuleSymbol: String {
        if isCompleted { return "checkmark" }
        if isUnscheduled { return "tray" }
        switch item.state {
        case .active: return "hourglass"
        case .elapsed: return "exclamationmark"
        default: return "clock"
        }
    }

    private var capsuleFill: Color {
        if isCompleted { return PopoverChrome.inkTertiary.opacity(0.14) }
        if isUnscheduled { return PopoverChrome.surfaceAlt }
        switch item.state {
        case .active: return PopoverChrome.accent
        case .elapsed: return Self.overdueTint
        default: return PopoverChrome.accentSoft
        }
    }

    private var capsuleInk: Color {
        if isCompleted || isUnscheduled { return PopoverChrome.inkTertiary }
        switch item.state {
        case .active, .elapsed: return .white
        default: return PopoverChrome.accent
        }
    }

    private var capsuleStroke: Color {
        if isCompleted { return .clear }
        if isUnscheduled { return PopoverChrome.divider }
        switch item.state {
        case .active, .elapsed: return .clear
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
