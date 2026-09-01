import SwiftUI
import SwiftData

private enum MemoListTab: String, CaseIterable {
    case active = "오늘"
    case completed = "완료"
}

struct MemoListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Environment(\.appearanceDensity) private var appearanceDensity
    @Environment(AppState.self) private var appState
    // 이 화면은 «오늘»·«완료» 두 탭 모두 todo 만 보여준다. 거르는 일을 DB 에 시킨다.
    // `resolvedSection` 은 계산 프로퍼티라 SQL 로 번역되지 않으므로 저장 컬럼을 쓴다.
    @Query(
        filter: #Predicate<Memo> { $0.sectionRaw == "todo" },
        sort: \Memo.createdAt,
        order: .reverse
    )
    private var allMemos: [Memo]
    @State private var selectedTab: MemoListTab = .active
    @State private var editingMemo: Memo?
    @State private var editContent: String = ""
    @State private var showNewMemoField: Bool = false
    @State private var newMemoContent: String = ""
    @State private var newMemoIcon: String = MemoIcon.defaultIcon
    @State private var hostWindow: NSWindow?

    private var todayTodos: [Memo] {
        allMemos.filter { memo in
            // 섹션은 `@Query` 술어가 이미 걸렀다.
            !memo.isArchivedValue
                && !memo.isRecentlyDeleted
                && !memo.isCompletedValue
                && TodoBucket.of(
                    startDate: memo.startDate,
                    deadline: memo.deadline,
                    isCompleted: false,
                    now: Date()
                ) == .today
        }
    }

    private var activeMemos: [Memo] {
        sortedActiveMemos(todayTodos)
    }

    private var completedMemos: [Memo] {
        allMemos
            .filter {
                $0.isCompletedValue
                    && !$0.isArchivedValue
                    && !$0.isRecentlyDeleted
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var visibleMemos: [Memo] {
        selectedTab == .active ? activeMemos : completedMemos
    }

    private var hasMemoRows: Bool {
        !activeMemos.isEmpty || !completedMemos.isEmpty
    }

    private func sortedActiveMemos(_ memos: [Memo]) -> [Memo] {
        let pinned = memos.filter { $0.isPinned }
        let recent = memos.filter { !$0.isPinned }
        return pinned + recent
    }

    var body: some View {
        VStack(spacing: 10) {
            memoBrowserButton

            if hasMemoRows {
                tabPicker
            }

            if !hasMemoRows {
                emptyState
            } else {
                memoList
            }

            newMemoButton
        }
        .configureHostWindow { window in
            hostWindow = window
        }
    }

    private var memoBrowserButton: some View {
        Button {
            HubWindowPresenter.present(
                tab: .memo,
                appState: appState,
                popoverWindow: hostWindow,
                openWindow: openWindow
            )
        } label: {
            HStack(spacing: 6) {
                Text("기록 더 보기")
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(PopoverChrome.inkSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(PopoverChrome.surfaceAlt.opacity(0.84), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var tabPicker: some View {
        HStack(spacing: 4) {
            ForEach(MemoListTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 5) {
                        Text(tab.rawValue)
                        Text("\(tab == .active ? activeMemos.count : completedMemos.count)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(selectedTab == tab ? PopoverChrome.accentInk : PopoverChrome.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(selectedTab == tab ? PopoverChrome.accent : PopoverChrome.surfaceAlt.opacity(0.84), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.largeTitle)
                .foregroundStyle(PopoverChrome.inkTertiary)
            Text("오늘 할 일이 없습니다")
                .font(.subheadline)
                .foregroundStyle(PopoverChrome.inkSecondary)
            Text("아래 빠른 기록은 Quick Note로 저장됩니다")
                .font(.caption)
                .foregroundStyle(PopoverChrome.inkTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .popoverCard()
    }

    private var memoList: some View {
        Group {
            if visibleMemos.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: selectedTab == .completed ? "checkmark.circle" : "note.text")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                    Text(selectedTab == .completed ? "완료된 할 일이 없습니다" : "오늘 할 일이 없습니다")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .popoverCard()
            } else {
                ScrollView {
                    LazyVStack(spacing: appearanceDensity.popoverMetric(4)) {
                        ForEach(visibleMemos) { memo in
                            memoRow(memo)
                        }
                    }
                    .padding(.trailing, 12)
                }
                .popoverScrollbar()
                .frame(maxHeight: .infinity)
            }
        }
    }

    private func memoRow(_ memo: Memo) -> some View {
        VStack(alignment: .leading, spacing: appearanceDensity.popoverMetric(4)) {
            if editingMemo?.id == memo.id {
                editView(memo)
            } else {
                displayView(memo)
            }
        }
        .popoverCard(padding: appearanceDensity.popoverMetric(10), radius: 14)
    }

    private func displayView(_ memo: Memo) -> some View {
        HStack(alignment: .top, spacing: appearanceDensity.popoverMetric(10)) {
            memoIconButton(for: memo)

            VStack(alignment: .leading, spacing: appearanceDensity.popoverMetric(2)) {
                Text(memo.content)
                    .font(.system(size: appearanceDensity.popoverMetric(13)))
                    .foregroundStyle(PopoverChrome.ink)
                    .lineLimit(3)
                    .textSelection(.enabled)
                HStack(spacing: 0) {
                    Text(memo.createdAt, style: .relative)
                    Text(" 전")
                }
                .font(.system(size: appearanceDensity.popoverMetric(10)))
                .foregroundStyle(PopoverChrome.inkTertiary)
            }
            Spacer()
            Menu {
                Button(memo.isPinned ? "고정 해제" : "고정") {
                    memo.isPinned.toggle()
                    memo.updatedAt = Date()
                    try? modelContext.save()
                }
                Button("편집") {
                    editContent = memo.content
                    editingMemo = memo
                }
                Button(memo.isCompletedValue ? "완료 해제" : "완료") {
                    memo.isCompletedValue.toggle()
                    memo.updatedAt = Date()
                    try? modelContext.save()
                }
                Button("보관") {
                    memo.isArchivedValue = true
                    memo.updatedAt = Date()
                    try? modelContext.save()
                }
                Divider()
                Button("삭제", role: .destructive) {
                    NotificationManager.shared.cancel(identifier: "memo.deadline.\(memo.id.uuidString)")
                    if memo.isLinkedToRemindersValue {
                        try? MemoReminderLinkService.shared.removeReminder(for: memo)
                        memo.isLinkedToRemindersValue = false
                        memo.reminderIdentifier = nil
                    }
                    memo.deletedAt = Date()
                    memo.updatedAt = Date()
                    try? modelContext.save()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22)
        }
    }

    private func memoIconButton(for memo: Memo) -> some View {
        Menu {
            if memo.isPinned {
                Text("고정된 메모")
            } else {
                ForEach(MemoIcon.options, id: \.self) { icon in
                    Button {
                        memo.icon = icon
                        memo.updatedAt = Date()
                        try? modelContext.save()
                    } label: {
                        Text("\(icon) \(MemoIcon.label(for: icon))")
                    }
                }
            }
        } label: {
            Text(memo.isPinned ? MemoIcon.pinnedIcon : (memo.icon ?? MemoIcon.defaultIcon))
                .font(.system(size: 18))
                .frame(width: 26, height: 26)
                .background(PopoverChrome.surfaceAlt.opacity(0.9), in: Circle())
        }
        .buttonStyle(.plain)
        .help(memo.isPinned ? "고정된 메모" : "아이콘 변경")
    }

    private func editView(_ memo: Memo) -> some View {
        VStack(spacing: 6) {
            TextEditor(text: $editContent)
                .font(.system(size: appearanceDensity.popoverMetric(13)))
                .frame(minHeight: 40, maxHeight: 80)
                .scrollContentBackground(.hidden)

            HStack {
                Spacer()
                Button("취소") {
                    editingMemo = nil
                }
                .controlSize(.small)

                Button("저장") {
                    memo.content = editContent
                    memo.updatedAt = Date()
                    try? modelContext.save()
                    editingMemo = nil
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var newMemoButton: some View {
        Group {
            if showNewMemoField {
                VStack(spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        newMemoIconButton

                        TextField("빠른 기록...", text: $newMemoContent, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...3)
                    }

                    HStack {
                        Spacer()
                        Button("취소") {
                            showNewMemoField = false
                            newMemoContent = ""
                            newMemoIcon = MemoIcon.defaultIcon
                        }
                        .controlSize(.small)

                        Button("저장") {
                            guard !newMemoContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            let memo = Memo(content: newMemoContent, icon: newMemoIcon, section: .quickNote)
                            modelContext.insert(memo)
                            try? modelContext.save()
                            newMemoContent = ""
                            newMemoIcon = MemoIcon.defaultIcon
                            showNewMemoField = false
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.horizontal, 4)
            } else {
                Button {
                    showNewMemoField = true
                } label: {
                    Label("새 메모", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(LanternSecondaryButtonStyle())
            }
        }
        .padding(.bottom, 4)
        .companionHighlight("memo.new")
    }

    private var newMemoIconButton: some View {
        Menu {
            ForEach(MemoIcon.options, id: \.self) { icon in
                Button {
                    newMemoIcon = icon
                } label: {
                    Text("\(icon) \(MemoIcon.label(for: icon))")
                }
            }
        } label: {
            Text(newMemoIcon)
                .font(.system(size: 18))
                .frame(width: 28, height: 28)
                .background(PopoverChrome.surfaceAlt.opacity(0.9), in: Circle())
        }
        .buttonStyle(.plain)
        .help("아이콘 선택")
    }
}

enum MemoIcon {
    static let defaultIcon = "📝"
    static let pinnedIcon = "📌"
    static let options = ["💡", "🐜", "🔗", "📝", "☕️", "🌱", "📚", "📜", "⭐️"]

    static func label(for icon: String) -> String {
        switch icon {
        case "💡": return "아이디어"
        case "🐜": return "작업"
        case "🔗": return "링크"
        case "🚀": return "링크"
        case "📝": return "메모"
        case "☕️": return "읽을거리"
        case "🌱": return "영감"
        case "📚": return "공부"
        case "📜": return "참고"
        case "✅": return "완료"
        case "⭐️": return "중요"
        default: return "아이콘"
        }
    }
}
