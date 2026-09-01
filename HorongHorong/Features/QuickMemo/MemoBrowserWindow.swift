import SwiftUI
import SwiftData

private enum MemoBrowserFilter: Hashable {
    case overdue
    case today
    case upcoming
    case someday
    case completed
    case reminders

    var title: String {
        switch self {
        case .overdue: return TodoBucket.overdue.title
        case .today: return TodoBucket.today.title
        case .upcoming: return TodoBucket.upcoming.title
        case .someday: return TodoBucket.someday.title
        case .completed: return TodoBucket.completed.title
        case .reminders: return "미리알림"
        }
    }

    var symbol: String {
        switch self {
        case .overdue: return TodoBucket.overdue.symbol
        case .today: return TodoBucket.today.symbol
        case .upcoming: return TodoBucket.upcoming.symbol
        case .someday: return TodoBucket.someday.symbol
        case .completed: return TodoBucket.completed.symbol
        case .reminders: return "list.bullet.circle"
        }
    }

    var bucket: TodoBucket? {
        switch self {
        case .overdue: return .overdue
        case .today: return .today
        case .upcoming: return .upcoming
        case .someday: return .someday
        case .completed: return .completed
        case .reminders: return nil
        }
    }
}

private enum MemoBrowserSort: String, CaseIterable, Identifiable {
    case updated = "최신순"
    case deadline = "마감순"

    var id: String { rawValue }
}

private struct ReminderOffsetOption: Identifiable {
    let id: Int
    let label: String
    let minutes: Int?
}

private struct MemoCompactControlButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(isEnabled ? PopoverChrome.inkSecondary : PopoverChrome.inkTertiary.opacity(0.72))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: PopoverChrome.radius(7), style: .continuous)
                    .fill(PopoverChrome.card.opacity(configuration.isPressed ? 0.62 : 0.86))
            )
            .overlay(
                RoundedRectangle(cornerRadius: PopoverChrome.radius(7), style: .continuous)
                    .stroke(isEnabled ? PopoverChrome.divider : PopoverChrome.divider.opacity(0.55), lineWidth: 1)
            )
    }
}

struct MemoBrowserWindow: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appearanceDensity) private var appearanceDensity
    // 정렬 키는 편집으로 바뀌지 않는 필드여야 한다.
    // updatedAt 을 쓰면 메모를 수정할 때마다 fetch 가 무효화돼 창 전체가 재계산된다.
    // 표시 순서는 어차피 makeSnapshot() 에서 sort 옵션대로 다시 정한다.
    @Query(sort: \Memo.createdAt, order: .reverse) private var allMemos: [Memo]
    @AppStorage(Constants.AppStorageKey.popoverTheme)
    private var popoverTheme: String = Constants.defaultPopoverTheme

    @State private var selectedFilter: MemoBrowserFilter = .today
    @State private var selectedMemoID: UUID?
    @State private var searchText: String = ""
    @State private var todayReferenceDate = Date()
    @State private var sort: MemoBrowserSort = .updated
    @State private var reminderStatusMessage: String = ""
    @State private var reminderLists: [ReminderListOption] = []
    @State private var externalReminderItems: [ReminderListItem] = []
    @State private var isLoadingExternalReminders = false
    @State private var externalReminderMessage: String = ""
    @State private var pendingContentMemo: Memo?
    @State private var contentSaveTask: Task<Void, Never>?

    private let reminderOffsetOptions = [
        ReminderOffsetOption(id: -1, label: "알림 없음", minutes: nil),
        ReminderOffsetOption(id: 0, label: "마감 시간", minutes: 0),
        ReminderOffsetOption(id: 10, label: "10분 전", minutes: 10),
        ReminderOffsetOption(id: 60, label: "1시간 전", minutes: 60),
        ReminderOffsetOption(id: 1440, label: "1일 전", minutes: 1440)
    ]

    /// 한 번의 body 평가에서 쓰는 모든 파생 값.
    /// computed property 로 두면 사이드바·리스트·디테일에서 각각 다시 계산된다.
    private struct Snapshot {
        var memos: [Memo] = []
        var memoIDs: [UUID] = []
        var externalItems: [ReminderListItem] = []
        var overdueCount = 0
        var todayCount = 0
        var upcomingCount = 0
        var somedayCount = 0
        var completedCount = 0
        var reminderCount = 0
    }

    /// allMemos 를 한 번만 순회하며 검색·필터·사이드바 카운트를 모두 계산한다.
    private func makeSnapshot() -> Snapshot {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        var overdueCount = 0
        var todayCount = 0
        var upcomingCount = 0
        var somedayCount = 0
        var completedCount = 0
        var linkedIdentifiers: Set<String> = []
        var searched: [Memo] = []

        for memo in allMemos {
            if let identifier = memo.reminderIdentifier {
                linkedIdentifiers.insert(identifier)
            }
            guard memo.resolvedSection == .todo,
                  !memo.isArchivedValue,
                  !memo.isRecentlyDeleted else { continue }

            let bucket = TodoBucket.of(
                startDate: memo.startDate,
                deadline: memo.deadline,
                isCompleted: memo.isCompletedValue,
                now: todayReferenceDate
            )
            switch bucket {
            case .overdue: overdueCount += 1
            case .today: todayCount += 1
            case .upcoming: upcomingCount += 1
            case .someday: somedayCount += 1
            case .completed: completedCount += 1
            }

            if query.isEmpty || memo.content.localizedCaseInsensitiveContains(query) {
                searched.append(memo)
            }
        }

        let filtered = searched.filter { memo in
            guard let bucket = selectedFilter.bucket else { return false }
            return TodoBucket.of(
                startDate: memo.startDate,
                deadline: memo.deadline,
                isCompleted: memo.isCompletedValue,
                now: todayReferenceDate
            ) == bucket
        }
        let sortedMemos = sortMemos(filtered)

        let unlinked = externalReminderItems.filter { !linkedIdentifiers.contains($0.id) }
        let activeExternalCount = unlinked.lazy.filter { !$0.isCompleted }.count
        let externalFiltered = unlinked.filter { item in
            let matchesQuery = query.isEmpty
                || item.title.localizedCaseInsensitiveContains(query)
                || (item.notes?.localizedCaseInsensitiveContains(query) ?? false)
                || item.calendarTitle.localizedCaseInsensitiveContains(query)
            guard matchesQuery else { return false }
            return selectedFilter == .reminders && !item.isCompleted
        }

        return Snapshot(
            memos: sortedMemos,
            memoIDs: sortedMemos.map(\.id),
            externalItems: sortExternalReminderItems(externalFiltered),
            overdueCount: overdueCount,
            todayCount: todayCount,
            upcomingCount: upcomingCount,
            somedayCount: somedayCount,
            completedCount: completedCount,
            reminderCount: activeExternalCount
        )
    }

    private func sortMemos(_ memos: [Memo]) -> [Memo] {
        switch sort {
        case .updated:
            return memos.sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
                return $0.updatedAt > $1.updatedAt
            }
        case .deadline:
            return memos.sorted {
                let left = $0.deadline ?? $0.startDate ?? .distantFuture
                let right = $1.deadline ?? $1.startDate ?? .distantFuture
                if left != right { return left < right }
                return $0.updatedAt > $1.updatedAt
            }
        }
    }

    private func selectedMemo(in snapshot: Snapshot) -> Memo? {
        snapshot.memos.first { $0.id == selectedMemoID } ?? snapshot.memos.first
    }

    var body: some View {
        let snapshot = makeSnapshot()

        return HStack(spacing: 0) {
            sidebar(snapshot)
            Divider()
            memoListPane(snapshot)
            Divider()
            detailPane(snapshot)
        }
        .frame(minWidth: 920, minHeight: 560)
        .background(PopoverChrome.surface)
        .appearanceAccentTint(.popover)
        .id(popoverTheme)
        .onAppear {
            todayReferenceDate = Date()
            selectedMemoID = selectedMemo(in: snapshot)?.id
            loadReminderLists()
            loadExternalReminderItems()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            todayReferenceDate = Date()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in
            todayReferenceDate = Date()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            todayReferenceDate = Date()
        }
        .onDisappear {
            flushPendingContentSave()
        }
        // 앱 종료 경로에서는 onDisappear 가 보장되지 않는다.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            flushPendingContentSave()
        }
        .onChange(of: selectedMemoID) { _, _ in
            flushPendingContentSave()
        }
        .onChange(of: snapshot.memoIDs) { _, ids in
            guard !ids.isEmpty else {
                selectedMemoID = nil
                return
            }
            if let selectedMemoID, ids.contains(selectedMemoID) {
                return
            }
            selectedMemoID = ids[0]
        }
    }

    private func sidebar(_ snapshot: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarSectionTitle("할 일")
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)
                .padding(.bottom, 18)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    sidebarButton(.overdue, count: snapshot.overdueCount)
                    sidebarButton(.today, count: snapshot.todayCount)
                    sidebarButton(.upcoming, count: snapshot.upcomingCount)
                    sidebarButton(.someday, count: snapshot.somedayCount)
                    sidebarButton(.completed, count: snapshot.completedCount)
                    sidebarButton(.reminders, count: snapshot.reminderCount)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 18)
            }
        }
        .padding(.horizontal, 18)
        .frame(width: 204)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(PopoverChrome.surfaceAlt)
    }

    private func sidebarSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(PopoverChrome.inkTertiary)
            .padding(.horizontal, 14)
    }

    private func sidebarButton(_ filter: MemoBrowserFilter, count: Int) -> some View {
        Button {
            selectedFilter = filter
        } label: {
            HStack(spacing: 10) {
                Image(systemName: filter.symbol)
                    .frame(width: 18)
                Text(filter.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .allowsTightening(true)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                Text("\(count)")
                    .foregroundStyle(selectedFilter == filter ? PopoverChrome.accent : PopoverChrome.inkTertiary)
                    .lineLimit(1)
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
            }
            .memoSidebarRow(isSelected: selectedFilter == filter)
        }
        .buttonStyle(.plain)
    }

    private func memoListPane(_ snapshot: Snapshot) -> some View {
        VStack(spacing: appearanceDensity.informationMetric(14)) {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(PopoverChrome.inkTertiary)
                    TextField("할 일 검색...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(13), style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PopoverChrome.radius(13), style: .continuous)
                        .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
                )

                Picker("", selection: $sort) {
                    ForEach(MemoBrowserSort.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .labelsHidden()
                .frame(width: 112)
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)

            if snapshot.memos.isEmpty && snapshot.externalItems.isEmpty {
                emptyList(snapshot)
            } else {
                ScrollView {
                    LazyVStack(spacing: appearanceDensity.informationMetric(10)) {
                        ForEach(snapshot.memos) { memo in
                            memoRow(memo)
                        }
                        if !snapshot.externalItems.isEmpty {
                            externalReminderSection(snapshot)
                        }
                    }
                    .padding(.horizontal, appearanceDensity.informationMetric(14))
                    .padding(.bottom, appearanceDensity.informationMetric(12))
                }
            }

            newMemoButton
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
        .frame(width: 470)
        .frame(maxHeight: .infinity)
        .background(PopoverChrome.surface)
    }

    private func emptyList(_ snapshot: Snapshot) -> some View {
        VStack(spacing: 10) {
            if selectedFilter == .today {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                Text(snapshot.todayCount == 0 ? "오늘 할 일이 없습니다" : "검색 결과가 없습니다")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                Text(
                    snapshot.todayCount == 0
                        ? "마감 또는 시작일이 오늘인 할 일이 여기에 모입니다."
                        : "오늘 할 일 \(snapshot.todayCount)개가 있지만\n현재 검색어와 일치하는 항목은 없습니다."
                )
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .multilineTextAlignment(.center)
            } else {
                if isLoadingExternalReminders {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "note.text")
                        .font(.system(size: 30, weight: .regular))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                }
                Text(isLoadingExternalReminders ? "미리알림을 불러오는 중입니다" : "표시할 할 일이 없습니다")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                if !externalReminderMessage.isEmpty {
                    Text(externalReminderMessage)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func externalReminderSection(_ snapshot: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("미리알림")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                Rectangle()
                    .fill(PopoverChrome.border)
                    .frame(height: 1)
            }
            .padding(.top, snapshot.memos.isEmpty ? 0 : 4)

            ForEach(snapshot.externalItems) { item in
                externalReminderRow(item)
            }
        }
    }

    private func externalReminderRow(_ item: ReminderListItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "list.bullet.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(item.isCompleted ? PopoverChrome.inkTertiary : PopoverChrome.accent)
                    .frame(width: 34, height: 34)
                    .background(PopoverChrome.surfaceAlt.opacity(0.9), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))

                VStack(alignment: .leading, spacing: 7) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(item.isCompleted ? PopoverChrome.inkTertiary : PopoverChrome.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 8) {
                        Text(item.calendarTitle)
                            .memoBadge(tint: PopoverChrome.inkTertiary)
                        if let dueDate = item.dueDate {
                            Label(memoDeadlineLabel(dueDate), systemImage: "calendar")
                                .memoBadge(tint: dueDate < Date() ? .red : .orange)
                        }
                        if item.url != nil {
                            Image(systemName: "link")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(PopoverChrome.accent)
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            if let notes = item.notes, !notes.isEmpty {
                Text(notes)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .lineLimit(2)
                    .padding(.leading, 46)
            }
        }
        .padding(14)
        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(16), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PopoverChrome.radius(16), style: .continuous)
                .stroke(PopoverChrome.isGamePixel || PopoverChrome.isWineLantern ? PopoverChrome.border : Color.clear, lineWidth: PopoverChrome.borderWidth)
        )
        .overlay(alignment: .topTrailing) {
            Text("미리알림")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.accent)
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(PopoverChrome.accentSoft.opacity(0.84), in: RoundedRectangle(cornerRadius: PopoverChrome.controlRadius, style: .continuous))
                .padding(10)
        }
    }

    private func memoRow(_ memo: Memo) -> some View {
        MemoRowView(
            memo: memo,
            isSelected: selectedMemoID == memo.id,
            onSelect: { selectedMemoID = memo.id },
            onTogglePinned: { togglePinned(memo) },
            onToggleCompleted: { toggleCompleted(memo) },
            onToggleArchived: { toggleArchived(memo) },
            onDelete: { delete(memo) }
        )
    }

    private var newMemoButton: some View {
        Button {
            let memo = Memo(content: "", icon: MemoIcon.defaultIcon, section: .todo)
            switch selectedFilter {
            case .today:
                memo.startDate = Date()
            case .upcoming:
                memo.startDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())
            default:
                break
            }
            modelContext.insert(memo)
            try? modelContext.save()
            selectedMemoID = memo.id
        } label: {
            Label("새 할 일", systemImage: "plus")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(PopoverChrome.accent.opacity(0.38), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func detailPane(_ snapshot: Snapshot) -> some View {
        if let memo = selectedMemo(in: snapshot) {
            memoDetail(memo)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 30))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                Text("메모를 선택하세요")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PopoverChrome.card.opacity(PopoverChrome.isWineLantern ? 0.45 : 0.58))
        }
    }

    private func memoDetail(_ memo: Memo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            detailToolbar(memo)

            TextEditor(text: Binding(
                get: { memo.content },
                set: { newValue in
                    // 대입은 즉시(메모리) — 목록 제목·글자 수가 실시간으로 따라온다.
                    // 비싼 뒷정리(fsync·알림 재예약)만 입력이 멎은 뒤로 미룬다.
                    memo.content = newValue
                    scheduleContentSave(for: memo)
                }
            ))
            .font(.system(size: 18, weight: .regular, design: .rounded))
            .foregroundStyle(PopoverChrome.ink)
            .scrollContentBackground(.hidden)
            // placeholder 를 padding 안쪽(= TextEditor 프레임)에 얹는다.
            // TextEditor 의 텍스트 원점은 프레임 기준 (5, 0) — NSTextView 의
            // lineFragmentPadding 5pt 만 보정하면 커서와 정확히 겹친다.
            .overlay(alignment: .topLeading) {
                if memo.content.isEmpty {
                    Text("메모를 입력하세요...")
                        .font(.system(size: 18, weight: .regular, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary.opacity(0.62))
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)

            Divider()
            schedulePanel(memo)
            Divider()
            detailFooter(memo)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PopoverChrome.card.opacity(PopoverChrome.isWineLantern ? 0.55 : 0.72))
    }

    private func detailToolbar(_ memo: Memo) -> some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(MemoIcon.options, id: \.self) { icon in
                    Button {
                        memo.icon = icon
                        persist(memo)
                    } label: {
                        Text("\(icon) \(MemoIcon.label(for: icon))")
                    }
                }
            } label: {
                Text("\(memo.icon ?? MemoIcon.defaultIcon) \(MemoIcon.label(for: memo.icon ?? MemoIcon.defaultIcon))")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.accent)
                    .padding(.horizontal, 13)
                    .frame(height: 30)
                    .background(PopoverChrome.accentSoft.opacity(0.85), in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                togglePinned(memo)
            } label: {
                Image(systemName: memo.isPinned ? "pin.slash" : "pin")
            }
            .buttonStyle(.borderless)
            .help(memo.isPinned ? "고정 해제" : "고정")

            Button {
                toggleCompleted(memo)
            } label: {
                Image(systemName: memo.isCompletedValue ? "arrow.uturn.backward.circle" : "checkmark")
            }
            .buttonStyle(.borderless)
            .help(memo.isCompletedValue ? "완료 해제" : "완료")

            Button {
                toggleArchived(memo)
            } label: {
                Image(systemName: memo.isArchivedValue ? "archivebox" : "archivebox.fill")
            }
            .buttonStyle(.borderless)
            .help(memo.isArchivedValue ? "보관 해제" : "보관")

            Button(role: .destructive) {
                delete(memo)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("삭제")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func schedulePanel(_ memo: Memo) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Toggle("시작일", isOn: startDateEnabledBinding(for: memo))
                    .toggleStyle(.checkbox)
                    .tint(PopoverChrome.accent)
                    .frame(width: 76, alignment: .leading)
                DatePicker("", selection: startDateBinding(for: memo), displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .tint(PopoverChrome.accent)
                    .disabled(memo.startDate == nil)
            }

            HStack(spacing: 10) {
                Toggle("마감", isOn: deadlineEnabledBinding(for: memo))
                    .toggleStyle(.checkbox)
                    .tint(PopoverChrome.accent)
                    .frame(width: 76, alignment: .leading)
                DatePicker("", selection: deadlineBinding(for: memo), displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .tint(PopoverChrome.accent)
                    .disabled(memo.deadline == nil)
            }

            HStack(spacing: 10) {
                Label("알림", systemImage: "bell")
                    .frame(width: 76, alignment: .leading)
                Picker("", selection: reminderOffsetBinding(for: memo)) {
                    ForEach(availableReminderOffsetOptions(for: memo)) { option in
                        Text(option.label).tag(option.minutes)
                    }
                }
                .labelsHidden()
                .tint(PopoverChrome.accent)
                .disabled(memo.startDate == nil && memo.deadline == nil)
                Spacer()
            }

            HStack(spacing: 10) {
                Toggle("미리알림 앱에 연결", isOn: reminderLinkBinding(for: memo))
                    .toggleStyle(.switch)
                    .tint(PopoverChrome.accent)
                Spacer()
                if !reminderStatusMessage.isEmpty {
                    Text(reminderStatusMessage)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                }
                Button("동기화") {
                    syncReminder(memo)
                }
                .controlSize(.small)
                .buttonStyle(MemoCompactControlButtonStyle())
                .disabled(!memo.isLinkedToRemindersValue)
            }

            HStack(spacing: 10) {
                Label("목록", systemImage: "list.bullet")
                    .frame(width: 76, alignment: .leading)
                Picker("", selection: reminderCalendarBinding(for: memo)) {
                    Text("기본 목록").tag(nil as String?)
                    ForEach(reminderLists) { list in
                        Text(list.isDefault ? "\(list.title) (기본)" : list.title)
                            .tag(list.id as String?)
                    }
                }
                .labelsHidden()
                .tint(PopoverChrome.accent)
                .disabled(reminderLists.isEmpty)
                Spacer()
            }
        }
        .font(.system(size: 13, weight: .medium, design: .rounded))
        .foregroundStyle(PopoverChrome.inkSecondary)
        .environment(\.colorScheme, PopoverChrome.isWineLantern ? .dark : .light)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func detailFooter(_ memo: Memo) -> some View {
        HStack(spacing: 12) {
            Label(formatDate(memo.createdAt), systemImage: "calendar")
            if let deadline = memo.deadline {
                Label(memoDeadlineLabel(deadline), systemImage: "calendar.badge.clock")
            }
            Spacer()
            Text("\(memo.content.count)자 · 자동 저장됨")
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(PopoverChrome.inkTertiary)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func formatDate(_ date: Date) -> String {
        Self.detailDateFormatter.string(from: date)
    }

    private static let detailDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private func sortExternalReminderItems(_ items: [ReminderListItem]) -> [ReminderListItem] {
        switch sort {
        case .deadline:
            return items.sorted {
                let left = $0.dueDate ?? .distantFuture
                let right = $1.dueDate ?? .distantFuture
                if left != right { return left < right }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        case .updated:
            return items.sorted {
                if $0.isCompleted != $1.isCompleted { return !$0.isCompleted }
                let left = $0.dueDate ?? .distantFuture
                let right = $1.dueDate ?? .distantFuture
                if left != right { return left < right }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        }
    }

    private func startDateEnabledBinding(for memo: Memo) -> Binding<Bool> {
        Binding {
            memo.startDate != nil
        } set: { enabled in
            memo.startDate = enabled ? (memo.startDate ?? Date()) : nil
            clearReminderOffsetIfUnschedulable(memo)
            persist(memo, syncLinkedReminder: true)
        }
    }

    private func deadlineEnabledBinding(for memo: Memo) -> Binding<Bool> {
        Binding {
            memo.deadline != nil
        } set: { enabled in
            memo.deadline = enabled ? (memo.deadline ?? Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()) : nil
            clearReminderOffsetIfUnschedulable(memo)
            persist(memo, syncLinkedReminder: true)
        }
    }

    /// "마감 시간" 알림은 마감일이 있어야 기준 시각이 생긴다.
    private func availableReminderOffsetOptions(for memo: Memo) -> [ReminderOffsetOption] {
        guard memo.deadline == nil else { return reminderOffsetOptions }
        return reminderOffsetOptions.filter { $0.minutes != 0 }
    }

    /// 시작일·마감을 끈 뒤 기준 시각이 사라졌으면 알림 설정도 함께 정리한다.
    private func clearReminderOffsetIfUnschedulable(_ memo: Memo) {
        guard memo.reminderBaseDate == nil else { return }
        memo.reminderOffsetMinutes = nil
    }

    /// 시작이 마감보다 뒤면 **마감을 함께 민다.** 되돌리거나 무시하지 않는 이유는,
    /// 사용자가 방금 고른 값을 말없이 버리면 «왜 안 바뀌지» 가 되기 때문이다.
    /// 방금 고른 쪽을 살리고 반대쪽을 따라오게 한다.
    ///
    /// 뒤집힌 값이 저장되면 «마감 − 시작» 이 음수가 되어, 나중에 이 값으로 소요 시간을
    /// 재려 할 때 통계가 깨진다(실측 2026-08-20: 완료 할일 68건 중 6건이 역전 상태였다).
    private func startDateBinding(for memo: Memo) -> Binding<Date> {
        Binding {
            memo.startDate ?? Date()
        } set: { date in
            memo.setStartDate(date)
            persist(memo, syncLinkedReminder: true)
        }
    }

    /// 마감을 시작보다 앞으로 당기면 **시작을 함께 당긴다.** 위와 같은 사정이다.
    private func deadlineBinding(for memo: Memo) -> Binding<Date> {
        Binding {
            memo.deadline ?? Date()
        } set: { date in
            memo.setDeadline(date)
            persist(memo, syncLinkedReminder: true)
        }
    }

    private func reminderOffsetBinding(for memo: Memo) -> Binding<Int?> {
        Binding {
            memo.reminderOffsetMinutes
        } set: { minutes in
            memo.reminderOffsetMinutes = minutes
            persist(memo, syncLinkedReminder: true)
        }
    }

    private func reminderCalendarBinding(for memo: Memo) -> Binding<String?> {
        Binding {
            memo.reminderCalendarIdentifier
        } set: { identifier in
            memo.reminderCalendarIdentifier = identifier
            persist(memo, syncLinkedReminder: true)
        }
    }

    private func reminderLinkBinding(for memo: Memo) -> Binding<Bool> {
        Binding {
            memo.isLinkedToRemindersValue
        } set: { isLinked in
            if isLinked {
                loadReminderLists()
                linkReminder(memo)
            } else {
                unlinkReminder(memo)
            }
        }
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

    private func loadExternalReminderItems() {
        isLoadingExternalReminders = true
        externalReminderMessage = ""
        Task { @MainActor in
            do {
                externalReminderItems = try await MemoReminderLinkService.shared.reminderItems()
                externalReminderMessage = ""
            } catch {
                externalReminderItems = []
                externalReminderMessage = error.localizedDescription
            }
            isLoadingExternalReminders = false
        }
    }

    /// 본문 입력이 멎은 뒤에만 persist() 를 돌린다.
    /// persist() 한 번은 SQLite fsync + 알림 XPC 라 타건마다 부르면 메인 스레드가 막힌다.
    private func scheduleContentSave(for memo: Memo) {
        contentSaveTask?.cancel()
        pendingContentMemo = memo
        contentSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            flushPendingContentSave()
        }
    }

    /// 저장이 밀린 채로 화면을 떠나지 않도록 강제 기록한다.
    private func flushPendingContentSave() {
        contentSaveTask?.cancel()
        contentSaveTask = nil
        guard let memo = pendingContentMemo else { return }
        pendingContentMemo = nil
        guard memo.modelContext != nil else { return }
        persist(memo)
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
            body: memoRowTitle(memo),
            at: fireDate
        )
    }

    private func localReminderIdentifier(for memo: Memo) -> String {
        "memo.deadline.\(memo.id.uuidString)"
    }

    private func linkReminder(_ memo: Memo) {
        reminderStatusMessage = "연결 중..."
        Task { @MainActor in
            do {
                memo.reminderIdentifier = try await MemoReminderLinkService.shared.saveReminder(for: memo)
                memo.isLinkedToRemindersValue = true
                persist(memo)
                loadExternalReminderItems()
                reminderStatusMessage = "미리알림 연결됨"
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
                loadExternalReminderItems()
                reminderStatusMessage = "동기화됨"
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
            loadExternalReminderItems()
            reminderStatusMessage = "연결 해제됨"
        } catch {
            reminderStatusMessage = error.localizedDescription
        }
    }

    private func togglePinned(_ memo: Memo) {
        memo.isPinned.toggle()
        persist(memo)
    }

    private func toggleCompleted(_ memo: Memo) {
        memo.isCompletedValue.toggle()
        if memo.isCompletedValue {
            memo.isPinned = false
            NotificationManager.shared.cancel(identifier: localReminderIdentifier(for: memo))
        }
        persist(memo, syncLinkedReminder: true)
    }

    private func toggleArchived(_ memo: Memo) {
        memo.isArchivedValue.toggle()
        if memo.isArchivedValue {
            memo.isPinned = false
            NotificationManager.shared.cancel(identifier: localReminderIdentifier(for: memo))
        }
        persist(memo, syncLinkedReminder: true)
    }

    private func delete(_ memo: Memo) {
        let deletedID = memo.id
        if pendingContentMemo?.id == deletedID {
            contentSaveTask?.cancel()
            contentSaveTask = nil
            pendingContentMemo = nil
        }
        NotificationManager.shared.cancel(identifier: localReminderIdentifier(for: memo))
        if memo.isLinkedToRemindersValue {
            try? MemoReminderLinkService.shared.removeReminder(for: memo)
            memo.isLinkedToRemindersValue = false
            memo.reminderIdentifier = nil
        }
        if memo.resolvedSection == .todo {
            memo.deletedAt = Date()
            memo.updatedAt = Date()
            try? modelContext.save()
        } else {
            modelContext.delete(memo)
            try? modelContext.save()
        }
        loadExternalReminderItems()
        if selectedMemoID == deletedID {
            // nil 로 두면 다음 스냅샷의 onChange 가 첫 항목으로 보정한다.
            selectedMemoID = nil
        }
    }
}

private func memoRowTitle(_ memo: Memo) -> String {
    let trimmed = memo.content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "새 메모" }
    return trimmed.components(separatedBy: .newlines).first ?? trimmed
}

private func memoRowIcon(_ memo: Memo) -> String {
    if memo.isArchivedValue { return "📦" }
    if memo.isCompletedValue { return "✅" }
    if memo.isPinned { return MemoIcon.pinnedIcon }
    return memo.icon ?? MemoIcon.defaultIcon
}

private func memoDeadlineLabel(_ date: Date) -> String {
    if Calendar.current.isDateInToday(date) {
        return "오늘 마감"
    }
    if date < Date() {
        return "마감 지남"
    }
    return "\(date.formatted(date: .abbreviated, time: .omitted)) 마감"
}

/// 행을 독립 View 로 두면 SwiftUI 가 메모별로 재렌더 범위를 좁힐 수 있다.
private struct MemoRowView: View {
    @Environment(\.appearanceDensity) private var appearanceDensity
    let memo: Memo
    let isSelected: Bool
    let onSelect: () -> Void
    let onTogglePinned: () -> Void
    let onToggleCompleted: () -> Void
    let onToggleArchived: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: appearanceDensity.informationMetric(12)) {
                Text(memoRowIcon(memo))
                    .font(.system(size: 20))
                    .frame(width: 34, height: 34)
                    .background(PopoverChrome.surfaceAlt.opacity(0.9), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))

                VStack(alignment: .leading, spacing: appearanceDensity.informationMetric(7)) {
                    Text(memoRowTitle(memo))
                        .font(.system(size: appearanceDensity.informationMetric(15), weight: .semibold, design: .rounded))
                        .foregroundStyle(memo.isCompletedValue ? PopoverChrome.inkTertiary : PopoverChrome.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 8) {
                        relativeTime(memo.updatedAt)
                        if memo.isPinned {
                            Label("고정됨", systemImage: "pin.fill")
                                .memoBadge(tint: PopoverChrome.accent)
                        }
                        if let deadline = memo.deadline {
                            Label(memoDeadlineLabel(deadline), systemImage: "calendar")
                                .memoBadge(tint: deadline < Date() ? .red : .orange)
                        }
                        if memo.reminderOffsetMinutes != nil {
                            Image(systemName: "bell")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.green)
                        }
                    }
                }

                Spacer(minLength: 0)

                Menu {
                    Button(memo.isPinned ? "고정 해제" : "고정", action: onTogglePinned)
                    Button(memo.isCompletedValue ? "완료 해제" : "완료", action: onToggleCompleted)
                    Button(memo.isArchivedValue ? "보관 해제" : "보관", action: onToggleArchived)
                    Divider()
                    Button("삭제", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .frame(width: 22, height: 22)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 22)
            }
            .padding(appearanceDensity.informationMetric(14))
            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(16), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PopoverChrome.radius(16), style: .continuous)
                    .stroke(
                        isSelected || PopoverChrome.isGamePixel || PopoverChrome.isWineLantern ? (isSelected ? PopoverChrome.accent : PopoverChrome.border) : Color.clear,
                        lineWidth: isSelected ? 1.4 : PopoverChrome.borderWidth
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(16), style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func relativeTime(_ date: Date) -> some View {
        HStack(spacing: 0) {
            Text(date, style: .relative)
            Text(" 전")
        }
        .font(.system(size: appearanceDensity.informationMetric(12), weight: .semibold, design: .rounded))
        .foregroundStyle(PopoverChrome.inkTertiary)
    }
}

private extension View {
    func memoSidebarRow(isSelected: Bool) -> some View {
        self
            .font(.system(size: 14, weight: isSelected ? .bold : .semibold, design: .rounded))
            .foregroundStyle(isSelected ? PopoverChrome.accent : PopoverChrome.inkSecondary)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 34)
            .background(isSelected ? PopoverChrome.accentSoft.opacity(0.72) : Color.clear, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous))
    }

    func memoBadge(tint: Color) -> some View {
        self
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: PopoverChrome.controlRadius, style: .continuous))
    }
}
