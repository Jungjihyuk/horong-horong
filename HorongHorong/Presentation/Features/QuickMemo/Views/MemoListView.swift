import SwiftUI

struct MemoListView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(AppState.self) private var appState

    @State private var viewModel: MemoListViewModel
    @State private var copiedNoteID: UUID?
    @State private var diaryText = ""
    @State private var todoText = ""
    @State private var editingTodoID: UUID?
    @State private var editText = ""
    @State private var showsMoodPalette = false
    @State private var hostWindow: NSWindow?

    /// 허브 창(내 머리속)의 좌측 분류와 **같은 저장 키**를 본다.
    /// 팝오버에서 보던 분류가 「전체 보기」로 그대로 이어지도록.
    @AppStorage(Constants.AppStorageKey.mindSection)
    private var sectionRaw: String = SecondBrainSection.todo.rawValue
    /// 온보딩이 특정 요소를 가리키는 동안에만 채워진다. 저장값은 건드리지 않는다.
    @State private var onboardingSection: SecondBrainSection?
    @ObservedObject private var highlightCenter = CompanionHighlightCenter.shared

    private var section: SecondBrainSection {
        onboardingSection ?? SecondBrainSection.popoverSection(rawValue: sectionRaw)
    }

    init(
        repository: TodoRepository,
        quickNotes: QuickNoteRepository,
        diary: DiaryRepository,
        clipboard: ClipboardGateway
    ) {
        _viewModel = State(initialValue: MemoListViewModel(
            repository: repository,
            quickNotes: quickNotes,
            diary: diary,
            clipboard: clipboard
        ))
    }

    var body: some View {
        VStack(spacing: 12) {
            MemoSectionBar(selected: section) { sectionRaw = $0.rawValue }
            ScrollView {
                selectedSection
                    .padding(.trailing, 10)
                    .padding(.bottom, 4)
            }
            .popoverScrollbar()
        }
        .configureHostWindow { hostWindow = $0 }
        .onAppear { viewModel.reload() }
        .task { await viewModel.loadReminderLists() }
        .onChange(of: highlightCenter.target) { _, target in
            // 온보딩이 가리키는 앵커가 사는 섹션으로만 잠깐 옮긴다. 저장값은 그대로 둔다 —
            // 안내를 한 번 봤다는 이유로 허브의 분류 선택까지 바뀌면 안 된다.
            onboardingSection = target == "memo.new" ? .todo : nil
        }
    }

    @ViewBuilder
    private var selectedSection: some View {
        switch section {
        case .quick: quickNoteSection
        case .diary: diarySection
        case .todo: todoSection
        case .knowledge, .works, .refs: comingSoonPanel(section)
        }
    }

    /// 지금 보고 있는 분류를 허브 창에서 크게 연다.
    ///
    /// 분류 선택 줄 옆에 아이콘만 두었더니 무슨 버튼인지 알아볼 수 없었다. 글자를 되살리되
    /// **그 분류의 머리말 줄**로 내렸다 — «Quick Note 를 전체 보기» 라는 뜻이 위치로 드러나고,
    /// 다섯 칸도 폭을 온전히 나눠 쓴다.
    private var expandButton: some View {
        Button {
            HubWindowPresenter.present(
                tab: .memo,
                appState: appState,
                popoverWindow: hostWindow,
                openWindow: openWindow
            )
        } label: {
            HStack(spacing: 3) {
                Text("전체 보기")
                Image(systemName: "arrow.up.forward")
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(PopoverChrome.inkSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                PopoverChrome.surfaceAlt,
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("허브 창에서 크게 보기")
    }

    private var quickNoteSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionHeader("Quick Note", shortcut: "⌘⇧N")
            if viewModel.recentNotes.isEmpty {
                compactEmpty("아직 빠른 기록이 없습니다")
            } else {
                ForEach(viewModel.recentNotes) { note in
                    Button { copy(note) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: copiedNoteID == note.id ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(PopoverChrome.accent)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.title)
                                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(PopoverChrome.ink)
                                    .lineLimit(1)
                                Text(copiedNoteID == note.id ? "복사됨" : note.createdAt.formatted(.relative(presentation: .named)))
                                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(copiedNoteID == note.id ? PopoverChrome.accent : PopoverChrome.inkTertiary)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("전체 내용 복사")
                }
            }
        }
        .popoverCard(padding: 11)
    }

    private var diarySection: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 9) {
                sectionHeader("Diary", shortcut: "오늘")
                HStack(spacing: 7) {
                    TextField("기억할 사건이나 #키워드", text: $diaryText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5, design: .rounded))
                        .onSubmit { submitDiary(now: context.date) }
                    if !diaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("추가") { submitDiary(now: context.date) }
                            .buttonStyle(.plain)
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundStyle(PopoverChrome.accent)
                    }
                }
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(PopoverChrome.surfaceAlt, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text("\(viewModel.moodSlot(now: context.date).title) 감정")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                    HStack(spacing: 5) {
                        ForEach(MemoListViewModel.representativeMoods) { mood in
                            moodButton(mood, now: context.date)
                        }
                        Button("•••") { showsMoodPalette = true }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(PopoverChrome.inkSecondary)
                            .frame(width: 27, height: 27)
                            .background(PopoverChrome.surfaceAlt, in: Circle())
                            .popover(isPresented: $showsMoodPalette) {
                                CompactMoodPalette(
                                    selected: viewModel.currentMood(now: context.date),
                                    onSelect: { mood in
                                        viewModel.setMood(mood, now: context.date)
                                        showsMoodPalette = false
                                    }
                                )
                            }
                    }
                }
            }
        }
        .popoverCard(padding: 11)
    }

    private var todoSection: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeline = viewModel.timeline(now: context.date)
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Todo", shortcut: "오늘 \(timeline.scheduled.count + timeline.unscheduled.count)")
                todoComposer(now: context.date)
                if let message = viewModel.todoSaveMessage {
                    Text(message)
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(PopoverChrome.accent)
                }
                if timeline.isEmpty {
                    compactEmpty("오늘 할 일이 없습니다")
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(timeline.scheduled) { item in
                            if timeline.nextID == item.id { nowMarker }
                            todoRow(item)
                        }
                        if timeline.nextID == nil, !timeline.scheduled.isEmpty { nowMarker }
                        if !timeline.unscheduled.isEmpty {
                            Text("시간 미정")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(PopoverChrome.inkTertiary)
                                .padding(.leading, 34)
                                .padding(.top, 8)
                                .padding(.bottom, 1)
                            ForEach(timeline.unscheduled) { todoRow($0) }
                        }
                    }
                }
            }
        }
        .popoverCard(padding: 11)
    }

    /// 아직 화면이 없는 분류를 골랐을 때. 고른 하나만 그린다.
    private func comingSoonPanel(_ item: SecondBrainSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(item.label, shortcut: "준비 중")
            Text(item.subtitle)
                .font(.system(size: 10.5, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
            Text("아직 팝오버에서는 볼 수 없어요. 「전체 보기」에서 열어 주세요.")
                .font(.system(size: 10.5, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .popoverCard(padding: 11)
        .accessibilityLabel("\(item.label), 준비 중")
    }

    /// 힌트(단축키·개수)는 제목을 꾸미는 말이라 제목 옆에 붙인다.
    /// 오른쪽 끝은 «전체 보기» 자리다 — 지금 보고 있는 분류를 크게 여는 동작.
    private func sectionHeader(_ title: String, shortcut: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
            Text(shortcut)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
            Spacer(minLength: 4)
            expandButton
        }
    }

    private func compactEmpty(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, design: .rounded))
            .foregroundStyle(PopoverChrome.inkTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
    }

    private func moodButton(_ mood: DiaryMood, now: Date) -> some View {
        let selected = viewModel.currentMood(now: now) == mood
        return Button { viewModel.setMood(mood, now: now) } label: {
            Text(mood.emoji)
                .font(.system(size: 14))
                .frame(width: 27, height: 27)
                .background(selected ? PopoverChrome.accentSoft : PopoverChrome.surfaceAlt, in: Circle())
                .overlay(Circle().stroke(selected ? PopoverChrome.accent : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .help(mood.rawValue)
    }

    private func todoComposer(now: Date) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "plus").font(.system(size: 10, weight: .bold)).foregroundStyle(PopoverChrome.accent)
            TextField("예: 오후 2시부터 3시까지 회의", text: $todoText)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5, design: .rounded))
                .onSubmit { submitTodo(now: now) }
            if !todoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("추가") { submitTodo(now: now) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.accent)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(PopoverChrome.surfaceAlt, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .companionHighlight("memo.new")
    }

    /// 지금 시각이 어디쯤인지 긋는 선. 점은 왼쪽 알약 열(24pt) 한가운데에 놓아
    /// 시간축 위에 걸치게 한다 — 옆으로 비켜 있으면 그냥 구분선으로 보인다.
    private var nowMarker: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(PopoverChrome.accent)
                .frame(width: 7, height: 7)
                .frame(width: 24)
            Text("지금")
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.accent)
            Rectangle()
                .fill(PopoverChrome.accent.opacity(0.3))
                .frame(height: 1)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder private func todoRow(_ item: TodoTimelineItem) -> some View {
        if editingTodoID == item.id {
            VStack(spacing: 5) {
                TextField("할 일", text: $editText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { finishEditing(item.id) }
                HStack {
                    Spacer()
                    Button("취소") { editingTodoID = nil }.controlSize(.mini)
                    Button("저장") { finishEditing(item.id) }.controlSize(.mini)
                }
            }
            .padding(.vertical, 5)
        } else {
            TodoTimelineRow(
                item: item,
                reminderTitle: viewModel.reminderList(for: item.todo)?.title,
                onToggle: { viewModel.toggleCompleted(item.todo) },
                onEdit: {
                    editText = item.todo.content
                    editingTodoID = item.id
                },
                onDelete: { viewModel.delete(item.id) }
            )
            .equatable()
        }
    }

    private func copy(_ note: QuickNoteItem) {
        guard viewModel.copy(note) else { return }
        copiedNoteID = note.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            if copiedNoteID == note.id { copiedNoteID = nil }
        }
    }

    private func submitDiary(now: Date) {
        guard viewModel.appendDiaryCue(diaryText, now: now) else { return }
        diaryText = ""
    }

    private func submitTodo(now: Date) {
        guard viewModel.submitComposer(todoText, now: now) else { return }
        todoText = ""
    }

    private func finishEditing(_ id: UUID) {
        viewModel.updateContent(id, content: editText)
        editingTodoID = nil
    }
}

/// 팝오버 「기록」 탭의 분류 선택 줄.
///
/// 허브 창은 220pt rail 에 세로로 놓지만 팝오버는 폭이 360pt 라 가로 다섯 칸으로 눕힌다.
/// 색과 선택 표시는 팝오버 상단 탭바(`MenuBarPopover.tabBar`)와 같은 토큰을 써서
/// «위쪽 탭 안의 작은 탭» 으로 읽히게 한다.
private struct MemoSectionBar: View {
    let selected: SecondBrainSection
    let onSelect: (SecondBrainSection) -> Void

    var body: some View {
        // 겉 상자를 씌우지 않는다. 바로 위 탭바가 이미 `surfaceAlt` 띠라, 8pt 아래에 같은 띠를
        // 하나 더 두면 «탭 속의 탭 속의 탭» 처럼 겹쳐 보인다. 고른 칸의 색만으로 충분하다.
        HStack(spacing: 2) {
            ForEach(SecondBrainSection.popoverSections) { item in
                MemoSectionBarItem(item: item, isSelected: item == selected) {
                    onSelect(item)
                }
                .equatable()
            }
        }
    }
}

/// 선택 줄의 한 칸.
///
/// **독립 구조체인 이유**: 마우스가 올라온 칸만 따로 기억해야 하는데, 부모의 함수 안에서는
/// 칸마다 `@State` 를 가질 수 없다. 값만 받고 `Equatable` 이라 다른 칸이 바뀌어도 다시 그리지 않는다
/// (허브의 `SecondBrainRailItem` 과 같은 이유).
private struct MemoSectionBarItem: View, Equatable {
    let item: SecondBrainSection
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    /// 동작 클로저는 비교에서 뺀다. 넣으면 값이 그대로여도 매번 다르다고 판정된다.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item == rhs.item && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: item.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    // 아직 화면이 없는 분류는 옅게 — 눌러 볼 수는 있되 빈 곳임을 미리 알린다.
                    .opacity(item.isComingSoon ? 0.5 : 1)
                Text(item.shortLabel)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            // 고른 칸은 **옅은** 강조색이다. 바로 위 팝오버 탭바가 진한 강조색을 꽉 채워 쓰는데,
            // 한 단계 아래 칸까지 같은 세기로 칠하면 둘 중 어느 것이 지금 화면인지 헷갈린다.
            .foregroundStyle(isSelected ? PopoverChrome.accent : PopoverChrome.inkSecondary)
            .background(
                isSelected
                    ? PopoverChrome.accentSoft
                    : (isHovering ? PopoverChrome.ink.opacity(0.06) : .clear),
                in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous)
                    .stroke(isSelected ? PopoverChrome.accent.opacity(0.35) : .clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help(item.subtitle)
        .accessibilityLabel("\(item.label), \(item.subtitle)")
    }
}

private struct CompactMoodPalette: View {
    let selected: DiaryMood?
    let onSelect: (DiaryMood) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(DiaryMoodGroup.allCases) { group in
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(group.emoji) \(group.title)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))], spacing: 5) {
                            ForEach(group.moods) { mood in
                                Button { onSelect(mood) } label: {
                                    Text("\(mood.emoji) \(mood.rawValue)")
                                        .font(.system(size: 10, weight: selected == mood ? .bold : .regular, design: .rounded))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 5)
                                        .background(selected == mood ? PopoverChrome.accentSoft : PopoverChrome.surfaceAlt, in: RoundedRectangle(cornerRadius: 7))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
        .frame(width: 300, height: 330)
        .background(PopoverChrome.surface)
    }
}
