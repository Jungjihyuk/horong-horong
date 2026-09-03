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
 상세 창의 목록 행과 머리말.

 원래 `AchievementViews.swift`(9,854줄) 한 파일에 있었다. 2026-09-03 분할.
 */

struct AchievementDetailGoalRow: View {
    let goal: AchievementGoal
    let rewardRepository: RewardRepository
    let onAdd: () -> Void
    let onManage: () -> Void
    let onDelete: () -> Void
    let onOpenRewardTab: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(goal.emoji)
                    .font(.system(size: 22))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(goal.title)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(PopoverChrome.ink)
                        if goal.isOverdue {
                            AchievementOverdueBadge(dueDateText: goal.dueDateText)
                        }
                    }
                    Text("\(goal.cadence) · \(goal.rule)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                }
                Spacer()
                AchievementRewardBadge(reward: goal.reward, color: goal.color)
                AchievementGoalRewardAction(goal: goal, rewardRepository: rewardRepository, onOpenRewardTab: onOpenRewardTab)
                Menu {
                    Button {
                        onAdd()
                    } label: {
                        Label("할일 연결", systemImage: "link")
                    }
                    Button {
                        onManage()
                    } label: {
                        Label("수정", systemImage: "pencil")
                    }
                    Button("삭제", role: .destructive) {
                        onDelete()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
            HStack(spacing: 10) {
                AchievementProgressBar(progress: goal.progress, color: goal.color)
                Text("\(goal.done)/\(goal.total)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(PopoverChrome.ink)
            }

            if !goal.todos.isEmpty {
                VStack(spacing: 6) {
                    ForEach(goal.todos) { todo in
                        HStack(spacing: 7) {
                            Image(systemName: todo.status == .done ? "checkmark.circle.fill" : "circle.dotted")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(todo.status == .done ? goal.color : PopoverChrome.inkTertiary)
                            Text(todo.text)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(todo.status == .done ? PopoverChrome.inkSecondary : PopoverChrome.ink)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            if !todo.metaText.isEmpty {
                                Text(todo.metaText)
                                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                    .foregroundStyle(PopoverChrome.inkTertiary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .achievementDetailCard()
    }
}

struct AchievementPeriodHeader: View {
    let title: String
    let subtitle: String
    let leading: String
    let trailing: String
    let onLeading: () -> Void
    let onTrailing: () -> Void

    var body: some View {
        HStack {
            monthNavigationButton(title: leading, systemImage: "chevron.left", imagePlacement: .leading, action: onLeading)
            Spacer()
            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                Text(subtitle)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
            }
            Spacer()
            monthNavigationButton(title: trailing, systemImage: "chevron.right", imagePlacement: .trailing, action: onTrailing)
        }
        .achievementDetailCard()
    }

    private enum NavigationImagePlacement {
        case leading
        case trailing
    }

    private func monthNavigationButton(
        title: String,
        systemImage: String,
        imagePlacement: NavigationImagePlacement,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if imagePlacement == .leading {
                    Image(systemName: systemImage)
                        .font(.system(size: 8.5, weight: .heavy))
                }
                Text(title)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                if imagePlacement == .trailing {
                    Image(systemName: systemImage)
                        .font(.system(size: 8.5, weight: .heavy))
                }
            }
            .foregroundStyle(PopoverChrome.accent)
            .frame(minWidth: 73, minHeight: 29)
            .padding(.horizontal, 5)
            .background(
                RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous)
                    .fill(PopoverChrome.accentSoft.opacity(0.72))
            )
            .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct AchievementKRRow: View {
    let title: String
    let progress: Double
    var onManage: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.accent)
            }
            AchievementProgressBar(progress: progress, color: PopoverChrome.accent)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onManage?()
        }
    }
}

struct AchievementCalendarLegendButton: View {
    let goal: AchievementGoal
    let onManage: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            onManage()
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(goal.color)
                    .frame(width: 6, height: 6)
                Text(goal.title)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .lineLimit(1)
                Image(systemName: "pencil")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(isHovered ? PopoverChrome.surfaceAlt : Color.clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("목표 관리")
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
