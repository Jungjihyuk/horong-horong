import AppKit
import SwiftUI

/// 할 일 목록과 상세.
///
/// **`@Query`·`ModelContext` 를 쓰지 않는다.** 화면은 ViewModel 이 준 값 타입만 본다.
/// 여기 남은 `@State` 는 저장하지 않는 화면 상태뿐이다 — 접힌 그룹, 끌어다 놓는 중인 위치,
/// 스와이프 거리처럼 앱을 껐다 켜면 사라져도 되는 것들.
struct TodoBrowserView: View {
    @State private var viewModel: TodoViewModel

    @State private var collapsedGroups: Set<String> = ["완료", "최근 삭제"]
    @State private var dropTargetTitle: String?
    @State private var colorPickerListID: String?
    @State private var swipeOffset: CGFloat = 0
    @State private var swipingID: UUID?
    @State private var confirmEmptyTrash = false
    @FocusState private var composerFocused: Bool
    @ObservedObject private var listColors = ReminderListColorStore.shared

    init(repository: TodoRepository) {
        _viewModel = State(initialValue: TodoViewModel(repository: repository))
    }

    var body: some View {
        HStack(spacing: 0) {
            listPane
            Divider().overlay(PopoverChrome.divider)
            detailPane
                .frame(width: 300)
        }
        .onAppear {
            viewModel.loadReminderLists()
            viewModel.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            viewModel.dayChanged()
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
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Todo")
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                Text("미리알림에 \(viewModel.linkedCount)개 연동 중")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(PopoverChrome.inkTertiary)
                TextField("할 일 검색", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(width: 220, height: 36)
            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
            )
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var composer: some View {
        HStack(spacing: 9) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(PopoverChrome.accent)
            TextField("할 일 추가 — 오늘로 들어갑니다", text: $viewModel.composerText)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .focused($composerFocused)
                .onSubmit(submit)
        }
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
                    groupPlaceholder("여기로 끌어다 놓으세요")
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
            viewModel.move(idString: id, to: bucket)
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
            }
        }
        .padding(6)
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
                            .opacity(offset < -28 ? 1 : 0)
                    }
                    .frame(width: -offset)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            cardContent(item)
                .offset(x: offset)
        }
        .clipped()
        .background {
            TodoTrackpadSwipeCatcher(
                onChanged: { applySwipe(item, translation: $0) },
                onEnded: { endSwipe(item, translation: $0) }
            )
            .allowsHitTesting(false)
        }
        .highPriorityGesture(swipeGesture(for: item))
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
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .opacity(item.isCompleted ? 0.5 : 1)
        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(viewModel.selected?.id == item.id ? PopoverChrome.accent : Color.clear, lineWidth: 1.5)
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
                detailEditor
                Divider().overlay(PopoverChrome.divider)
                detailFields(item)
                Spacer(minLength: 0)
                detailFooter
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
            TextField("무엇을 할까요", text: $viewModel.titleDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .onChange(of: viewModel.titleDraft) { _, _ in viewModel.draftChanged() }

            TextField("메모", text: $viewModel.noteDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5, design: .rounded))
                .lineLimit(3...8)
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 10)
                .onChange(of: viewModel.noteDraft) { _, _ in viewModel.draftChanged() }
        }
    }

    private func detailFields(_ item: TodoItem) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 9) {
                    fieldLabel("날짜")
                    DatePicker("", selection: whenBinding(for: item), displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 6) {
                    fieldLabel("")
                    dateQuick("오늘", selected: viewModel.isWhen(item, dayOffset: 0)) {
                        viewModel.setWhen(item.id, dayOffset: 0)
                    }
                    dateQuick("내일", selected: viewModel.isWhen(item, dayOffset: 1)) {
                        viewModel.setWhen(item.id, dayOffset: 1)
                    }
                    dateQuick("없음", selected: item.startDate == nil && item.deadline == nil) {
                        viewModel.setWhen(item.id, date: nil)
                    }
                    Spacer(minLength: 0)
                }
            }

            HStack(spacing: 9) {
                fieldLabel("미리알림")
                Button {
                    viewModel.toggleReminder(item)
                } label: {
                    Label(item.isLinkedToReminders ? "연동됨" : "연동 안 함", systemImage: "bell")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(item.isLinkedToReminders ? TodoPalette.linkedInk : PopoverChrome.inkSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(
                            item.isLinkedToReminders ? TodoPalette.linkedFill : PopoverChrome.card,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(item.isLinkedToReminders ? Color.clear : PopoverChrome.border, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
                .disabled(item.isRecentlyDeleted)
            }

            HStack(alignment: .top, spacing: 9) {
                fieldLabel("목록")
                VStack(alignment: .leading, spacing: 5) {
                    if viewModel.reminderLists.isEmpty {
                        Text("미리알림 목록을 불러오는 중")
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(PopoverChrome.inkTertiary)
                    } else {
                        TodoChipFlow(spacing: 6) {
                            ForEach(viewModel.reminderLists) { list in
                                listChip(list, item: item)
                            }
                        }
                    }
                    if !viewModel.reminderStatusMessage.isEmpty {
                        Text(viewModel.reminderStatusMessage)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(PopoverChrome.inkTertiary)
                    }
                }
                .opacity(item.isLinkedToReminders ? 1 : 0.42)
                .allowsHitTesting(item.isLinkedToReminders)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var detailFooter: some View {
        HStack(spacing: 8) {
            footerButton("메모로 확장", systemImage: "arrow.up") {}
                .disabled(true)
                .help("문서로 옮기기는 다음에 열립니다")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .overlay(alignment: .top) {
            Divider().overlay(PopoverChrome.divider)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundStyle(PopoverChrome.inkTertiary)
            .frame(width: 50, alignment: .leading)
    }

    private func dateQuick(_ title: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(selected ? PopoverChrome.accentInk : PopoverChrome.inkSecondary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(
                    selected ? PopoverChrome.accent : PopoverChrome.card,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(selected ? Color.clear : PopoverChrome.border, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func footerButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(PopoverChrome.border, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func listChip(_ list: ReminderListOption, item: TodoItem) -> some View {
        let selected = (item.reminderCalendarIdentifier ?? viewModel.reminderLists.first(where: \.isDefault)?.id) == list.id
        let swatch = listColors.swatch(for: list.id)
        return HStack(spacing: 6) {
            Button {
                colorPickerListID = list.id
            } label: {
                Circle()
                    .fill(swatch.dot)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(PopoverChrome.ink.opacity(0.18), lineWidth: 0.5))
                    .overlay {
                        if colorPickerListID == list.id {
                            Circle()
                                .stroke(PopoverChrome.ink, lineWidth: 1.5)
                                .frame(width: 18, height: 18)
                        }
                    }
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("목록 색 바꾸기")
            .popover(isPresented: Binding(
                get: { colorPickerListID == list.id },
                set: { if !$0 { colorPickerListID = nil } }
            )) {
                listColorPicker(for: list)
            }

            Button {
                viewModel.setReminderList(item.id, listID: list.id)
            } label: {
                Text(list.title)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .foregroundStyle(selected ? swatch.ink : PopoverChrome.inkSecondary)
        .padding(.leading, 6)
        .padding(.trailing, 11)
        .frame(height: 30)
        .background(
            selected ? swatch.wash : PopoverChrome.card,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(selected ? swatch.dot.opacity(0.35) : PopoverChrome.border, lineWidth: 1.5)
        )
        .fixedSize()
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

    private func whenBinding(for item: TodoItem) -> Binding<Date> {
        Binding(
            get: {
                item.deadline ?? item.startDate
                    ?? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
            },
            set: { viewModel.setWhen(item.id, date: $0) }
        )
    }

    private func swipeGesture(for item: TodoItem) -> some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                let horizontal = value.translation.width
                guard abs(horizontal) > abs(value.translation.height) else { return }
                applySwipe(item, translation: horizontal)
            }
            .onEnded { value in
                let horizontal = value.translation.width
                endSwipe(item, translation: abs(horizontal) > abs(value.translation.height) ? horizontal : 0)
            }
    }

    private func applySwipe(_ item: TodoItem, translation: CGFloat) {
        guard translation < 0 else { return }
        swipingID = item.id
        swipeOffset = max(translation, -120)
    }

    private func endSwipe(_ item: TodoItem, translation: CGFloat) {
        let shouldDelete = translation < -72
        withAnimation(.easeOut(duration: 0.18)) {
            swipeOffset = 0
            swipingID = nil
        }
        if shouldDelete {
            viewModel.armPendingDelete(item.id)
        }
    }
}

/// 할 일 화면에서만 쓰는 색. 리터럴이 여러 곳에 흩어져 있어 한 곳에 모았다.
private enum TodoPalette {
    static let danger = Color(red: 0.75, green: 0.34, blue: 0.23)
    static let linkedInk = Color(red: 0.31, green: 0.49, blue: 0.27)
    static let linkedFill = Color(red: 0.89, green: 0.94, blue: 0.87)
}

private struct TodoCheckbox: View {
    let isCompleted: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isCompleted ? Color.clear : Color.black.opacity(0.2), lineWidth: 1.8)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isCompleted ? Color(red: 0.44, green: 0.68, blue: 0.39) : Color.white)
                )
            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 21, height: 21)
    }
}

/// 행에서 **값만으로 그려지는 부분**. `Equatable` 이라 내용이 그대로면 다시 그리지 않는다.
///
/// 체크박스·복원 버튼처럼 동작을 들고 있는 조각은 바깥에 남겼다 —
/// 클로저를 들이면 `Equatable` 합성이 깨져 매번 다시 그린다.
private struct TodoCardBody: View, Equatable {
    let title: String
    let isCompleted: Bool
    let chip: TodoDueChip?
    let list: ReminderListOption?
    let swatch: ReminderListSwatch?
    let isLinked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
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
                    listBadge(list, swatch: swatch)
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

    private func listBadge(_ list: ReminderListOption, swatch: ReminderListSwatch) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(swatch.dot)
                .frame(width: 6, height: 6)
            if isLinked {
                Image(systemName: "bell")
                    .font(.system(size: 9, weight: .bold))
            }
            Text(list.title)
        }
        .font(.system(size: 10.5, weight: .heavy, design: .rounded))
        .foregroundStyle(swatch.ink)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(swatch.wash, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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


private struct TodoChipFlow: Layout {
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
            let location = view.convert(event.locationInWindow, from: nil)
            guard view.bounds.contains(location) else { return event }

            let dx = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.scrollingDeltaX * 16
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

            let proposed = min(0, max(translation - dx, -120))
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

        private func scheduleFinish() {
            endWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.finish()
            }
            endWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
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
