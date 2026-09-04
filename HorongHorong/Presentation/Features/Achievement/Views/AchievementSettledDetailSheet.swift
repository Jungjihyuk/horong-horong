import SwiftUI

/*
 결산 목록에서 목표 한 줄을 눌렀을 때 뜨는 **읽기 전용** 시트.

 예전에는 목표 관리(편집) 시트가 떴다. 끝난 목표는 고칠 대상이 아니라 **들여다볼 기록**이라
 이모지·달성 기준·마감일 입력란과 「하위 목표 연결」 목록이 아무 쓸모가 없었고,
 「삭제」·「저장」 버튼이 기록을 건드릴 위험만 만들었다.

 여기서 답하는 질문은 하나다 — **«그때 무엇을 하려고 했었나».**
 월간 목표면 묶여 있던 주간 목표를, 주간 목표면 묶여 있던 할일을 보여 준다.
 */

/// 끝난 목표 한 건을 되짚어 보는 시트.
struct AchievementSettledDetailSheet: View {
    let goal: AchievementGoal
    let outcome: AchievementSettledOutcome
    /// "9월 5일 실패 마감" 처럼 이미 만들어 둔 문구. 날짜 규칙을 여기서 또 만들지 않는다.
    let subtitle: String
    /// 월간 목표에 묶여 있던 주간 목표들. 주간 목표면 비어 있다.
    let childGoals: [AchievementGoal]
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider().opacity(0.35)
            content
        }
        .padding(16)
        .frame(width: 380)
        .frame(maxHeight: 520)
        .background(PopoverChrome.surface)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(goal.emoji)
                .font(.system(size: 24))
            VStack(alignment: .leading, spacing: 4) {
                Text(goal.title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Button("닫기", action: onClose)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                AchievementSettledOutcomeBadge(outcome: outcome)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        // 월간 목표는 하위 주간 목표로 진행률을 낸다. 그 목표들이 «무엇을 하려 했나» 의 답이다.
        // 하위가 하나도 없는 월간 목표는 할일을 직접 묶은 경우라 그쪽을 보여 준다.
        if goal.cadence == "월간", !childGoals.isEmpty {
            section(title: "연결된 주간 목표", count: childGoals.count) {
                ForEach(childGoals) { child in
                    AchievementSettledChildGoalRow(goal: child)
                }
            }
        } else if goal.todos.isEmpty {
            emptyMessage("연결된 항목이 없습니다.")
        } else {
            section(title: "연결된 할일", count: goal.todos.count) {
                ForEach(goal.todos) { todo in
                    AchievementSettledTodoRow(todo: todo)
                }
            }
        }
    }

    @ViewBuilder
    private func section(
        title: String,
        count: Int,
        @ViewBuilder rows: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                Spacer()
                Text("\(count)개")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .monospacedDigit()
            }
            ScrollView {
                // 기록이 쌓이면 이 목록도 함께 는다. VStack 이면 전부 즉시 만든다.
                LazyVStack(alignment: .leading, spacing: 7) {
                    rows()
                }
                .padding(.vertical, 2)
            }
            .popoverScrollbar()
        }
    }

    private func emptyMessage(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(PopoverChrome.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
    }
}

/// 월간 목표 아래에 있던 주간 목표 한 줄.
/// **값 타입만 받는 독립 View 로 뗀다**(R3) — 목록이 길어져도 다시 그리는 범위가 좁다.
private struct AchievementSettledChildGoalRow: View, Equatable {
    let goal: AchievementGoal

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.goal.id == rhs.goal.id
            && lhs.goal.done == rhs.goal.done
            && lhs.goal.total == rhs.goal.total
            && lhs.goal.title == rhs.goal.title
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: goal.isComplete ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(goal.isComplete ? PopoverChrome.accent : PopoverChrome.inkTertiary)
            Text(goal.emoji)
                .font(.system(size: 12))
            Text(goal.title)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(goal.done)/\(goal.total)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
                .monospacedDigit()
        }
        .padding(9)
        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
    }
}

/// 주간 목표에 묶여 있던 할일 한 줄.
private struct AchievementSettledTodoRow: View, Equatable {
    let todo: AchievementTodo

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.todo.id == rhs.todo.id
            && lhs.todo.text == rhs.todo.text
            && lhs.todo.status == rhs.todo.status
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: todo.status == .done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(todo.status == .done ? PopoverChrome.accent : PopoverChrome.inkTertiary)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(todo.text)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(todo.status == .done ? PopoverChrome.inkSecondary : PopoverChrome.ink)
                    .lineLimit(2)
                if !todo.metaText.isEmpty {
                    Text(todo.metaText)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
    }
}
