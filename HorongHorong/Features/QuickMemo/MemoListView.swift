import SwiftUI

/// 팝오버가 보여줄 할 일 묶음.
///
/// 완료 목록 대신 «예정» 을 둔다 — 팝오버는 **앞으로 할 것**을 확인하는 자리이고,
/// 끝난 일을 되짚는 것은 기록 창의 Todo 탭이 맡는다.
/// 팝오버 메모 탭의 두 갈래. ViewModel 도 쓰므로 파일 밖에서 보인다.
enum MemoListTab: String, CaseIterable {
    case today = "오늘"
    case upcoming = "예정"
}

struct MemoListView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.appearanceDensity) private var appearanceDensity
    @Environment(AppState.self) private var appState

    @State private var viewModel: MemoListViewModel
    @State private var selectedTab: MemoListTab = .today
    @State private var editingMemoID: UUID?
    @State private var editContent: String = ""
    @State private var showNewMemoField: Bool = false
    @State private var newMemoContent: String = ""
    @State private var newMemoIcon: String = MemoIcon.defaultIcon
    @State private var hostWindow: NSWindow?

    init(repository: TodoRepository, quickNotes: QuickNoteRepository) {
        _viewModel = State(initialValue: MemoListViewModel(repository: repository, quickNotes: quickNotes))
    }

    private var visibleMemos: [TodoItem] { viewModel.rows(for: selectedTab) }
    private var hasMemoRows: Bool { viewModel.hasRows }

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
        .onAppear { viewModel.reload() }
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
                        Text("\(viewModel.rows(for: tab).count)")
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
                    Image(systemName: selectedTab == .upcoming ? "calendar" : "note.text")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                    Text(selectedTab == .upcoming ? "예정된 할 일이 없습니다" : "오늘 할 일이 없습니다")
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

    private func memoRow(_ memo: TodoItem) -> some View {
        VStack(alignment: .leading, spacing: appearanceDensity.popoverMetric(4)) {
            if editingMemoID == memo.id {
                editView(memo)
            } else {
                displayView(memo)
            }
        }
        .popoverCard(padding: appearanceDensity.popoverMetric(10), radius: 14)
    }

    private func displayView(_ memo: TodoItem) -> some View {
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
                Button(memo.isPinned ? "고정 해제" : "고정") { viewModel.togglePinned(memo) }
                Button("편집") {
                    editContent = memo.content
                    editingMemoID = memo.id
                }
                Button(memo.isCompleted ? "완료 해제" : "완료") { viewModel.toggleCompleted(memo) }
                Divider()
                // 알림 취소와 미리알림 연동 해제는 저장소가 함께 한다.
                Button("삭제", role: .destructive) { viewModel.delete(memo.id) }
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

    private func memoIconButton(for memo: TodoItem) -> some View {
        Menu {
            if memo.isPinned {
                Text("고정된 메모")
            } else {
                ForEach(MemoIcon.options, id: \.self) { icon in
                    Button {
                        viewModel.setIcon(memo.id, icon: icon)
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

    private func editView(_ memo: TodoItem) -> some View {
        VStack(spacing: 6) {
            TextEditor(text: $editContent)
                .font(.system(size: appearanceDensity.popoverMetric(13)))
                .frame(minHeight: 40, maxHeight: 80)
                .scrollContentBackground(.hidden)

            HStack {
                Spacer()
                Button("취소") {
                    editingMemoID = nil
                }
                .controlSize(.small)

                Button("저장") {
                    viewModel.updateContent(memo.id, content: editContent)
                    editingMemoID = nil
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
                            viewModel.addQuickNote(content: newMemoContent, icon: newMemoIcon)
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
