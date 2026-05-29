import SwiftUI
import SwiftData

struct MemoListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Memo.createdAt, order: .reverse) private var allMemos: [Memo]
    @State private var editingMemo: Memo?
    @State private var editContent: String = ""
    @State private var showNewMemoField: Bool = false
    @State private var newMemoContent: String = ""
    @State private var newMemoIcon: String = MemoIcon.defaultIcon

    private var visibleMemos: [Memo] {
        let pinned = allMemos.filter { $0.isPinned }
        let recent = allMemos.filter { !$0.isPinned }
        return pinned + recent
    }

    var body: some View {
        VStack(spacing: 10) {
            if allMemos.isEmpty {
                emptyState
            } else {
                memoList
            }

            newMemoButton
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.largeTitle)
                .foregroundStyle(PopoverChrome.inkTertiary)
            Text("메모가 없습니다")
                .font(.subheadline)
                .foregroundStyle(PopoverChrome.inkSecondary)
            Text("⌘+Shift+N으로 빠르게 메모하세요")
                .font(.caption)
                .foregroundStyle(PopoverChrome.inkTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .popoverCard()
    }

    private var memoList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(visibleMemos) { memo in
                    memoRow(memo)
                }
            }
            .padding(.trailing, 12)
        }
        .frame(maxHeight: .infinity)
    }

    private func memoRow(_ memo: Memo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if editingMemo?.id == memo.id {
                editView(memo)
            } else {
                displayView(memo)
            }
        }
        .popoverCard(padding: 10, radius: 14)
    }

    private func displayView(_ memo: Memo) -> some View {
        HStack(alignment: .top, spacing: 10) {
            memoIconButton(for: memo)

            VStack(alignment: .leading, spacing: 2) {
                Text(memo.content)
                    .font(.callout)
                    .foregroundStyle(PopoverChrome.ink)
                    .lineLimit(3)
                    .textSelection(.enabled)
                HStack(spacing: 0) {
                    Text(memo.createdAt, style: .relative)
                    Text(" 전")
                }
                .font(.caption2)
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
                Divider()
                Button("삭제", role: .destructive) {
                    modelContext.delete(memo)
                    try? modelContext.save()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20)
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
                .font(.callout)
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

                        TextField("새 메모 입력...", text: $newMemoContent, axis: .vertical)
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
                            let memo = Memo(content: newMemoContent, icon: newMemoIcon)
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
                }
                .buttonStyle(LanternSecondaryButtonStyle())
            }
        }
        .padding(.bottom, 4)
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
    static let options = ["🌱", "🐜", "🚀", "📝", "☕️", "💡", "📚", "🔗", "✅", "⭐️"]

    static func label(for icon: String) -> String {
        switch icon {
        case "🌱": return "아이디어"
        case "🐜": return "작업"
        case "🚀": return "링크"
        case "📝": return "메모"
        case "☕️": return "읽을거리"
        case "💡": return "힌트"
        case "📚": return "공부"
        case "🔗": return "참고"
        case "✅": return "할 일"
        case "⭐️": return "중요"
        default: return "아이콘"
        }
    }
}
