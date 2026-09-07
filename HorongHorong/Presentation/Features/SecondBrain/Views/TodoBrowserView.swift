import AppKit
import SwiftUI

private enum TodoDurationUnit: Int, CaseIterable, Identifiable {
    case minutes = 1
    case hours = 60
    case days = 1_440

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .minutes: "분"
        case .hours: "시간"
        case .days: "일"
        }
    }
}

/// 할 일 한 줄(카드)의 치수. 높이를 조정할 때 여기만 만진다.
enum TodoRowMetrics {
    static let horizontalPadding: CGFloat = 13
    static let verticalPadding: CGFloat = 8
    static let checkboxSize: CGFloat = 14.5
    /// 제목과 아래 칩 줄 사이.
    static let contentSpacing: CGFloat = 6
}

/// 왼쪽으로 미는 삭제 제스처의 치수.
///
/// 세 값은 **서로 묶여 있다** — 최대 거리를 줄이면서 삭제 문턱을 그대로 두면
/// 문턱에 닿지 못해 삭제가 아예 안 된다. 그래서 비율(0.6 · 0.24)로 파생시킨다.
enum TodoSwipeMetrics {
    /// 카드가 왼쪽으로 밀릴 수 있는 최대 거리.
    static let maximumOffset: CGFloat = 72
    /// 손을 뗐을 때 이만큼 넘게 밀려 있으면 삭제로 친다.
    static let deleteThreshold = maximumOffset * 0.6
    /// 빨간 바탕에 휴지통이 드러나기 시작하는 거리.
    static let trashRevealOffset = maximumOffset * 0.24
}

/// 할 일 목록과 상세.
///
/// **`@Query`·`ModelContext` 를 쓰지 않는다.** 화면은 ViewModel 이 준 값 타입만 본다.
/// 여기 남은 `@State` 는 저장하지 않는 화면 상태뿐이다 — 접힌 그룹, 끌어다 놓는 중인 위치,
/// 스와이프 거리처럼 앱을 껐다 켜면 사라져도 되는 것들.
struct TodoBrowserView: View {
    static let initiallyCollapsedGroups: Set<String> = [
        TodoBucket.overdue.title,
        TodoBucket.someday.title,
        TodoBucket.completed.title,
        "최근 삭제"
    ]

    @State private var viewModel: TodoViewModel

    @State private var collapsedGroups = Self.initiallyCollapsedGroups
    @State private var dropTargetTitle: String?
    @State private var colorPickerListID: String?
    @State private var swipeOffset: CGFloat = 0
    @State private var swipingID: UUID?
    @State private var confirmEmptyTrash = false
    @State private var showsCustomDuration = false
    @State private var customDurationAmount = 30
    @State private var customDurationUnit = TodoDurationUnit.minutes
    @FocusState private var composerFocused: Bool
    @State private var showingComposerHelp = false
    @ObservedObject private var listColors = ReminderListColorStore.shared

    /// 손잡이로 정한 상세 폼 너비. 끄고 켜도 유지된다.
    @AppStorage(Constants.AppStorageKey.todoDetailPaneWidth)
    private var storedDetailPaneWidth: Double = Double(Constants.todoDetailPaneDefaultWidth)
    /// 끄는 동안에만 쓰는 값. 손을 뗄 때 한 번만 저장해 UserDefaults 를 매 프레임 건드리지 않는다.
    @State private var draggingDetailPaneWidth: CGFloat?
    @State private var detailPaneWidthAtDragStart: CGFloat?

    /// 걸리는 시간 네 칸. 왼쪽 둘은 최근에 쓴 값이 흘러가고, 오른쪽 둘은 사용자가 박아 둔다.
    @AppStorage(Constants.AppStorageKey.todoDurationRecent)
    private var durationRecentRaw = TodoDurationSlots.encode(TodoDurationSlots.defaultRecent)
    @AppStorage(Constants.AppStorageKey.todoDurationPinned)
    private var durationPinnedRaw = TodoDurationSlots.encode(TodoDurationSlots.defaultPinned)
    @AppStorage(Constants.AppStorageKey.todoDefaultDuration)
    private var defaultDurationMinutes = Constants.defaultTodoDurationMinutes

    init(repository: TodoRepository) {
        _viewModel = State(initialValue: TodoViewModel(repository: repository))
    }

    var body: some View {
        GeometryReader { proxy in
            let detailWidth = resolvedDetailPaneWidth(totalWidth: proxy.size.width)
            HStack(spacing: 0) {
                listPane
                PaneResizeHandle(
                    onDrag: { translation in
                        let base = detailPaneWidthAtDragStart ?? CGFloat(storedDetailPaneWidth)
                        detailPaneWidthAtDragStart = base
                        draggingDetailPaneWidth = base - translation
                    },
                    onDragEnd: {
                        storedDetailPaneWidth = Double(detailWidth)
                        draggingDetailPaneWidth = nil
                        detailPaneWidthAtDragStart = nil
                    }
                )
                detailPane
                    .frame(width: detailWidth)
            }
        }
        .onAppear {
            viewModel.loadReminderLists()
            viewModel.dayChanged()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            viewModel.dayChanged()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pomodoroLinkedTaskDidComplete)) { _ in
            // 회고 저장은 포모도로 저장소가 직접 Todo를 고치므로, 화면이 들고 있는 스냅샷을 다시 읽는다.
            viewModel.reload()
        }
        .onDisappear {
            viewModel.flush()
            viewModel.commitPendingDeleteIfNeeded()
        }
        .confirmationDialog(
            "최근 삭제의 할 일을 완전히 지울까요? 되돌릴 수 없습니다.",
            isPresented: $confirmEmptyTrash,
            titleVisibility: .visible
        ) {
            Button("비우기", role: .destructive) {
                viewModel.emptyRecentlyDeleted()
            }
            Button("취소", role: .cancel) {}
        }
    }

    /// 방금 쓴 길이를 왼쪽 칸에 남긴다. 직접 입력한 «5분» 이 다음에도 한 번에 잡히도록.
    private func rememberDuration(_ minutes: Int) {
        let recent = TodoDurationSlots.decode(durationRecentRaw)
        let pinned = TodoDurationSlots.decode(durationPinnedRaw)
        durationRecentRaw = TodoDurationSlots.encode(
            TodoDurationSlots.remembering(minutes, recent: recent, pinned: pinned)
        )
    }

    private func pinDuration(_ minutes: Int, pinned shouldPin: Bool) {
        let recent = TodoDurationSlots.decode(durationRecentRaw)
        let pinnedValues = TodoDurationSlots.decode(durationPinnedRaw)
        let next = shouldPin
            ? TodoDurationSlots.pinning(minutes, recent: recent, pinned: pinnedValues)
            : TodoDurationSlots.unpinning(minutes, recent: recent, pinned: pinnedValues)
        durationRecentRaw = TodoDurationSlots.encode(next.recent)
        durationPinnedRaw = TodoDurationSlots.encode(next.pinned)
    }

    /// 창이 좁아졌거나 저장값이 오래됐을 수 있으므로 그릴 때마다 지금 창 크기로 다시 자른다.
    ///
    /// **최소 너비는 상수다.** 예전에는 머리말과 일정 카드의 글자 폭을 `GeometryReader` 로
    /// 재서 여기에 넣었는데, 그 값이 다시 두 칸의 폭을 정하는 바람에 레이아웃이 수렴하지
    /// 못하고 앱이 멈췄다. 좁아졌을 때의 표현은 `ViewThatFits` 가 맡는다.
    private func resolvedDetailPaneWidth(totalWidth: CGFloat) -> CGFloat {
        PaneWidthPolicy.resolveTrailing(
            proposed: draggingDetailPaneWidth ?? CGFloat(storedDetailPaneWidth),
            totalWidth: totalWidth,
            leadingMinimum: Constants.todoListPaneMinWidth,
            trailingMinimum: Constants.todoDetailPaneMinWidth,
            trailingMaximum: Constants.todoDetailPaneMaxWidth
        )
    }

    // MARK: - 목록

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            composer
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    group(bucket: .overdue, items: viewModel.overdue, hint: nil)
                    group(bucket: .today, items: viewModel.today, hint: nil)
                    group(bucket: .upcoming, items: viewModel.upcoming, hint: nil)
                    group(bucket: .someday, items: viewModel.someday, hint: "날짜 없음")
                    group(bucket: .completed, items: viewModel.completed, hint: nil)
                    recentlyDeletedGroup
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
        }
        .frame(maxWidth: .infinity)
        .background(PopoverChrome.surface)
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: BrowserHeaderMetrics.titleSearchSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Todo")
                    .font(BrowserHeaderMetrics.titleFont)
                    .foregroundStyle(PopoverChrome.ink)
                    // 없으면 좁을 때 «To / do» 로 접힌다. 제목은 접히느니 잘리는 게 낫다.
                    .lineLimit(1)
                // 좁아지면 접히는 대신 짧은 표현으로 갈아탄다. 폭을 재서 최소 너비로
                // 되먹이면 «측정 → 상태 → 폭 → 재측정» 고리가 생겨 레이아웃이 수렴하지 않는다.
                ViewThatFits(in: .horizontal) {
                    Text("미리알림에 \(viewModel.linkedCount)개 연동 중")
                    Text("\(viewModel.linkedCount)개 연동 중")
                    Text("\(viewModel.linkedCount)개 연동")
                }
                .font(BrowserHeaderMetrics.subtitleFont)
                .foregroundStyle(PopoverChrome.inkTertiary)
                .lineLimit(1)
            }
            // 자리를 놓고 다투면 검색창이 먼저 양보한다. 제목·부제가 먼저 뭉개지면
            // 여기가 무슨 화면인지부터 읽히지 않는다.
            .layoutPriority(1)
            Spacer(minLength: BrowserHeaderMetrics.titleSearchMinimumGap)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(PopoverChrome.inkTertiary)
                TextField("할 일 검색", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            // 220 고정이면 좁은 칸에서 제목 자리를 통째로 먹는다. 줄어들 수 있게 둔다.
            .frame(minWidth: BrowserHeaderMetrics.searchFieldMinimumWidth,
                   maxWidth: BrowserHeaderMetrics.searchFieldWidth,
                   minHeight: 36, maxHeight: 36)
            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
            )
        }
        .padding(.horizontal, BrowserHeaderMetrics.horizontalPadding)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var composer: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(PopoverChrome.accent)

            TextField("예: 내일 9:30~10시 회의, 모레 1시간 운동", text: $viewModel.composerText)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .focused($composerFocused)
                .onSubmit(submit)

            if let summary = viewModel.composerScheduleSummary() {
                HStack(spacing: 4) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 11, weight: .semibold))
                    Text(summary)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                }
                .foregroundStyle(PopoverChrome.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(PopoverChrome.accent.opacity(0.12))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(PopoverChrome.accent.opacity(0.32), lineWidth: 1)
                )
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }

            Button {
                showingComposerHelp.toggle()
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PopoverChrome.inkSecondary)
            }
            .buttonStyle(.plain)
            .help("빠른 일정 입력 문법 가이드")
            .popover(isPresented: $showingComposerHelp, arrowEdge: .bottom) {
                composerHelpPopover
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: viewModel.composerScheduleSummary())
        .padding(.horizontal, 13)
        .frame(height: 44)
        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(PopoverChrome.accent.opacity(0.36), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var composerHelpPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(PopoverChrome.accent)
                Text("빠른 일정 입력 가이드")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
            }

            Text("입력창에 날짜나 시간을 함께 적으면 일정이 자동으로 등록됩니다.")
                .font(.system(size: 11.5))
                .foregroundStyle(PopoverChrome.inkSecondary)

            Divider().overlay(PopoverChrome.divider)

            VStack(alignment: .leading, spacing: 9) {
                helpRow(category: "날짜", examples: "내일, 모레, 글피, 금요일, 다음주 월요일")
                helpRow(category: "시간 범위", examples: "9시 30분 ~ 10시, 9:30~10:00, 9시부터 10시까지")
                helpRow(category: "시작 + 소요", examples: "9시 시작 30분간, 9시 30분간, 오후 2시 1시간")
                helpRow(category: "소요시간만", examples: "30분간, 1시간 동안, 90분 (기본 9시 시작)")
                helpRow(category: "시작시각만", examples: "14:00, 오후 3시 (마감 없음)")
            }

            Divider().overlay(PopoverChrome.divider)

            HStack(spacing: 4) {
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .bold))
                Text("엔터를 누르면 일정은 날짜로 들어가고 제목만 깔끔하게 등록됩니다.")
                    .font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(PopoverChrome.accent)
        }
        .padding(14)
        .frame(width: 320)
    }

    private func helpRow(category: String, examples: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(category)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(PopoverChrome.accent)
            Text(examples)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(PopoverChrome.ink)
        }
    }

    private func group(bucket: TodoBucket, items: [TodoItem], hint: String?) -> some View {
        let title = bucket.title
        let expanded = !collapsedGroups.contains(title)
        let isDropTarget = dropTargetTitle == title
        // **LazyVStack 이어야 한다.** 평범한 VStack 이면 이 그룹의 행을 전부 즉시 만든다.
        // 바깥 LazyVStack 은 «그룹 컨테이너» 6개만 지연 생성하므로, 컨테이너가 만들어지는
        // 순간 안쪽 행 수천 개가 한꺼번에 그려졌다
        // (실측 2026-09-02: todo 5,235건에서 그리기에만 1,235ms · 행당 0.34ms).
        return LazyVStack(alignment: .leading, spacing: 7) {
            groupHeader(title: title, count: items.count, hint: hint, expanded: expanded)

            if expanded {
                if items.isEmpty {
                    if bucket != .overdue {
                        groupPlaceholder("여기로 끌어다 놓으세요")
                    }
                } else {
                    ForEach(items) { item in
                        rowOrPendingDelete(item)
                    }
                }
            } else if isDropTarget {
                Text("여기에 놓기")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.accent)
                    .padding(.bottom, 6)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isDropTarget ? PopoverChrome.accentSoft.opacity(0.55) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isDropTarget ? PopoverChrome.accent.opacity(0.55) : Color.clear, lineWidth: 1.5)
        )
        .dropDestination(for: String.self) { dropped, _ in
            guard bucket != .overdue else { return false }
            guard let id = dropped.first else { return false }
            viewModel.move(idString: id, to: bucket)
            collapsedGroups.remove(title)
            dropTargetTitle = nil
            return true
        } isTargeted: { hovering in
            guard bucket != .overdue else { return }
            if hovering {
                dropTargetTitle = title
            } else if dropTargetTitle == title {
                dropTargetTitle = nil
            }
        }
    }

    private func groupHeader(title: String, count: Int, hint: String?, expanded: Bool) -> some View {
        Button {
            toggleCollapsed(title, expanded: expanded)
        } label: {
            HStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 11.5, weight: .heavy, design: .rounded))
                countBadge(count)
                if let hint {
                    Text(hint)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .foregroundStyle(PopoverChrome.inkSecondary)
            .padding(.top, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func countBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(.system(size: 10.5, weight: .heavy, design: .rounded))
            .foregroundStyle(PopoverChrome.inkTertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func groupPlaceholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            .foregroundStyle(PopoverChrome.inkTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
    }

    private var recentlyDeletedGroup: some View {
        let title = "최근 삭제"
        let expanded = !collapsedGroups.contains(title)
        let items = viewModel.recentlyDeleted
        let isDropTarget = dropTargetTitle == title
        return LazyVStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Button {
                    toggleCollapsed(title, expanded: expanded)
                } label: {
                    HStack(spacing: 7) {
                        Text(title)
                            .font(.system(size: 11.5, weight: .heavy, design: .rounded))
                        countBadge(items.count)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if !items.isEmpty {
                    Button("비우기") {
                        confirmEmptyTrash = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(TodoPalette.danger)
                }
            }
            .padding(.top, 8)

            if expanded {
                if items.isEmpty {
                    groupPlaceholder("삭제한 할 일이 여기 모입니다")
                } else {
                    ForEach(items) { item in
                        rowOrPendingDelete(item)
                    }
                }
            } else if isDropTarget {
                Text("여기에 놓기")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.accent)
                    .padding(.bottom, 6)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isDropTarget ? PopoverChrome.accentSoft.opacity(0.55) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isDropTarget ? PopoverChrome.accent.opacity(0.55) : Color.clear, lineWidth: 1.5)
        )
        .dropDestination(for: String.self) { dropped, _ in
            guard let id = dropped.first else { return false }
            guard viewModel.moveToRecentlyDeleted(idString: id) else { return false }
            collapsedGroups.remove(title)
            dropTargetTitle = nil
            return true
        } isTargeted: { hovering in
            if hovering {
                dropTargetTitle = title
            } else if dropTargetTitle == title {
                dropTargetTitle = nil
            }
        }
    }

    private func toggleCollapsed(_ title: String, expanded: Bool) {
        if expanded {
            collapsedGroups.insert(title)
        } else {
            collapsedGroups.remove(title)
        }
    }

    // MARK: - 행

    @ViewBuilder
    private func rowOrPendingDelete(_ item: TodoItem) -> some View {
        if viewModel.pendingDeleteID == item.id {
            pendingDeleteRow(item)
        } else {
            todoRow(item)
        }
    }

    private func pendingDeleteRow(_ item: TodoItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "trash")
                .font(.system(size: 12, weight: .bold))
            Text("삭제됨")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text(item.displayTitle)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .lineLimit(1)
                .foregroundStyle(PopoverChrome.inkTertiary)
            Spacer(minLength: 8)
            Button("취소") {
                viewModel.cancelPendingDelete()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(PopoverChrome.accentInk)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(PopoverChrome.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(TodoPalette.danger, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func todoRow(_ item: TodoItem) -> some View {
        let offset = swipingID == item.id ? swipeOffset : 0
        return ZStack(alignment: .trailing) {
            if offset < -0.5 {
                TodoPalette.danger
                    .overlay {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .opacity(offset < -TodoSwipeMetrics.trashRevealOffset ? 1 : 0)
                    }
                    .frame(width: -offset)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            cardContent(item)
                .offset(x: offset)
        }
        .clipped()
        // **마우스 `DragGesture` 를 달지 않는다.** 여기에 `highPriorityGesture` 로 걸면
        // 자식(`cardContent`)의 `.draggable` 보다 먼저 이벤트를 가져가 섹션 간 끌어다 놓기가
        // 아예 시작되지 않는다. 스와이프 삭제는 아래 트랙패드 두 손가락 경로가 맡는다 —
        // 그쪽은 `scrollWheel` 이벤트라 누르고 끄는 제스처와 겹치지 않는다.
        .background {
            TodoTrackpadSwipeCatcher(
                onChanged: { applySwipe(item, translation: $0) },
                onEnded: { endSwipe(item, translation: $0) }
            )
            .allowsHitTesting(false)
        }
    }

    private func cardContent(_ item: TodoItem) -> some View {
        let list = viewModel.reminderList(for: item)
        return HStack(alignment: .top, spacing: 11) {
            Button {
                viewModel.toggleCompleted(item)
            } label: {
                TodoCheckbox(isCompleted: item.isCompleted)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

            TodoCardBody(
                title: item.displayTitle,
                isCompleted: item.isCompleted,
                chip: TodoDueChip.of(
                    startDate: item.startDate,
                    deadline: item.deadline,
                    now: viewModel.todayReferenceDate
                ),
                list: list,
                swatch: list.map { listColors.swatch(for: $0.id) },
                isLinked: item.isLinkedToReminders
            )

            Spacer(minLength: 0)
            if item.isRecentlyDeleted {
                Button("복원") {
                    restore(item)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.accent)
                .padding(.top, 1)
            }
        }
        .padding(.horizontal, TodoRowMetrics.horizontalPadding)
        .padding(.vertical, TodoRowMetrics.verticalPadding)
        .opacity(item.isCompleted ? 0.5 : 1)
        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        // `stroke` 는 선을 경계선 위에 걸쳐 그려 절반이 카드 밖 배경과 섞인다. 그래서 색이
        // 어정쩡해 보였다. `strokeBorder` 로 안쪽에만 그려 한 가지 배경 위에 또렷하게 얹는다.
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(
                    viewModel.selected?.id == item.id ? PopoverChrome.accent : Color.clear,
                    lineWidth: 2.25
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { viewModel.select(item.id) }
        .draggable(item.id.uuidString) {
            Text(item.displayTitle)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: Color.black.opacity(0.12), radius: 8, y: 3)
        }
    }

    // MARK: - 상세

    @ViewBuilder
    private var detailPane: some View {
        if let item = viewModel.selected {
            VStack(alignment: .leading, spacing: 0) {
                detailHeader(item)
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        detailEditor
                        Divider().overlay(PopoverChrome.divider)
                        detailFields(item)
                    }
                }
            }
            .onChange(of: item.id) { _, _ in
                showsCustomDuration = false
            }
            .background(PopoverChrome.surfaceAlt.opacity(0.35))
        } else {
            VStack(spacing: 10) {
                Text("✓")
                    .font(.system(size: 32))
                Text("할 일을 고르면 날짜와 미리알림을 정할 수 있어요")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(36)
        }
    }

    private func detailHeader(_ item: TodoItem) -> some View {
        HStack {
            Text(item.isRecentlyDeleted ? "최근 삭제" : "할 일")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
            Spacer()
            if item.isRecentlyDeleted {
                Button("복원") {
                    restore(item)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.accent)
            }
            Button {
                viewModel.armPendingDelete(item.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(TodoPalette.danger)
            }
            .buttonStyle(.plain)
            .help(item.isRecentlyDeleted ? "완전히 삭제" : "삭제")
        }
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .padding(.bottom, 8)
    }

    private var detailEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            TodoTitleField(text: $viewModel.titleDraft)
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .onChange(of: viewModel.titleDraft) { _, _ in viewModel.draftChanged() }

            TextField("메모", text: $viewModel.noteDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5, design: .rounded))
                .lineLimit(1...)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 18)
                .onChange(of: viewModel.noteDraft) { _, _ in viewModel.draftChanged() }
        }
    }

    private func detailFields(_ item: TodoItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            scheduleSection(item)
            reminderSection(item)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
            Text(title)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
        }
        .foregroundStyle(PopoverChrome.inkTertiary)
    }

    private func scheduleSection(_ item: TodoItem) -> some View {
        TodoScheduleCard(
            startDate: item.startDate,
            deadline: item.deadline,
            today: viewModel.todayReferenceDate,
            onPickDayOffset: { viewModel.setStartDay(item.id, dayOffset: $0, defaultDurationMinutes: defaultDurationMinutes) },
            onClear: { viewModel.clearSchedule(item.id) },
            onPickTime: { viewModel.setStartTime(item.id, hour: $0, minute: $1) },
            onPickDeadlineTime: { viewModel.setDeadlineTime(item.id, hour: $0, minute: $1) },
            durationSlots: TodoDurationSlots.slots(
                recent: TodoDurationSlots.decode(durationRecentRaw),
                pinned: TodoDurationSlots.decode(durationPinnedRaw)
            ),
            onPickDuration: { minutes in
                viewModel.setDuration(item.id, minutes: minutes)
                rememberDuration(minutes)
            },
            onPinDuration: { pinDuration($0, pinned: true) },
            onUnpinDuration: { pinDuration($0, pinned: false) },
            onClearDuration: { viewModel.clearDeadline(item.id) },
            onCustomDuration: {
                prepareCustomDuration(item)
                showsCustomDuration = true
            },
            showsCustomDuration: $showsCustomDuration,
            customDurationContent: { customDurationPopover(for: item) }
        )
    }

    private func reminderSection(_ item: TodoItem) -> some View {
        TodoReminderCard(
            isLinked: item.isLinkedToReminders,
            isEditable: !item.isRecentlyDeleted,
            lists: viewModel.reminderLists,
            selectedListID: viewModel.reminderList(for: item)?.id,
            startDate: item.startDate,
            today: viewModel.todayReferenceDate,
            statusMessage: viewModel.reminderStatusMessage,
            swatch: { listColors.swatch(for: $0) },
            onToggleLink: { viewModel.toggleReminder(item) },
            onSelectList: { viewModel.setReminderList(item.id, listID: $0) }
        )
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundStyle(PopoverChrome.inkTertiary)
            .frame(width: 50, alignment: .leading)
    }

    private func isCustomDuration(_ item: TodoItem) -> Bool {
        guard let minutes = item.durationMinutes else { return false }
        return ![30, 60, 120].contains(minutes)
    }

    private func prepareCustomDuration(_ item: TodoItem) {
        let minutes = item.durationMinutes ?? 30
        if minutes.isMultiple(of: 1_440) {
            customDurationAmount = minutes / 1_440
            customDurationUnit = .days
        } else if minutes.isMultiple(of: 60) {
            customDurationAmount = minutes / 60
            customDurationUnit = .hours
        } else {
            customDurationAmount = minutes
            customDurationUnit = .minutes
        }
    }

    /// 직접 입력한 길이를 할 일에 적고 팝오버를 닫는다. 엔터와 «적용» 이 같은 길을 타야
    /// 둘 중 무엇을 눌렀는지에 따라 결과가 달라지지 않는다.
    private func applyCustomDuration(for item: TodoItem, amount: Int) {
        let minutes = min(999, max(1, amount)) * customDurationUnit.rawValue
        viewModel.setDuration(item.id, minutes: minutes)
        rememberDuration(minutes)
        showsCustomDuration = false
    }

    private func customDurationPopover(for item: TodoItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("소요 시간")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)

            HStack(spacing: 8) {
                Button {
                    customDurationAmount = max(1, customDurationAmount - 1)
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .help("줄이기")

                NumberField(
                    value: $customDurationAmount,
                    range: 1...999,
                    width: 58,
                    // 엔터가 곧 «적용» 이다. 값만 확정하고 팝오버가 남아 있으면
                    // 「엔터를 치고 적용을 또 눌러야 하는」 두 번 손이 된다.
                    onCommit: { applyCustomDuration(for: item, amount: $0) }
                )

                Picker("", selection: $customDurationUnit) {
                    ForEach(TodoDurationUnit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 72)

                Button {
                    customDurationAmount = min(999, customDurationAmount + 1)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("늘리기")
            }

            HStack {
                Spacer()
                Button("적용") {
                    applyCustomDuration(for: item, amount: customDurationAmount)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(width: 240)
        .background(PopoverChrome.surface)
        .appearanceAccentTint(.popover)
    }

    private func reminderListMenu(for item: TodoItem) -> some View {
        let currentList = viewModel.reminderList(for: item) ?? viewModel.reminderLists.first(where: \.isDefault)
        let swatch = listColors.swatch(for: currentList?.id ?? "")

        return HStack(spacing: 6) {
            Menu {
                ForEach(viewModel.reminderLists) { list in
                    Button {
                        viewModel.setReminderList(item.id, listID: list.id)
                    } label: {
                        if list.id == currentList?.id {
                            Label(list.title, systemImage: "checkmark")
                        } else {
                            Text(list.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(swatch.dot)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(PopoverChrome.ink.opacity(0.18), lineWidth: 0.5))
                    Text(currentList?.title ?? "목록 선택")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(swatch.ink)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(swatch.wash, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(swatch.dot.opacity(0.35), lineWidth: 1.2)
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if let list = currentList {
                Button {
                    colorPickerListID = list.id
                } label: {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 11))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .frame(width: 26, height: 26)
                        .background(PopoverChrome.surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(PopoverChrome.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("목록 테마 색상 변경")
                .popover(isPresented: Binding(
                    get: { colorPickerListID == list.id },
                    set: { if !$0 { colorPickerListID = nil } }
                )) {
                    listColorPicker(for: list)
                }
            }
        }
    }

    private func listColorPicker(for list: ReminderListOption) -> some View {
        let current = listColors.swatch(for: list.id)
        return VStack(alignment: .leading, spacing: 10) {
            Text("목록 색")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
            Text("호롱 톤에 맞춘 색만 고를 수 있어요")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(28), spacing: 8), count: 4),
                spacing: 8
            ) {
                ForEach(ReminderListSwatch.allCases) { option in
                    Button {
                        listColors.set(option, for: list.id)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(option.dot)
                                .frame(width: 22, height: 22)
                                .overlay(Circle().stroke(PopoverChrome.ink.opacity(0.16), lineWidth: 0.5))
                            if current == option && listColors.isOverridden(list.id) {
                                Circle()
                                    .stroke(PopoverChrome.ink, lineWidth: 1.8)
                                    .frame(width: 28, height: 28)
                            }
                        }
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(option.label)
                    .accessibilityLabel(option.label)
                }
            }

            Button {
                listColors.reset(list.id)
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(ReminderListSwatch.automatic(for: list.id).dot)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(PopoverChrome.divider, lineWidth: 1))
                    Text("자동 색")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(PopoverChrome.ink)
                    Spacer(minLength: 4)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(PopoverChrome.ink)
                        .opacity(listColors.isOverridden(list.id) ? 0 : 1)
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(
                    listColors.isOverridden(list.id) ? PopoverChrome.card : PopoverChrome.selectionFill,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(PopoverChrome.divider, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 168)
        .background(PopoverChrome.surface)
        .appearanceAccentTint(.popover)
    }

    // MARK: - 동작

    private func submit() {
        viewModel.submitComposer()
        composerFocused = true
    }

    /// 되살린 할 일이 접힌 그룹으로 들어가면 «어디 갔지» 가 된다. 그 그룹을 펴 준다.
    private func restore(_ item: TodoItem) {
        viewModel.restore(item.id)
        collapsedGroups.remove(item.bucket(now: viewModel.todayReferenceDate).title)
    }

    private func applySwipe(_ item: TodoItem, translation: CGFloat) {
        guard translation < 0 else { return }
        swipingID = item.id
        swipeOffset = max(translation, -TodoSwipeMetrics.maximumOffset)
    }

    private func endSwipe(_ item: TodoItem, translation: CGFloat) {
        let shouldDelete = translation < -TodoSwipeMetrics.deleteThreshold
        withAnimation(.easeOut(duration: 0.28)) {
            swipeOffset = 0
            swipingID = nil
        }
        if shouldDelete {
            viewModel.armPendingDelete(item.id)
        }
    }
}

struct TodoTitleField: View {
    @Binding var text: String

    var body: some View {
        TextField("무엇을 할까요", text: Binding(
            get: { text },
            // 저장 형식에서 개행은 제목과 메모의 경계이므로 제목 안의 개행은 공백으로 바꾼다.
            set: { text = $0.components(separatedBy: .newlines).joined(separator: " ") }
        ), axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 17, weight: .heavy, design: .rounded))
            // 제목을 축소하거나 가로 스크롤하지 않고 패널 너비에 맞춰 읽을 수 있게 한다.
            .lineLimit(1...)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("할 일 제목")
    }
}

/// 트랙패드 두 손가락 가로 스크롤을 **손가락이 실제로 움직인 방향**으로 되돌린다.
///
/// AppKit 은 «자연스러운 스크롤» 설정에 따라 `scrollingDeltaX` 부호를 이미 뒤집어서 준다.
/// 스크롤이라면 그대로 쓰면 되지만 스와이프 삭제는 카드가 손가락을 따라와야 하는 **직접 조작**이라
/// 설정과 무관하게 손가락 방향으로 통일해야 한다. 왼쪽이 음수다.
enum TodoSwipeDirection {
    static func fingerTranslation(
        scrollingDeltaX: CGFloat,
        isDirectionInvertedFromDevice: Bool
    ) -> CGFloat {
        isDirectionInvertedFromDevice ? scrollingDeltaX : -scrollingDeltaX
    }
}

/// 할 일 화면에서만 쓰는 색. 리터럴이 여러 곳에 흩어져 있어 한 곳에 모았다.
private enum TodoPalette {
    static let danger = Color(red: 0.75, green: 0.34, blue: 0.23)
    static let linkedInk = Color(red: 0.31, green: 0.49, blue: 0.27)
    static let linkedFill = Color(red: 0.89, green: 0.94, blue: 0.87)
}

struct TodoCheckbox: View {
    let isCompleted: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(isCompleted ? Color.clear : Color.black.opacity(0.2), lineWidth: 1.4)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isCompleted ? Color(red: 0.44, green: 0.68, blue: 0.39) : Color.white)
                )
            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: TodoRowMetrics.checkboxSize, height: TodoRowMetrics.checkboxSize)
    }
}

/// 행에서 **값만으로 그려지는 부분**. `Equatable` 이라 내용이 그대로면 다시 그리지 않는다.
///
/// 체크박스·복원 버튼처럼 동작을 들고 있는 조각은 바깥에 남겼다 —
/// 클로저를 들이면 `Equatable` 합성이 깨져 매번 다시 그린다.
struct TodoCardBody: View, Equatable {
    let title: String
    let isCompleted: Bool
    let chip: TodoDueChip?
    let list: ReminderListOption?
    let swatch: ReminderListSwatch?
    let isLinked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: TodoRowMetrics.contentSpacing) {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
                .strikethrough(isCompleted, color: PopoverChrome.inkTertiary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: 6) {
                if let chip {
                    dueChip(chip)
                }
                if let list, let swatch {
                    ReminderListBadge(title: list.title, swatch: swatch, isLinked: isLinked)
                }
            }
        }
    }

    private func dueChip(_ chip: TodoDueChip) -> some View {
        Label(chip.label, systemImage: "calendar")
            .font(.system(size: 10.5, weight: .heavy, design: .rounded))
            .foregroundStyle(Self.chipForeground(chip.tone))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Self.chipBackground(chip.tone), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private static func chipForeground(_ tone: TodoDueChip.Tone) -> Color {
        switch tone {
        case .over: return Color(red: 0.75, green: 0.34, blue: 0.23)
        case .today: return Color(red: 0.77, green: 0.48, blue: 0.14)
        case .soon: return Color(red: 0.67, green: 0.50, blue: 0.13)
        case .later: return Color(red: 0.54, green: 0.47, blue: 0.40)
        }
    }

    private static func chipBackground(_ tone: TodoDueChip.Tone) -> Color {
        switch tone {
        case .over: return Color(red: 0.98, green: 0.89, blue: 0.86)
        case .today: return Color(red: 0.98, green: 0.90, blue: 0.81)
        case .soon: return Color(red: 0.98, green: 0.94, blue: 0.84)
        case .later: return Color(red: 0.94, green: 0.91, blue: 0.86)
        }
    }
}


struct TodoChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var points: [CGPoint] = []
        var cursor = CGPoint.zero
        var lineHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursor.x > 0, cursor.x + size.width > maxWidth {
                cursor.x = 0
                cursor.y += lineHeight + spacing
                lineHeight = 0
            }
            points.append(cursor)
            cursor.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            usedWidth = max(usedWidth, cursor.x - spacing)
        }

        return (
            CGSize(width: usedWidth, height: cursor.y + lineHeight),
            points
        )
    }
}

/// 트랙패드 가로 스크롤을 스와이프 삭제로 받는다. 세로 스크롤은 목록에 그대로 넘긴다.
private struct TodoTrackpadSwipeCatcher: NSViewRepresentable {
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var onChanged: (CGFloat) -> Void
        var onEnded: (CGFloat) -> Void
        private weak var view: NSView?
        private var monitor: Any?
        private var translation: CGFloat = 0
        private var isHorizontal: Bool?
        private var endWork: DispatchWorkItem?

        init(onChanged: @escaping (CGFloat) -> Void, onEnded: @escaping (CGFloat) -> Void) {
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        func install(for view: NSView) {
            self.view = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func removeMonitor() {
            endWork?.cancel()
            endWork = nil
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            removeMonitor()
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let view, view.window != nil, view.window === event.window else {
                return event
            }
            // 제스처를 잡기 전에는 이 행 위에서 시작한 것만 받는다. 일단 잡은 뒤에는 포인터가
            // 행 밖으로 벗어나도 계속 받아야 «손 뗌»(`.ended`) 을 놓치지 않는다. 그걸 놓치면
            // 아래 안전망 타이머가 대신 끝내 버려 손을 떼지도 않았는데 삭제가 시작된다.
            let location = view.convert(event.locationInWindow, from: nil)
            if isHorizontal != true, !view.bounds.contains(location) { return event }

            let rawDX = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.scrollingDeltaX * 16
            let dx = TodoSwipeDirection.fingerTranslation(
                scrollingDeltaX: rawDX,
                isDirectionInvertedFromDevice: event.isDirectionInvertedFromDevice
            )
            let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 16
            let isUserPhase = event.phase == .began
                || event.phase == .changed
                || event.phase == .mayBegin

            if event.phase == .began {
                isHorizontal = nil
                translation = 0
            }

            if isHorizontal == nil, !isUserPhase {
                return event
            }

            let proposed = min(0, max(translation + dx, -TodoSwipeMetrics.maximumOffset))
            if isHorizontal == nil {
                if abs(dx) > abs(dy), abs(dx) > 0.5, proposed < 0 {
                    isHorizontal = true
                } else if abs(dy) > 0.5 {
                    isHorizontal = false
                    return event
                } else {
                    return event
                }
            }

            guard isHorizontal == true else { return event }

            translation = proposed
            onChanged(translation)

            let ended = event.phase == .ended
                || event.phase == .cancelled
                || event.momentumPhase == .ended
                || event.momentumPhase == .cancelled
            if ended {
                finish()
            } else {
                scheduleFinish()
            }
            return nil
        }

        /// 손을 뗐다는 `.ended` 를 못 받았을 때만 쓰는 **안전망**. 손가락을 얹은 채 멈추면
        /// 트랙패드가 이벤트를 보내지 않으므로, 짧게 잡으면 가만히 있는 것을 손 뗀 것으로 오해한다.
        private static let idleFinishDelay: TimeInterval = 1.0

        private func scheduleFinish() {
            endWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.finish()
            }
            endWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.idleFinishDelay, execute: work)
        }

        private func finish() {
            endWork?.cancel()
            endWork = nil
            let value = translation
            translation = 0
            isHorizontal = nil
            onEnded(value)
        }
    }
}
