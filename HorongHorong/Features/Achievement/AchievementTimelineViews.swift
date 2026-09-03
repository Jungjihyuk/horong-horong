import AppKit
import HorongAI
import HorongAIMLX
import OSLog
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if canImport(FoundationModels)
import FoundationModels
#endif

/*
 목표 타임라인과 그 정렬·필터.

 원래 `AchievementViews.swift`(9,854줄) 한 파일에 있었다. 2026-09-03 분할.
 */

struct AchievementTimelineSortMenu: View {
    let title: String
    let selectedOrder: Constants.AchievementTimelineSortOrder
    /// '남은 것' 필터에서는 완료 항목이 아예 없어서 완료 기준 정렬이 의미가 없다.
    let disablesCompletionOrders: Bool
    let onSelect: (Constants.AchievementTimelineSortOrder) -> Void

    @State private var isHovering = false

    var body: some View {
        Menu {
            ForEach(Constants.AchievementTimelineSortOrder.allCases) { order in
                Button {
                    onSelect(order)
                } label: {
                    Label(order.menuLabel, systemImage: order == selectedOrder ? "checkmark" : symbolName(for: order))
                }
                .disabled(disablesCompletionOrders && order.dependsOnCompletion)
            }
        } label: {
            HStack(spacing: 4) {
                Text("\(title) · \(selectedOrder.label)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(PopoverChrome.inkSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                isHovering ? PopoverChrome.surfaceAlt : Color.clear,
                in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
        }
        .buttonStyle(.plain)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHovering = $0 }
        // 호버 배경만 얻고 원래 부제목 위치는 그대로 두려고 padding 을 되돌린다.
        .padding(.horizontal, -6)
        .padding(.vertical, -2)
    }

    private func symbolName(for order: Constants.AchievementTimelineSortOrder) -> String {
        switch order {
        case .ascending:      return "arrow.up"
        case .descending:     return "arrow.down"
        case .completedFirst: return "arrow.up.to.line"
        case .completedLast:  return "arrow.down.to.line"
        }
    }
}

struct AchievementTimelineFilters: View {
    let goals: [AchievementGoal]
    @Binding var selectedGoalID: UUID?
    @Binding var selectedFilter: AchievementWeekGoalFilter
    let selectedGoal: AchievementGoal

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AchievementWeekGoalFilter.allCases) { filter in
                Button {
                    selectedFilter = filter
                } label: {
                    Text(filter.rawValue)
                        .font(.system(size: 11.5, weight: selectedFilter == filter ? .bold : .medium, design: .rounded))
                        .foregroundStyle(selectedFilter == filter ? PopoverChrome.selectionInk : PopoverChrome.inkSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selectedFilter == filter ? PopoverChrome.selectionFill : PopoverChrome.surfaceAlt, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Menu {
                ForEach(goals) { goal in
                    Button {
                        selectedGoalID = goal.id
                        selectedFilter = .goal
                    } label: {
                        Text("\(goal.emoji) \(goal.title)")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selectedGoal.emoji)
                    Text(selectedGoal.title)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(PopoverChrome.inkSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous)
                        .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

struct AchievementGoalTimelineView: View {
    let items: [AchievementTimelineItem]
    let onMoveTodo: (UUID, Date) -> Void
    let onToggleTodoCompletion: (UUID) -> Void
    @State private var expandedItemIDs = Set<UUID>()
    @State private var hoveredColumnID: UUID?

    private let columnWidth: CGFloat = 132
    private let axisY: CGFloat = 86
    private let firstTodoCenterOffset: CGFloat = 80
    private let todoBoxHeight: CGFloat = 54
    private let todoSpacing: CGFloat = 8
    private let moreButtonHeight: CGFloat = 28
    private let maxCollapsedTodoCount = 3

    private var todoStep: CGFloat {
        todoBoxHeight + todoSpacing
    }

    var body: some View {
        let totalWidth = CGFloat(items.count) * columnWidth
        let maxVisibleTodoCount = items.map(visibleTodoCount).max() ?? 0
        let hasMoreButton = items.contains { $0.todos.count > maxCollapsedTodoCount }
        let timelineHeight = max(
            CGFloat(220),
            axisY
                + firstTodoCenterOffset
                + CGFloat(max(0, maxVisibleTodoCount - 1)) * todoStep
                + todoBoxHeight / 2
                + (hasMoreButton ? todoSpacing + moreButtonHeight : 0)
                + 23
        )

        GeometryReader { geometry in
            let contentWidth = max(totalWidth, geometry.size.width)
            let resolvedColumnWidth = items.isEmpty ? columnWidth : contentWidth / CGFloat(items.count)

            ScrollView(.horizontal, showsIndicators: contentWidth > geometry.size.width) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let isExpanded = expandedItemIDs.contains(item.id)
                        AchievementTimelineColumn(
                            item: item,
                            axisY: axisY,
                            firstTodoCenterOffset: firstTodoCenterOffset,
                            columnWidth: resolvedColumnWidth,
                            todoBoxHeight: todoBoxHeight,
                            todoSpacing: todoSpacing,
                            moreButtonHeight: moreButtonHeight,
                            maxCollapsedTodoCount: maxCollapsedTodoCount,
                            isExpanded: isExpanded,
                            height: timelineHeight - 10,
                            isLast: index == items.count - 1,
                            onToggleExpanded: {
                                if isExpanded {
                                    expandedItemIDs.remove(item.id)
                                } else {
                                    expandedItemIDs.insert(item.id)
                                }
                            },
                            onMoveTodo: onMoveTodo,
                            onToggleTodoCompletion: onToggleTodoCompletion,
                            onTodoHoverChange: { hovering in
                                hoveredColumnID = hovering ? item.id : (hoveredColumnID == item.id ? nil : hoveredColumnID)
                            }
                        )
                        // 상세 패널이 옆 컬럼 카드에 가리지 않도록 컬럼 자체를 앞으로 끌어올린다.
                        .zIndex(hoveredColumnID == item.id ? 1 : 0)
                    }
                }
                .frame(width: contentWidth, height: timelineHeight - 10, alignment: .topLeading)
                .padding(.top, 10)
                .padding(.bottom, 8)
            }
        }
        .frame(height: timelineHeight + 8, alignment: .top)
        .accessibilityLabel("미리알림 할일 기반 주간 성취 타임라인")
    }

    private func visibleTodoCount(for item: AchievementTimelineItem) -> Int {
        if expandedItemIDs.contains(item.id) {
            return item.todos.count
        }
        return min(maxCollapsedTodoCount, item.todos.count)
    }
}

struct AchievementTimelineColumn: View {
    let item: AchievementTimelineItem
    let axisY: CGFloat
    let firstTodoCenterOffset: CGFloat
    let columnWidth: CGFloat
    let todoBoxHeight: CGFloat
    let todoSpacing: CGFloat
    let moreButtonHeight: CGFloat
    let maxCollapsedTodoCount: Int
    let isExpanded: Bool
    let height: CGFloat
    let isLast: Bool
    let onToggleExpanded: () -> Void
    let onMoveTodo: (UUID, Date) -> Void
    let onToggleTodoCompletion: (UUID) -> Void
    var onTodoHoverChange: (Bool) -> Void = { _ in }
    @State private var isDropTargeted = false

    private var todoStep: CGFloat {
        todoBoxHeight + todoSpacing
    }

    /// 할일 카드가 쓸 수 있는 안쪽 폭. 컬럼이 넓어지면 카드도 같이 넓어져 제목이 덜 잘린다.
    private var todoBoxContentWidth: CGFloat {
        max(94, columnWidth - 12 - 16)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(PopoverChrome.divider)
                .frame(width: columnWidth, height: 2)
                .position(x: columnWidth / 2, y: axisY)

            if isLast {
                Image(systemName: "arrowtriangle.right.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(PopoverChrome.accent)
                    .position(x: columnWidth - 5, y: axisY)
            }

            if let topLabel = item.topLabel {
                AchievementTimelineBadge(label: topLabel, isReward: item.isReward)
                    .position(x: columnWidth / 2, y: axisY - 27)
            }

            AchievementTimelineNode(item: item)
                .position(x: columnWidth / 2, y: axisY)

            Text(item.weekday)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
                .position(x: columnWidth / 2, y: axisY + 25)

            if !item.todos.isEmpty {
                timelineConnectorSegments

                VStack(spacing: 8) {
                    ForEach(visibleTodos) { todo in
                        AchievementTimelineTodoBox(
                            todo: todo,
                            width: todoBoxContentWidth,
                            onHoverChange: onTodoHoverChange,
                            onToggleCompletion: { onToggleTodoCompletion(todo.memoID) }
                        )
                    }

                    if hiddenTodoCount > 0 || isExpanded {
                        Button {
                            onToggleExpanded()
                        } label: {
                            HStack(spacing: 4) {
                                Text(isExpanded ? "접기" : "+\(hiddenTodoCount)개")
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 8.5, weight: .bold))
                            }
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundStyle(PopoverChrome.accent)
                            .frame(width: todoBoxContentWidth, height: moreButtonHeight)
                            .background(PopoverChrome.accentSoft.opacity(0.55), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .position(x: columnWidth / 2, y: firstTodoCenterY + (todoStackHeight - todoBoxHeight) / 2)
            }
        }
        .frame(width: columnWidth, height: height)
        .contentShape(Rectangle())
        .background(isDropTargeted ? PopoverChrome.accentSoft.opacity(0.32) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous)
                .stroke(PopoverChrome.accent.opacity(isDropTargeted ? 0.58 : 0), lineWidth: 1.5)
        )
        .onDrop(of: [.text], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
                return false
            }

            provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let text = object as? NSString,
                      let memoID = AchievementTimelineDragPayload.memoID(from: text as String) else { return }
                DispatchQueue.main.async {
                    onMoveTodo(memoID, item.date)
                }
            }
            return true
        }
    }

    private var connectorColor: Color {
        item.isCompleted ? PopoverChrome.accent.opacity(0.72) : PopoverChrome.inkTertiary.opacity(0.35)
    }

    private var firstTodoCenterY: CGFloat {
        axisY + firstTodoCenterOffset
    }

    private var visibleTodos: [AchievementTimelineTodo] {
        if isExpanded {
            return item.todos
        }
        return Array(item.todos.prefix(maxCollapsedTodoCount))
    }

    private var hiddenTodoCount: Int {
        max(0, item.todos.count - maxCollapsedTodoCount)
    }

    private var todoStackHeight: CGFloat {
        guard !visibleTodos.isEmpty else { return 0 }
        let todoHeight = CGFloat(visibleTodos.count) * todoBoxHeight
        let todoGapHeight = CGFloat(max(0, visibleTodos.count - 1)) * todoSpacing
        let toggleHeight = (hiddenTodoCount > 0 || isExpanded) ? todoSpacing + moreButtonHeight : 0
        return todoHeight + todoGapHeight + toggleHeight
    }

    private var timelineConnectorSegments: some View {
        let lineStartY = axisY + 36
        let firstTopY = firstTodoCenterY - todoBoxHeight / 2

        return ZStack(alignment: .topLeading) {
            connectorSegment(from: lineStartY, to: firstTopY)

            ForEach(0..<max(0, visibleTodos.count - 1), id: \.self) { index in
                let upperBottomY = firstTodoCenterY + CGFloat(index) * todoStep + todoBoxHeight / 2
                let lowerTopY = firstTodoCenterY + CGFloat(index + 1) * todoStep - todoBoxHeight / 2
                connectorSegment(from: upperBottomY, to: lowerTopY)
            }
        }
    }

    private func connectorSegment(from startY: CGFloat, to endY: CGFloat) -> some View {
        let segmentHeight = max(0, endY - startY)

        return Capsule()
            .fill(connectorColor)
            .frame(width: 2.5, height: segmentHeight)
            .position(x: columnWidth / 2, y: startY + segmentHeight / 2)
            .opacity(segmentHeight > 0 ? 1 : 0)
    }
}

struct AchievementTimelineNode: View {
    let item: AchievementTimelineItem

    var body: some View {
        let hasSchedule = !item.todos.isEmpty || item.isReward || item.topLabel != nil

        ZStack {
            Circle()
                .fill(PopoverChrome.accent.opacity(item.isFuture ? 0.16 : 0.22))
                .frame(width: 22, height: 22)
            Circle()
                .fill(PopoverChrome.surface)
                .frame(width: 15, height: 15)
            Circle()
                .fill(hasSchedule ? PopoverChrome.accent.opacity(item.isFuture ? 0.74 : 1) : Color.clear)
                .frame(width: 8, height: 8)
        }
    }
}

struct AchievementTimelineBadge: View {
    let label: String
    let isReward: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isReward ? "gift.fill" : "checkmark.circle.fill")
                .font(.system(size: 9, weight: .bold))
            Text(label)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
        }
        .foregroundStyle(isReward ? PopoverChrome.accentInk : PopoverChrome.accent)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(isReward ? PopoverChrome.accent : PopoverChrome.accentSoft, in: Capsule())
    }
}

struct AchievementTimelineTodoBox: View {
    let todo: AchievementTimelineTodo
    var width: CGFloat = 94
    var onHoverChange: (Bool) -> Void = { _ in }
    var onToggleCompletion: () -> Void = {}

    @State private var isHovering = false
    @State private var hoverTask: Task<Void, Never>?

    private static let hoverDelay: Duration = .milliseconds(500)

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 5) {
                // 동그라미만 눌러 완료를 뒤집는다. 카드 전체를 버튼으로 만들면 끌어서 옮기기와 부딪힌다.
                Button(action: onToggleCompletion) {
                    Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle.dotted")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(todo.isCompleted ? PopoverChrome.accent : PopoverChrome.inkTertiary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(todo.isCompleted ? "완료를 해제합니다" : "완료로 표시합니다")
                Text(todo.title)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            if !todo.meta.isEmpty {
                Text(todo.meta)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .lineLimit(1)
            }
        }
        .frame(width: width, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(height: 54, alignment: .leading)
        .background(todo.isCompleted ? PopoverChrome.card : PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous)
                .stroke(todo.isCompleted ? PopoverChrome.accent.opacity(0.55) : PopoverChrome.border, style: StrokeStyle(lineWidth: 1, dash: todo.isCompleted ? [] : [3, 3]))
        )
        .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
        .overlay(alignment: .topLeading) {
            if isHovering {
                hoverDetail
                    .offset(y: -6)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .zIndex(isHovering ? 1 : 0)
        .onHover { hovering in
            hoverTask?.cancel()
            guard hovering else {
                setHovering(false)
                return
            }
            hoverTask = Task {
                try? await Task.sleep(for: Self.hoverDelay)
                guard !Task.isCancelled else { return }
                setHovering(true)
            }
        }
        .onDisappear {
            hoverTask?.cancel()
        }
        .onDrag {
            hoverTask?.cancel()
            setHovering(false)
            return NSItemProvider(object: AchievementTimelineDragPayload.string(for: todo.memoID) as NSString)
        }
    }

    private func setHovering(_ hovering: Bool) {
        guard isHovering != hovering else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            isHovering = hovering
        }
        onHoverChange(hovering)
    }

    /// 카드와 확실히 구분되도록 어두운 배경으로 띄우는 상세 패널.
    /// 카드는 크림/화이트 계열이라 같은 색을 쓰면 겹쳐도 경계가 보이지 않는다.
    private var hoverDetail: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(todo.title)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.96))
                .fixedSize(horizontal: false, vertical: true)
            if !todo.meta.isEmpty {
                Text(todo.meta)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(width: max(width, 210), alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous)
                .fill(Color(red: 0.16, green: 0.13, blue: 0.11))
        )
        .overlay(
            RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous)
                .stroke(PopoverChrome.accent.opacity(0.65), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.34), radius: 14, x: 0, y: 6)
    }
}
