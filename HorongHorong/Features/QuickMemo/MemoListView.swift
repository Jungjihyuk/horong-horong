import SwiftUI
import SwiftData

struct MemoListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Memo.createdAt, order: .reverse) private var allMemos: [Memo]
    @State private var editingMemo: Memo?
    @State private var editContent: String = ""
    @State private var showNewMemoField: Bool = false
    @State private var newMemoContent: String = ""

    private var pinnedMemos: [Memo] {
        allMemos.filter { $0.isPinned }
    }

    private var recentMemos: [Memo] {
        Array(allMemos.filter { !$0.isPinned }.prefix(5))
    }

    var body: some View {
        VStack(spacing: 8) {
            if allMemos.isEmpty {
                emptyState
            } else {
                memoList
            }

            Divider()
            newMemoButton
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("메모가 없습니다")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("⌘+Shift+N으로 빠르게 메모하세요")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private var memoList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(pinnedMemos) { memo in
                    memoRow(memo, isPinned: true)
                }
                ForEach(recentMemos) { memo in
                    memoRow(memo, isPinned: false)
                }
            }
        }
        .frame(maxHeight: 300)
    }

    private func memoRow(_ memo: Memo, isPinned: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if editingMemo?.id == memo.id {
                editView(memo)
            } else {
                displayView(memo, isPinned: isPinned)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func displayView(_ memo: Memo, isPinned: Bool) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                if isPinned {
                    Label("고정됨", systemImage: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Text(memo.content)
                    .font(.callout)
                    .lineLimit(3)
                    .textSelection(.enabled)
                Text(memo.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Menu {
                Button(memo.isPinned ? "고정 해제" : "고정") {
                    memo.isPinned.toggle()
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
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20)
        }
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
                    TextField("새 메모 입력...", text: $newMemoContent, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)

                    HStack {
                        Spacer()
                        Button("취소") {
                            showNewMemoField = false
                            newMemoContent = ""
                        }
                        .controlSize(.small)

                        Button("저장") {
                            guard !newMemoContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            let memo = Memo(content: newMemoContent)
                            modelContext.insert(memo)
                            try? modelContext.save()
                            newMemoContent = ""
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
                .buttonStyle(.borderless)
            }
        }
        .padding(.bottom, 4)
    }
}
