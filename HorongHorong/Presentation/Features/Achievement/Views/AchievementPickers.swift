import AppKit
import HorongAI
import HorongAIMLX
import OSLog
import SwiftUI
import UniformTypeIdentifiers
#if canImport(FoundationModels)
import FoundationModels
#endif

/*
 기록·하위 목표 고르기 행.

 원래 `AchievementViews.swift`(9,854줄) 한 파일에 있었다. 2026-09-03 분할.
 */

struct AchievementEmptyDetailCard: View {
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(PopoverChrome.inkTertiary)
            Text(message)
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous))
    }
}

struct AchievementMemoPickerRow: View {
    let memo: AchievementMemoDetail
    /// 이 할일을 이미 가진 다른 주간 목표의 제목. 없으면 고를 수 있다.
    ///
    /// 목록에서 감추지 않고 잠근 채로 보여 준다 — 안 보이면 «왜 목록에 없지» 가 되고,
    /// 어느 목표에서 빼야 하는지도 알 수 없다.
    var lockedByGoalTitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(memo.icon ?? MemoIcon.defaultIcon)
                    .font(.system(size: 13))
                Text(memo.content)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(memo.isCompleted ? PopoverChrome.inkSecondary : PopoverChrome.ink)
                    .lineLimit(1)
            }
            if let lockedByGoalTitle {
                HStack(spacing: 7) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("‘\(lockedByGoalTitle)’ 에 연결됨")
                        .lineLimit(1)
                }
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
            }
            let metaText = AchievementDataBuilder.todoMetaText(for: memo)
            if !metaText.isEmpty {
                HStack(spacing: 7) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(statusColor)
                    Text(metaText)
                        .lineLimit(1)
                }
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
            }
        }
    }

    private var statusIcon: String {
        switch AchievementDataBuilder.todoStatus(for: memo) {
        case .done:
            return "checkmark.circle.fill"
        case .future:
            return "circle.dotted"
        case .pending:
            return "circle"
        }
    }

    private var statusColor: Color {
        switch AchievementDataBuilder.todoStatus(for: memo) {
        case .done:
            return PopoverChrome.accent
        case .future:
            return PopoverChrome.inkTertiary
        case .pending:
            return PopoverChrome.inkSecondary
        }
    }
}

struct AchievementChildGoalPickerRow: View {
    let goal: AchievementGoal

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(goal.emoji)
                    .font(.system(size: 13))
                Text(goal.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                    .lineLimit(1)
            }

            HStack(spacing: 7) {
                Text("\(goal.done)/\(goal.total)")
                if !goal.rule.isEmpty {
                    Text(goal.rule)
                        .lineLimit(1)
                }
            }
            .font(.system(size: 10.5, weight: .bold, design: .rounded))
            .foregroundStyle(PopoverChrome.inkTertiary)
        }
    }
}

struct AchievementMemoPickerSection: Identifiable {
    let icon: String
    let label: String
    let memos: [AchievementMemoDetail]

    var id: String { icon }
}
