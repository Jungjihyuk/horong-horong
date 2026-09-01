import AppKit
import SwiftUI
import SwiftData

struct TodoBrowserView: View {
    @Environment(\.modelContext) private var modelContext
    // 거르는 일을 DB 에 시킨다. 예전에는 전량을 가져와 Swift 에서 걸렀다 —
    // Todo 를 보는데 Quick Note·References 까지 전부 실체화됐다.
    // `resolvedSection` 은 계산 프로퍼티라 SQL 로 번역되지 않으므로 저장 컬럼을 쓴다.
    @Query(
        filter: #Predicate<Memo> { $0.sectionRaw == "todo" },
        sort: \Memo.createdAt,
        order: .reverse
    )
    private var allMemos: [Memo]

    @State private var selectedID: UUID?
    @State private var searchText = ""
    @State private var composerText = ""
    @State private var titleDraft = ""
    @State private var noteDraft = ""
    @State private var collapsedGroups: Set<String> = ["완료", "최근 삭제"]
    @State private var todayReferenceDate = Date()
    @State private var reminderLists: [ReminderListOption] = []
    @State private var reminderStatusMessage = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var dropTargetTitle: String?
    @State private var colorPickerListID: String?
    @State private var pendingDeleteID: UUID?
    @State private var pendingDeleteTask: Task<Void, Never>?
    @State private var swipeOffset: CGFloat = 0
    @State private var swipingID: UUID?
    @State private var confirmEmptyTrash = false
    @FocusState private var composerFocused: Bool
    @ObservedObject private var listColors = ReminderListColorStore.shared

    /// 한 번의 body 평가에서 쓰는 모든 파생 값.
    ///
    /// 계산 프로퍼티로 두면 소비처마다 `allMemos` 를 다시 전량 순회한다. 실제로 그랬다 —
    /// `grouped()` 5개가 각각 `todos` 를 돌고, `visibleItems` 가 그 5개를 또 합치고,
    /// `.onChange(of:)` 가 body 평가마다 그 파이프라인을 통째로 한 번 더 돌려
    /// **body 1회당 전량 순회 12~17회 + 전량 정렬 10회**가 됐다.
    ///
    /// 커밋 `158018d` 가 메모 브라우저에서 같은 구조를 같은 방법으로 없앴다.
    private struct Snapshot {
        var overdue: [Memo] = []
        var today: [Memo] = []
        var upcoming: [Memo] = []
        var someday: [Memo] = []
        var completed: [Memo] = []
        var recentlyDeleted: [Memo] = []
        var linkedCount = 0
        /// 선택이 목록에서 사라졌는지 보는 용도. `.onChange` 비교값을 body 평가마다
        /// 새로 할당하지 않도록 스냅샷 안에서 한 번만 만든다.
        var visibleIDs: [UUID] = []
        var firstVisible: Memo?
        var selected: Memo?
    }

    /// `allMemos` 를 **한 번만** 순회하며 5개 버킷·최근 삭제·연동 수를 함께 만든다.
    private func makeSnapshot() -> Snapshot {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var snapshot = Snapshot()

        for memo in allMemos {
            // 섹션 확인은 `@Query` 의 술어가 이미 했다.
            if !query.isEmpty, !memo.content.localizedCaseInsensitiveContains(query) { continue }

            // 최근 삭제는 아카이브 여부를 보지 않는다 — 통합 전 `recentlyDeletedItems` 와 같다.
            if memo.isRecentlyDeleted {
                snapshot.recentlyDeleted.append(memo)
                continue
            }
            guard !memo.isArchivedValue else { continue }

            if !memo.isCompletedValue, memo.isLinkedToRemindersValue {
                snapshot.linkedCount += 1
            }

            switch TodoBucket.of(
                startDate: memo.startDate,
                deadline: memo.deadline,
                isCompleted: memo.isCompletedValue,
                now: todayReferenceDate
            ) {
            case .overdue:   snapshot.overdue.append(memo)
            case .today:     snapshot.today.append(memo)
            case .upcoming:  snapshot.upcoming.append(memo)
            case .someday:   snapshot.someday.append(memo)
            case .completed: snapshot.completed.append(memo)
            }
        }

        // 정렬은 버킷마다 한 번씩. 전량을 5번 정렬하던 것보다 다루는 배열이 훨씬 작다.
        func byDue(_ items: [Memo]) -> [Memo] {
            items.sorted {
                let left = $0.deadline ?? $0.startDate ?? .distantFuture
                let right = $1.deadline ?? $1.startDate ?? .distantFuture
                return left < right
            }
        }
        snapshot.overdue = byDue(snapshot.overdue)
        snapshot.today = byDue(snapshot.today)
        snapshot.upcoming = byDue(snapshot.upcoming)
        snapshot.someday = byDue(snapshot.someday)
        snapshot.completed = byDue(snapshot.completed)
        snapshot.recentlyDeleted.sort { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }

        let visible = snapshot.overdue + snapshot.today + snapshot.upcoming
            + snapshot.someday + snapshot.completed
        snapshot.visibleIDs = visible.map(\.id) + snapshot.recentlyDeleted.map(\.id)
        snapshot.firstVisible = visible.first

        if let selectedID {
            snapshot.selected = visible.first { $0.id == selectedID }
                ?? snapshot.recentlyDeleted.first { $0.id == selectedID }
        }
        snapshot.selected = snapshot.selected ?? visible.first

        return snapshot
    }

    /// 이벤트 처리용. 렌더 경로에서는 `Snapshot.selected` 를 쓴다 —
    /// 여기서 스냅샷을 다시 만드는 것은 선택 전환·창 닫기처럼 드문 시점뿐이다.
    private func selectedMemo() -> Memo? {
        makeSnapshot().selected
    }

    var body: some View {
        // body 안에서 딱 한 번 만들고 자식들에게 넘긴다. 각자 계산하게 두면 팬아웃이 돌아온다.
        let snapshot = makeSnapshot()
        HStack(spacing: 0) {
            listPane(snapshot)
            Divider().overlay(PopoverChrome.divider)
            detailPane(snapshot.selected)
                .frame(width: 300)
        }
        .onAppear {
            todayReferenceDate = Date()
            loadReminderLists()
            selectedID = snapshot.selected?.id
            loadDrafts()
        }
        .onChange(of: selectedID) { _, _ in
            flush()
            loadDrafts()
        }
        .onChange(of: snapshot.visibleIDs) { _, ids in
            if let selectedID, ids.contains(selectedID) { return }
            selectedID = snapshot.firstVisible?.id
            loadDrafts()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            todayReferenceDate = Date()
        }
        .onDisappear {
            flush()
            commitPendingDeleteIfNeeded()
        }
        .confirmationDialog(
            "최근 삭제의 할 일을 완전히 지울까요? 되돌릴 수 없습니다.",
            isPresented: $confirmEmptyTrash,
            titleVisibility: .visible
        ) {
            Button("비우기", role: .destructive) {
                emptyRecentlyDeleted()
            }
            Button("취소", role: .cancel) {}
        }
    }

    private func listPane(_ snapshot: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(linkedCount: snapshot.linkedCount)
            composer
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    group(bucket: .overdue, items: snapshot.overdue, hint: nil)
                    group(bucket: .today, items: snapshot.today, hint: nil)
                    group(bucket: .upcoming, items: snapshot.upcoming, hint: nil)
                    group(bucket: .someday, items: snapshot.someday, hint: "날짜 없음")
                    group(bucket: .completed, items: snapshot.completed, hint: nil)
                    recentlyDeletedGroup(snapshot.recentlyDeleted)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
        }
        .frame(maxWidth: .infinity)
        .background(PopoverChrome.surface)
    }

    private func header(linkedCount: Int) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Todo")
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                Text("미리알림에 \(linkedCount)개 연동 중")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(PopoverChrome.inkTertiary)
                TextField("할 일 검색", text: $searchText)
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
            TextField("할 일 추가 — 오늘로 들어갑니다", text: $composerText)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .focused($composerFocused)
                .onSubmit(submitComposer)
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

    private func group(bucket: TodoBucket, items: [Memo], hint: String?) -> some View {
        let title = bucket.title
        let expanded = !collapsedGroups.contains(title)
        let isDropTarget = dropTargetTitle == title
        // **LazyVStack 이어야 한다.** 평범한 VStack 이면 이 그룹의 행을 전부 즉시 만든다.
        // 바깥 LazyVStack 은 «그룹 컨테이너» 6개만 지연 생성하므로, 컨테이너가 만들어지는
        // 순간 안쪽 행 수천 개가 한꺼번에 그려졌다
        // (실측 2026-09-02: todo 5,235건에서 그리기에만 1,235ms · 행당 0.34ms).
        return LazyVStack(alignment: .leading, spacing: 7) {
            Button {
                if expanded {
                    collapsedGroups.insert(title)
                } else {
                    collapsedGroups.remove(title)
                }
            } label: {
                HStack(spacing: 7) {
                    Text(title)
                        .font(.system(size: 11.5, weight: .heavy, design: .rounded))
                    Text("\(items.count)")
                        .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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

            if expanded {
                if items.isEmpty {
                    Text("여기로 끌어다 놓으세요")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 6)
                } else {
                    ForEach(items) { memo in
                        if pendingDeleteID == memo.id {
                            pendingDeleteRow(memo)
                        } else {
                            todoRow(memo)
                        }
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
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first else { return false }
            move(idString: id, to: bucket)
            return true
        } isTargeted: { hovering in
            if hovering {
                dropTargetTitle = title
            } else if dropTargetTitle == title {
                dropTargetTitle = nil
            }
        }
    }

    private func recentlyDeletedGroup(_ items: [Memo]) -> some View {
        let title = "최근 삭제"
        let expanded = !collapsedGroups.contains(title)
        return LazyVStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Button {
                    if expanded {
                        collapsedGroups.insert(title)
                    } else {
                        collapsedGroups.remove(title)
                    }
                } label: {
                    HStack(spacing: 7) {
                        Text(title)
                            .font(.system(size: 11.5, weight: .heavy, design: .rounded))
                        Text("\(items.count)")
                            .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(PopoverChrome.inkTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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
                    .foregroundStyle(Color(red: 0.75, green: 0.34, blue: 0.23))
                }
            }
            .padding(.top, 8)

            if expanded {
                if items.isEmpty {
                    Text("삭제한 할 일이 여기 모입니다")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 6)
                } else {
                    ForEach(items) { memo in
                        if pendingDeleteID == memo.id {
                            pendingDeleteRow(memo)
                        } else {
                            todoRow(memo)
                        }
                    }
                }
            }
        }
        .padding(6)
    }

    private func pendingDeleteRow(_ memo: Memo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "trash")
                .font(.system(size: 12, weight: .bold))
            Text("삭제됨")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text(displayTitle(memo))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .lineLimit(1)
                .foregroundStyle(PopoverChrome.inkTertiary)
            Spacer(minLength: 8)
            Button("취소") {
                cancelPendingDelete()
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
        .background(
            Color(red: 0.75, green: 0.34, blue: 0.23),
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
    }

    private func todoRow(_ memo: Memo) -> some View {
        let chip = TodoDueChip.of(
            startDate: memo.startDate,
            deadline: memo.deadline,
            now: todayReferenceDate
        )
        let list = reminderList(for: memo)
        let offset = swipingID == memo.id ? swipeOffset : 0
        return ZStack(alignment: .trailing) {
            if offset < -0.5 {
                Color(red: 0.75, green: 0.34, blue: 0.23)
                    .overlay {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .opacity(offset < -28 ? 1 : 0)
                    }
                    .frame(width: -offset)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            cardContent(memo, chip: chip, list: list)
                .offset(x: offset)
        }
        .clipped()
        .background {
            TodoTrackpadSwipeCatcher(
                onChanged: { applySwipe(memo, translation: $0) },
                onEnded: { endSwipe(memo, translation: $0) }
            )
            .allowsHitTesting(false)
        }
        .highPriorityGesture(swipeGesture(for: memo))
    }

    private func cardContent(_ memo: Memo, chip: TodoDueChip?, list: ReminderListOption?) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Button {
                toggleCompleted(memo)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(memo.isCompletedValue ? Color.clear : Color.black.opacity(0.2), lineWidth: 1.8)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(memo.isCompletedValue ? Color(red: 0.44, green: 0.68, blue: 0.39) : Color.white)
                        )
                    if memo.isCompletedValue {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 21, height: 21)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 7) {
                Text(displayTitle(memo))
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                    .strikethrough(memo.isCompletedValue, color: PopoverChrome.inkTertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    if let chip {
                        dueChip(chip)
                    }
                    if let list {
                        listBadge(list, linked: memo.isLinkedToRemindersValue)
                    }
                }
            }
            Spacer(minLength: 0)
            if memo.isRecentlyDeleted {
                Button("복원") {
                    restore(memo)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.accent)
                .padding(.top, 1)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .opacity(memo.isCompletedValue ? 0.5 : 1)
        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(selectedID == memo.id ? PopoverChrome.accent : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { selectedID = memo.id }
        .draggable(memo.id.uuidString) {
            Text(displayTitle(memo))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: Color.black.opacity(0.12), radius: 8, y: 3)
        }
    }

    private func listBadge(_ list: ReminderListOption, linked: Bool) -> some View {
        let swatch = listColors.swatch(for: list.id)
        return HStack(spacing: 5) {
            Circle()
                .fill(swatch.dot)
                .frame(width: 6, height: 6)
            if linked {
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

    private func dueChip(_ chip: TodoDueChip) -> some View {
        Label(chip.label, systemImage: "calendar")
            .font(.system(size: 10.5, weight: .heavy, design: .rounded))
            .foregroundStyle(chipForeground(chip.tone))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(chipBackground(chip.tone), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    @ViewBuilder
    private func detailPane(_ selected: Memo?) -> some View {
        if let memo = selected {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(memo.isRecentlyDeleted ? "최근 삭제" : "할 일")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                    Spacer()
                    if memo.isRecentlyDeleted {
                        Button("복원") {
                            restore(memo)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.accent)
                    }
                    Button {
                        armPendingDelete(memo)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Color(red: 0.75, green: 0.34, blue: 0.23))
                    }
                    .buttonStyle(.plain)
                    .help(memo.isRecentlyDeleted ? "완전히 삭제" : "삭제")
                }
                .padding(.horizontal, 16)
                .padding(.top, 13)
                .padding(.bottom, 8)

                TextField("무엇을 할까요", text: $titleDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .onChange(of: titleDraft) { _, _ in writeContent(of: memo) }

                TextField("메모", text: $noteDraft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5, design: .rounded))
                    .lineLimit(3...8)
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                    .onChange(of: noteDraft) { _, _ in writeContent(of: memo) }

                Divider().overlay(PopoverChrome.divider)

                VStack(alignment: .leading, spacing: 11) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 9) {
                            fieldLabel("날짜")
                            DatePicker(
                                "",
                                selection: whenBinding(for: memo),
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            Spacer(minLength: 0)
                        }
                        HStack(spacing: 6) {
                            fieldLabel("")
                            dateQuick("오늘", selected: isWhen(memo, offset: 0)) { setWhen(memo, dayOffset: 0) }
                            dateQuick("내일", selected: isWhen(memo, offset: 1)) { setWhen(memo, dayOffset: 1) }
                            dateQuick("없음", selected: memo.startDate == nil && memo.deadline == nil) { setWhen(memo, dayOffset: nil) }
                            Spacer(minLength: 0)
                        }
                    }

                    HStack(spacing: 9) {
                        fieldLabel("미리알림")
                        Button {
                            toggleReminder(memo)
                        } label: {
                            Label(
                                memo.isLinkedToRemindersValue ? "연동됨" : "연동 안 함",
                                systemImage: "bell"
                            )
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(memo.isLinkedToRemindersValue ? Color(red: 0.31, green: 0.49, blue: 0.27) : PopoverChrome.inkSecondary)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(
                                memo.isLinkedToRemindersValue
                                    ? Color(red: 0.89, green: 0.94, blue: 0.87)
                                    : PopoverChrome.card,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(memo.isLinkedToRemindersValue ? Color.clear : PopoverChrome.border, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(memo.isRecentlyDeleted)
                    }

                    HStack(alignment: .top, spacing: 9) {
                        fieldLabel("목록")
                        VStack(alignment: .leading, spacing: 5) {
                            if reminderLists.isEmpty {
                                Text("미리알림 목록을 불러오는 중")
                                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(PopoverChrome.inkTertiary)
                            } else {
                                TodoChipFlow(spacing: 6) {
                                    ForEach(reminderLists) { list in
                                        listChip(list, memo: memo)
                                    }
                                }
                            }
                            if !reminderStatusMessage.isEmpty {
                                Text(reminderStatusMessage)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(PopoverChrome.inkTertiary)
                            }
                        }
                        .opacity(memo.isLinkedToRemindersValue ? 1 : 0.42)
                        .allowsHitTesting(memo.isLinkedToRemindersValue)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)

                Spacer(minLength: 0)

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

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundStyle(PopoverChrome.inkTertiary)
            .frame(width: 50, alignment: .leading)
    }

    private func dateQuick(_ title: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(selected ? PopoverChrome.accent : PopoverChrome.inkSecondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(
                    selected ? PopoverChrome.accentSoft : PopoverChrome.card,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(selected ? Color.clear : PopoverChrome.border, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private func isWhen(_ memo: Memo, offset: Int) -> Bool {
        guard let basis = memo.deadline ?? memo.startDate else { return false }
        let target = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        return Calendar.current.isDate(basis, inSameDayAs: target)
    }

    private func listChip(_ list: ReminderListOption, memo: Memo) -> some View {
        let selected = (memo.reminderCalendarIdentifier ?? reminderLists.first(where: \.isDefault)?.id) == list.id
        let swatch = listColors.swatch(for: list.id)
        return HStack(spacing: 6) {
            Button {
                colorPickerListID = list.id
            } label: {
                Circle()
                    .fill(swatch.dot)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle().stroke(PopoverChrome.ink.opacity(0.18), lineWidth: 0.5)
                    )
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
                memo.reminderCalendarIdentifier = list.id
                persist(memo, syncLinkedReminder: true)
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
                                .overlay(
                                    Circle().stroke(PopoverChrome.ink.opacity(0.16), lineWidth: 0.5)
                                )
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

    private func submitComposer() {
        let title = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let memo = Memo(content: title, section: .todo)
        memo.startDate = daytime(Date(), hour: 9)
        modelContext.insert(memo)
        persist(memo)
        composerText = ""
        selectedID = memo.id
        composerFocused = true
    }

    private func whenBinding(for memo: Memo) -> Binding<Date> {
        Binding(
            get: { memo.deadline ?? memo.startDate ?? daytime(Date(), hour: 9) },
            set: { date in
                applyWhen(memo, date)
            }
        )
    }

    private func setWhen(_ memo: Memo, dayOffset: Int?) {
        guard let dayOffset else {
            memo.startDate = nil
            memo.deadline = nil
            persist(memo, syncLinkedReminder: true)
            return
        }
        let day = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
        applyWhen(memo, daytime(day, hour: 9))
    }

    private func applyWhen(_ memo: Memo, _ date: Date) {
        if memo.deadline != nil {
            memo.setDeadline(date)
        } else {
            memo.setStartDate(date)
        }
        persist(memo, syncLinkedReminder: true)
    }

    private func daytime(_ day: Date, hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }

    private func toggleReminder(_ memo: Memo) {
        if memo.isLinkedToRemindersValue {
            unlinkReminder(memo)
        } else {
            loadReminderLists()
            linkReminder(memo)
        }
    }

    private func toggleCompleted(_ memo: Memo) {
        memo.isCompletedValue.toggle()
        if memo.isCompletedValue {
            memo.isPinned = false
            NotificationManager.shared.cancel(identifier: localReminderIdentifier(for: memo))
        }
        persist(memo, syncLinkedReminder: true)
    }

    private func swipeGesture(for memo: Memo) -> some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) else { return }
                applySwipe(memo, translation: horizontal)
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                endSwipe(
                    memo,
                    translation: abs(horizontal) > abs(vertical) ? horizontal : 0
                )
            }
    }

    private func applySwipe(_ memo: Memo, translation: CGFloat) {
        guard translation < 0 else { return }
        swipingID = memo.id
        swipeOffset = max(translation, -120)
    }

    private func endSwipe(_ memo: Memo, translation: CGFloat) {
        let shouldDelete = translation < -72
        withAnimation(.easeOut(duration: 0.18)) {
            swipeOffset = 0
            swipingID = nil
        }
        if shouldDelete {
            armPendingDelete(memo)
        }
    }

    private func armPendingDelete(_ memo: Memo) {
        commitPendingDeleteIfNeeded()
        if selectedID == memo.id { selectedID = nil }
        withAnimation(.easeInOut(duration: 0.18)) {
            pendingDeleteID = memo.id
        }
        pendingDeleteTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1_500))
            guard !Task.isCancelled, pendingDeleteID == memo.id else { return }
            pendingDeleteID = nil
            pendingDeleteTask = nil
            finishDelete(memo)
        }
    }

    private func cancelPendingDelete() {
        pendingDeleteTask?.cancel()
        pendingDeleteTask = nil
        withAnimation(.easeInOut(duration: 0.18)) {
            pendingDeleteID = nil
        }
    }

    private func commitPendingDeleteIfNeeded() {
        let id = pendingDeleteID
        pendingDeleteTask?.cancel()
        pendingDeleteTask = nil
        pendingDeleteID = nil
        guard let id, let memo = allMemos.first(where: { $0.id == id }) else { return }
        finishDelete(memo)
    }

    private func finishDelete(_ memo: Memo) {
        if memo.isRecentlyDeleted {
            deletePermanently(memo)
        } else {
            moveToRecentlyDeleted(memo)
        }
    }

    private func moveToRecentlyDeleted(_ memo: Memo) {
        if selectedID == memo.id { selectedID = nil }
        unlinkNotificationsAndReminders(memo)
        memo.deletedAt = Date()
        memo.updatedAt = Date()
        try? modelContext.save()
    }

    private func restore(_ memo: Memo) {
        memo.deletedAt = nil
        persist(memo)
        collapsedGroups.remove(memo.todoBucket.title)
        selectedID = memo.id
    }

    private func emptyRecentlyDeleted() {
        let items = makeSnapshot().recentlyDeleted
        for memo in items {
            deletePermanently(memo)
        }
    }

    private func unlinkNotificationsAndReminders(_ memo: Memo) {
        NotificationManager.shared.cancel(identifier: localReminderIdentifier(for: memo))
        guard memo.isLinkedToRemindersValue else { return }
        try? MemoReminderLinkService.shared.removeReminder(for: memo)
        memo.isLinkedToRemindersValue = false
        memo.reminderIdentifier = nil
    }

    private func deletePermanently(_ memo: Memo) {
        if selectedID == memo.id { selectedID = nil }
        if pendingDeleteID == memo.id {
            pendingDeleteTask?.cancel()
            pendingDeleteTask = nil
            pendingDeleteID = nil
        }
        unlinkNotificationsAndReminders(memo)
        modelContext.delete(memo)
        try? modelContext.save()
    }

    private func loadDrafts() {
        guard let memo = selectedMemo() else {
            titleDraft = ""
            noteDraft = ""
            return
        }
        let parts = splitContent(memo.content)
        titleDraft = parts.title
        noteDraft = parts.note
    }

    private func writeContent(of memo: Memo) {
        let joined: String
        let note = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if note.isEmpty {
            joined = titleDraft
        } else {
            joined = titleDraft + "\n" + noteDraft
        }
        memo.content = joined
        scheduleSave(memo)
    }

    private func splitContent(_ content: String) -> (title: String, note: String) {
        if let index = content.firstIndex(of: "\n") {
            return (String(content[..<index]), String(content[content.index(after: index)...]))
        }
        return (content, "")
    }

    private func displayTitle(_ memo: Memo) -> String {
        let title = splitContent(memo.content).title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "제목 없음" : title
    }

    private func reminderList(for memo: Memo) -> ReminderListOption? {
        if let id = memo.reminderCalendarIdentifier,
           let list = reminderLists.first(where: { $0.id == id }) {
            return list
        }
        if memo.isLinkedToRemindersValue {
            return reminderLists.first(where: \.isDefault)
        }
        return nil
    }

    private func move(idString: String, to bucket: TodoBucket) {
        guard let id = UUID(uuidString: idString),
              let memo = allMemos.first(where: { $0.id == id }) else { return }
        memo.deletedAt = nil
        let placed = TodoBucket.placement(
            into: bucket,
            startDate: memo.startDate,
            deadline: memo.deadline,
            isCompleted: memo.isCompletedValue,
            now: todayReferenceDate
        )
        memo.isCompletedValue = placed.isCompleted
        if placed.isCompleted {
            memo.isPinned = false
            NotificationManager.shared.cancel(identifier: localReminderIdentifier(for: memo))
        }
        memo.startDate = placed.startDate
        memo.deadline = placed.deadline
        if let start = memo.startDate, let deadline = memo.deadline, deadline < start {
            memo.deadline = start
        }
        persist(memo, syncLinkedReminder: true)
        collapsedGroups.remove(bucket.title)
        selectedID = memo.id
        dropTargetTitle = nil
    }

    private func scheduleSave(_ memo: Memo) {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            persist(memo)
        }
    }

    private func flush() {
        saveTask?.cancel()
        saveTask = nil
        if let memo = selectedMemo() { persist(memo) }
    }

    private func persist(_ memo: Memo, syncLinkedReminder: Bool = false) {
        memo.updatedAt = Date()
        scheduleLocalReminder(for: memo)
        try? modelContext.save()
        if syncLinkedReminder, memo.isLinkedToRemindersValue {
            syncReminder(memo)
        }
    }

    private func scheduleLocalReminder(for memo: Memo) {
        let identifier = localReminderIdentifier(for: memo)
        guard !memo.isCompletedValue,
              !memo.isArchivedValue,
              !memo.isRecentlyDeleted,
              let fireDate = memo.reminderFireDate else {
            NotificationManager.shared.cancel(identifier: identifier)
            return
        }
        NotificationManager.shared.scheduleMemoReminder(
            identifier: identifier,
            title: memo.reminderNotificationTitle,
            body: displayTitle(memo),
            at: fireDate
        )
    }

    private func localReminderIdentifier(for memo: Memo) -> String {
        "memo.deadline.\(memo.id.uuidString)"
    }

    private func loadReminderLists() {
        Task { @MainActor in
            do {
                reminderLists = try await MemoReminderLinkService.shared.reminderLists()
            } catch {
                reminderLists = []
            }
        }
    }

    private func linkReminder(_ memo: Memo) {
        reminderStatusMessage = "연결 중..."
        Task { @MainActor in
            do {
                memo.reminderIdentifier = try await MemoReminderLinkService.shared.saveReminder(for: memo)
                memo.isLinkedToRemindersValue = true
                persist(memo)
                reminderStatusMessage = "연동됨"
            } catch {
                memo.isLinkedToRemindersValue = false
                try? modelContext.save()
                reminderStatusMessage = error.localizedDescription
            }
        }
    }

    private func syncReminder(_ memo: Memo) {
        guard memo.isLinkedToRemindersValue else { return }
        reminderStatusMessage = "동기화 중..."
        Task { @MainActor in
            do {
                memo.reminderIdentifier = try await MemoReminderLinkService.shared.saveReminder(for: memo)
                persist(memo)
                reminderStatusMessage = "연동됨"
            } catch {
                reminderStatusMessage = error.localizedDescription
            }
        }
    }

    private func unlinkReminder(_ memo: Memo) {
        do {
            try MemoReminderLinkService.shared.removeReminder(for: memo)
            memo.isLinkedToRemindersValue = false
            memo.reminderIdentifier = nil
            persist(memo)
            reminderStatusMessage = "연동 안 함"
        } catch {
            reminderStatusMessage = error.localizedDescription
        }
    }

    private func chipForeground(_ tone: TodoDueChip.Tone) -> Color {
        switch tone {
        case .over: return Color(red: 0.75, green: 0.34, blue: 0.23)
        case .today: return Color(red: 0.77, green: 0.48, blue: 0.14)
        case .soon: return Color(red: 0.67, green: 0.50, blue: 0.13)
        case .later: return Color(red: 0.54, green: 0.47, blue: 0.40)
        }
    }

    private func chipBackground(_ tone: TodoDueChip.Tone) -> Color {
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
