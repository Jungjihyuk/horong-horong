import SwiftUI
import SwiftData

private enum MemoBrowserFilter: Hashable {
    case all
    case reminders
    case pinned
    case dueSoon
    case completed
    case archived
    case icon(String)

    var title: String {
        switch self {
        case .all:
            return "전체"
        case .reminders:
            return "미리알림"
        case .pinned:
            return "고정됨"
        case .dueSoon:
            return "곧 마감"
        case .completed:
            return "완료"
        case .archived:
            return "보관함"
        case .icon(let icon):
            return MemoIcon.label(for: icon)
        }
    }

    var symbol: String {
        switch self {
        case .all:
            return "tray.full"
        case .reminders:
            return "list.bullet.circle"
        case .pinned:
            return "pin.fill"
        case .dueSoon:
            return "calendar.badge.clock"
        case .completed:
            return "checkmark.circle.fill"
        case .archived:
            return "archivebox.fill"
        case .icon:
            return "tag"
        }
    }
}

private enum MemoBrowserSort: String, CaseIterable, Identifiable {
    case updated = "최신순"
    case deadline = "마감순"
    case category = "카테고리"

    var id: String { rawValue }
}

private struct ReminderOffsetOption: Identifiable {
    let id: Int
    let label: String
    let minutes: Int?
}

struct MemoBrowserWindow: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Memo.updatedAt, order: .reverse) private var allMemos: [Memo]

    @State private var selectedFilter: MemoBrowserFilter = .all
    @State private var selectedMemoID: UUID?
    @State private var searchText: String = ""
    @State private var sort: MemoBrowserSort = .updated
    @State private var reminderStatusMessage: String = ""
    @State private var reminderLists: [ReminderListOption] = []
    @State private var externalReminderItems: [ReminderListItem] = []
    @State private var isLoadingExternalReminders = false
    @State private var externalReminderMessage: String = ""

    private let reminderOffsetOptions = [
        ReminderOffsetOption(id: -1, label: "알림 없음", minutes: nil),
        ReminderOffsetOption(id: 0, label: "마감 시간", minutes: 0),
        ReminderOffsetOption(id: 10, label: "10분 전", minutes: 10),
        ReminderOffsetOption(id: 60, label: "1시간 전", minutes: 60),
        ReminderOffsetOption(id: 1440, label: "1일 전", minutes: 1440)
    ]

    private var activeMemos: [Memo] {
        allMemos.filter { !$0.isCompletedValue && !$0.isArchivedValue }
    }

    private var selectedMemo: Memo? {
        filteredMemos.first { $0.id == selectedMemoID } ?? filteredMemos.first
    }

    private var filteredMemos: [Memo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let searched = allMemos.filter { memo in
            guard !query.isEmpty else { return true }
            let icon = memo.icon ?? MemoIcon.defaultIcon
            return memo.content.localizedCaseInsensitiveContains(query)
                || MemoIcon.label(for: icon).localizedCaseInsensitiveContains(query)
        }

        let filtered = searched.filter { memo in
            switch selectedFilter {
            case .all:
                return !memo.isCompletedValue && !memo.isArchivedValue
            case .reminders:
                return false
            case .pinned:
                return memo.isPinned && !memo.isCompletedValue && !memo.isArchivedValue
            case .dueSoon:
                return memo.deadline != nil && !memo.isCompletedValue && !memo.isArchivedValue
            case .completed:
                return memo.isCompletedValue && !memo.isArchivedValue
            case .archived:
                return memo.isArchivedValue
            case .icon(let icon):
                return (memo.icon ?? MemoIcon.defaultIcon) == icon && !memo.isCompletedValue && !memo.isArchivedValue
            }
        }

        switch sort {
        case .updated:
            return filtered.sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
                return $0.updatedAt > $1.updatedAt
            }
        case .deadline:
            return filtered.sorted {
                let left = $0.deadline ?? .distantFuture
                let right = $1.deadline ?? .distantFuture
                if left != right { return left < right }
                return $0.updatedAt > $1.updatedAt
            }
        case .category:
            return filtered.sorted {
                let left = MemoIcon.label(for: $0.icon ?? MemoIcon.defaultIcon)
                let right = MemoIcon.label(for: $1.icon ?? MemoIcon.defaultIcon)
                if left != right { return left < right }
                return $0.updatedAt > $1.updatedAt
            }
        }
    }

    private var linkedReminderIdentifiers: Set<String> {
        Set(allMemos.compactMap(\.reminderIdentifier))
    }

    private var unlinkedExternalReminderItems: [ReminderListItem] {
        externalReminderItems.filter { !linkedReminderIdentifiers.contains($0.id) }
    }

    private var filteredExternalReminderItems: [ReminderListItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let searched = unlinkedExternalReminderItems.filter { item in
            guard !query.isEmpty else { return true }
            return item.title.localizedCaseInsensitiveContains(query)
                || (item.notes?.localizedCaseInsensitiveContains(query) ?? false)
                || item.calendarTitle.localizedCaseInsensitiveContains(query)
        }

        let filtered = searched.filter { item in
            switch selectedFilter {
            case .all, .reminders:
                return !item.isCompleted
            case .dueSoon:
                return item.dueDate != nil && !item.isCompleted
            case .completed:
                return item.isCompleted
            case .pinned, .archived, .icon:
                return false
            }
        }

        return sortExternalReminderItems(filtered)
    }

    private var iconFilters: [String] {
        let existing = Set(activeMemos.map { $0.icon ?? MemoIcon.defaultIcon })
        let configured = MemoIcon.options.filter { existing.contains($0) }
        let extras = existing.subtracting(MemoIcon.options).sorted()
        return configured + extras
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            memoListPane
            Divider()
            detailPane
        }
        .frame(minWidth: 920, minHeight: 560)
        .background(PopoverChrome.surface)
        .onAppear {
            selectedMemoID = selectedMemo?.id
            loadReminderLists()
            loadExternalReminderItems()
        }
        .onChange(of: filteredMemos.map(\.id)) { _, ids in
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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            sidebarSectionTitle("보기")
            sidebarButton(.all, count: activeMemos.count + unlinkedExternalReminderItems.filter { !$0.isCompleted }.count)
            sidebarButton(.reminders, count: unlinkedExternalReminderItems.filter { !$0.isCompleted }.count)
            sidebarButton(.pinned, count: activeMemos.filter(\.isPinned).count)
            sidebarButton(.dueSoon, count: activeMemos.filter { $0.deadline != nil }.count + unlinkedExternalReminderItems.filter { $0.dueDate != nil && !$0.isCompleted }.count)
            sidebarButton(.completed, count: allMemos.filter { $0.isCompletedValue && !$0.isArchivedValue }.count + unlinkedExternalReminderItems.filter(\.isCompleted).count)
            sidebarButton(.archived, count: allMemos.filter(\.isArchivedValue).count)

            sidebarSectionTitle("카테고리")
                .padding(.top, 8)

            if iconFilters.isEmpty {
                Text("카테고리 없음")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .padding(.horizontal, 14)
            } else {
                ForEach(iconFilters, id: \.self) { icon in
                    sidebarIconButton(icon)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 24)
        .frame(width: 184)
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
                Spacer()
                Text("\(count)")
                    .foregroundStyle(selectedFilter == filter ? PopoverChrome.accent : PopoverChrome.inkTertiary)
            }
            .memoSidebarRow(isSelected: selectedFilter == filter)
        }
        .buttonStyle(.plain)
    }

    private func sidebarIconButton(_ icon: String) -> some View {
        let filter = MemoBrowserFilter.icon(icon)
        let count = activeMemos.filter { ($0.icon ?? MemoIcon.defaultIcon) == icon }.count
        return Button {
            selectedFilter = filter
        } label: {
            HStack(spacing: 10) {
                Text(icon)
                    .frame(width: 18)
                Text(MemoIcon.label(for: icon))
                Spacer()
                Text("\(count)")
                    .foregroundStyle(selectedFilter == filter ? PopoverChrome.accent : PopoverChrome.inkTertiary)
            }
            .memoSidebarRow(isSelected: selectedFilter == filter)
        }
        .buttonStyle(.plain)
    }

    private var memoListPane: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(PopoverChrome.inkTertiary)
                    TextField("메모 검색...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(PopoverChrome.border, lineWidth: 1)
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

            if filteredMemos.isEmpty && filteredExternalReminderItems.isEmpty {
                emptyList
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredMemos) { memo in
                            memoRow(memo)
                        }
                        if !filteredExternalReminderItems.isEmpty {
                            externalReminderSection
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
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

    private var emptyList: some View {
        VStack(spacing: 10) {
            if isLoadingExternalReminders {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "note.text")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }
            Text(isLoadingExternalReminders ? "미리알림을 불러오는 중입니다" : "표시할 메모가 없습니다")
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var externalReminderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("미리알림")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                Rectangle()
                    .fill(PopoverChrome.border)
                    .frame(height: 1)
            }
            .padding(.top, filteredMemos.isEmpty ? 0 : 4)

            ForEach(filteredExternalReminderItems) { item in
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
                    .background(PopoverChrome.surfaceAlt.opacity(0.9), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

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
                            Label(deadlineLabel(dueDate), systemImage: "calendar")
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
        .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Text("미리알림")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.accent)
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(PopoverChrome.accentSoft.opacity(0.84), in: Capsule())
                .padding(10)
        }
    }

    private func memoRow(_ memo: Memo) -> some View {
        Button {
            selectedMemoID = memo.id
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(rowIcon(for: memo))
                    .font(.system(size: 20))
                    .frame(width: 34, height: 34)
                    .background(PopoverChrome.surfaceAlt.opacity(0.9), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 7) {
                    Text(rowTitle(for: memo))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
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
                            Label(deadlineLabel(deadline), systemImage: "calendar")
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
                    Button(memo.isPinned ? "고정 해제" : "고정") {
                        togglePinned(memo)
                    }
                    Button(memo.isCompletedValue ? "완료 해제" : "완료") {
                        toggleCompleted(memo)
                    }
                    Button(memo.isArchivedValue ? "보관 해제" : "보관") {
                        toggleArchived(memo)
                    }
                    Divider()
                    Button("삭제", role: .destructive) {
                        delete(memo)
                    }
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
            .padding(14)
            .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selectedMemoID == memo.id ? PopoverChrome.accent : Color.clear, lineWidth: 1.4)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var newMemoButton: some View {
        Button {
            let memo = Memo(content: "", icon: MemoIcon.defaultIcon)
            modelContext.insert(memo)
            try? modelContext.save()
            selectedFilter = .all
            selectedMemoID = memo.id
        } label: {
            Label("새 메모", systemImage: "plus")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(PopoverChrome.accent.opacity(0.38), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detailPane: some View {
        if let memo = selectedMemo {
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
            .background(Color.white.opacity(0.45))
        }
    }

    private func memoDetail(_ memo: Memo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            detailToolbar(memo)

            TextEditor(text: Binding(
                get: { memo.content },
                set: { newValue in
                    memo.content = newValue
                    persist(memo)
                }
            ))
            .font(.system(size: 18, weight: .regular, design: .rounded))
            .foregroundStyle(PopoverChrome.ink)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .overlay(alignment: .topLeading) {
                if memo.content.isEmpty {
                    Text("메모를 입력하세요...")
                        .font(.system(size: 18, weight: .regular, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary.opacity(0.62))
                        .padding(.horizontal, 23)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }

            Divider()
            schedulePanel(memo)
            Divider()
            detailFooter(memo)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.56))
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
                    .frame(width: 76, alignment: .leading)
                DatePicker("", selection: startDateBinding(for: memo), displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .disabled(memo.startDate == nil)
            }

            HStack(spacing: 10) {
                Toggle("마감", isOn: deadlineEnabledBinding(for: memo))
                    .toggleStyle(.checkbox)
                    .frame(width: 76, alignment: .leading)
                DatePicker("", selection: deadlineBinding(for: memo), displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .disabled(memo.deadline == nil)
            }

            HStack(spacing: 10) {
                Label("알림", systemImage: "bell")
                    .frame(width: 76, alignment: .leading)
                Picker("", selection: reminderOffsetBinding(for: memo)) {
                    ForEach(reminderOffsetOptions) { option in
                        Text(option.label).tag(option.minutes)
                    }
                }
                .labelsHidden()
                .disabled(memo.deadline == nil)
                Spacer()
            }

            HStack(spacing: 10) {
                Toggle("미리알림 앱에 연결", isOn: reminderLinkBinding(for: memo))
                    .toggleStyle(.switch)
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
                .disabled(reminderLists.isEmpty)
                Spacer()
            }
        }
        .font(.system(size: 13, weight: .medium, design: .rounded))
        .foregroundStyle(PopoverChrome.inkSecondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func detailFooter(_ memo: Memo) -> some View {
        HStack(spacing: 12) {
            Label(formatDate(memo.createdAt), systemImage: "calendar")
            if let deadline = memo.deadline {
                Label(deadlineLabel(deadline), systemImage: "calendar.badge.clock")
            }
            Spacer()
            Text("\(memo.content.count)자 · 자동 저장됨")
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(PopoverChrome.inkTertiary)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func rowTitle(for memo: Memo) -> String {
        let trimmed = memo.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "새 메모" }
        return trimmed.components(separatedBy: .newlines).first ?? trimmed
    }

    private func rowIcon(for memo: Memo) -> String {
        if memo.isArchivedValue { return "📦" }
        if memo.isCompletedValue { return "✅" }
        if memo.isPinned { return MemoIcon.pinnedIcon }
        return memo.icon ?? MemoIcon.defaultIcon
    }

    private func relativeTime(_ date: Date) -> some View {
        HStack(spacing: 0) {
            Text(date, style: .relative)
            Text(" 전")
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(PopoverChrome.inkTertiary)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func deadlineLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "오늘 마감"
        }
        if date < Date() {
            return "마감 지남"
        }
        return "\(date.formatted(date: .abbreviated, time: .omitted)) 마감"
    }

    private func sortExternalReminderItems(_ items: [ReminderListItem]) -> [ReminderListItem] {
        switch sort {
        case .deadline:
            return items.sorted {
                let left = $0.dueDate ?? .distantFuture
                let right = $1.dueDate ?? .distantFuture
                if left != right { return left < right }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        case .category:
            return items.sorted {
                if $0.calendarTitle != $1.calendarTitle {
                    return $0.calendarTitle.localizedStandardCompare($1.calendarTitle) == .orderedAscending
                }
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
            persist(memo)
        }
    }

    private func deadlineEnabledBinding(for memo: Memo) -> Binding<Bool> {
        Binding {
            memo.deadline != nil
        } set: { enabled in
            memo.deadline = enabled ? (memo.deadline ?? Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()) : nil
            if !enabled {
                memo.reminderOffsetMinutes = nil
            }
            persist(memo, syncLinkedReminder: true)
        }
    }

    private func startDateBinding(for memo: Memo) -> Binding<Date> {
        Binding {
            memo.startDate ?? Date()
        } set: { date in
            memo.startDate = date
            persist(memo, syncLinkedReminder: true)
        }
    }

    private func deadlineBinding(for memo: Memo) -> Binding<Date> {
        Binding {
            memo.deadline ?? Date()
        } set: { date in
            memo.deadline = date
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
              let deadline = memo.deadline,
              let offset = memo.reminderOffsetMinutes else {
            NotificationManager.shared.cancel(identifier: identifier)
            return
        }

        let fireDate = deadline.addingTimeInterval(TimeInterval(-offset * 60))
        NotificationManager.shared.scheduleMemoReminder(
            identifier: identifier,
            title: "메모 마감 알림",
            body: rowTitle(for: memo),
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
        NotificationManager.shared.cancel(identifier: localReminderIdentifier(for: memo))
        if memo.isLinkedToRemindersValue {
            try? MemoReminderLinkService.shared.removeReminder(for: memo)
        }
        modelContext.delete(memo)
        try? modelContext.save()
        loadExternalReminderItems()
        if selectedMemoID == deletedID {
            selectedMemoID = filteredMemos.first?.id
        }
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
            .background(isSelected ? PopoverChrome.accentSoft.opacity(0.72) : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    func memoBadge(tint: Color) -> some View {
        self
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(tint.opacity(0.14), in: Capsule())
    }
}
