import SwiftUI

/*
 마감을 넘긴 목표를 정리하는 배너.

 할일의 기한초과 배너(`overdueMemosBanner`)와 **다른 개념**이라 따로 둔다 —
 그쪽은 «언제 할지 다시 정하는» 일이고, 이쪽은 «이 목표를 살릴지 접을지» 를 정하는 일이다.
 크롬만 같은 것을 쓰고 아이콘과 행동은 나눈다.
 */

/// 정산 대기 목표 한 줄이 화면에 필요로 하는 것.
struct AchievementSettlementRow: Identifiable, Equatable {
    let id: UUID
    let emoji: String
    let title: String
    let cadence: String
    /// 마감이 지난 **날짜**(경계 순간이 아니라 사람이 읽는 날).
    let deadlineDay: Date
    /// 실패로 마감하면 깎일 포인트. 0이면 깎지 않는다.
    let penaltyPoints: Int
}

/// 마감이 지났는데 아직 답하지 않은 목표들을 모아 보여 준다.
///
/// **「기한 지남」은 상태가 아니라 질문이다.** 배지만 달아 두면 답이 영영 나오지 않고
/// 목표가 이번 주로 무한히 이월된다. 여기서 답을 받는다.
struct AchievementSettlementBanner: View {
    let rows: [AchievementSettlementRow]
    /// 자동 마감까지 남은 기간 안내. 유예가 끝나면 시스템이 대신 답한다.
    let graceNoticeText: String?
    let onFail: (AchievementSettlementRow) -> Void
    let onExtend: (AchievementSettlementRow) -> Void
    let onAbandon: (AchievementSettlementRow) -> Void
    /// 쌓인 것이 많을 때 한 번에 접는다. 하나씩 누르게 하면 아무도 정리하지 않는다.
    let onAbandonAll: () -> Void

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일"
        return formatter
    }()

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                header
                ForEach(rows) { row in
                    AchievementSettlementRowView(
                        row: row,
                        dayText: Self.dayFormatter.string(from: row.deadlineDay),
                        onFail: { onFail(row) },
                        onExtend: { onExtend(row) },
                        onAbandon: { onAbandon(row) }
                    )
                }
                if let graceNoticeText {
                    Text(graceNoticeText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PopoverChrome.surfaceAlt.opacity(0.70), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous)
                    .stroke(PopoverChrome.accent.opacity(0.22), lineWidth: PopoverChrome.borderWidth)
            )
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "flag.slash")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(PopoverChrome.accent)
                .frame(width: 30, height: 30)
                .background(PopoverChrome.accentSoft.opacity(0.72), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("마감이 지난 목표 \(rows.count)개")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                Text("실패로 마감할지, 기간을 늘려 이어갈지 정해 주세요.")
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
            }

            Spacer(minLength: 8)

            if rows.count > 2 {
                Button(action: onAbandonAll) {
                    Text("전부 접기")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                }
                .buttonStyle(.plain)
                .help("포인트를 깎지 않고 목록에서 내립니다")
            }
        }
    }
}

/// 목표 한 줄. **값 타입만 받는 독립 View 로 뗀다** — 목록이 길어져도 다시 그리는 범위가 좁다.
private struct AchievementSettlementRowView: View, Equatable {
    let row: AchievementSettlementRow
    let dayText: String
    let onFail: () -> Void
    let onExtend: () -> Void
    let onAbandon: () -> Void

    // View 는 @MainActor 라 비교 함수도 격리를 넘지 않게 nonisolated 로 둔다.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.row == rhs.row && lhs.dayText == rhs.dayText
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(row.emoji)
                .font(.system(size: 13))
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }
            Spacer(minLength: 8)
            actionButton("접기", isPrimary: false, action: onAbandon)
            actionButton("이어서 도전", isPrimary: false, action: onExtend)
            actionButton("실패로 마감", isPrimary: true, action: onFail)
        }
        .padding(9)
        .background(PopoverChrome.card.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
    }

    private var subtitle: String {
        let base = "\(row.cadence) · \(dayText) 마감"
        return row.penaltyPoints > 0 ? "\(base) · 실패 시 −\(row.penaltyPoints)P" : base
    }

    private func actionButton(_ title: String, isPrimary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(isPrimary ? PopoverChrome.accentInk : PopoverChrome.ink)
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(
                    isPrimary ? PopoverChrome.primaryButtonFill : AnyShapeStyle(PopoverChrome.card),
                    in: RoundedRectangle(cornerRadius: PopoverChrome.radius(7), style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }
}

/// 결산 목록에서 «어떻게 끝났나» 를 한눈에 보여 주는 배지.
/// 달성한 목표는 보상 배지가 그 자리를 쓰므로 실패·접음에만 붙는다.
struct AchievementSettledOutcomeBadge: View {
    let outcome: AchievementSettledOutcome

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: outcome.icon)
                .font(.system(size: 10, weight: .bold))
            Text(outcome.label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .foregroundStyle(PopoverChrome.inkTertiary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(PopoverChrome.surfaceAlt.opacity(0.72), in: Capsule())
    }
}
