import SwiftUI
import SwiftData
import AppKit

struct ReferencesBrowserView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Memo.updatedAt, order: .reverse) private var allMemos: [Memo]
    @State private var selectedID: UUID?
    @State private var searchText = ""
    @State private var newURL = ""
    @State private var draft = ""
    @State private var saveTask: Task<Void, Never>?

    private var refs: [Memo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return allMemos.filter { memo in
            guard memo.resolvedSection == .reference, !memo.isArchivedValue else { return false }
            if query.isEmpty { return true }
            return memo.content.localizedCaseInsensitiveContains(query)
        }
    }

    private var selected: Memo? {
        refs.first { $0.id == selectedID } ?? refs.first
    }

    var body: some View {
        HStack(spacing: 0) {
            listPane
            Divider().overlay(PopoverChrome.divider)
            editorPane
        }
        .onAppear {
            selectedID = selected?.id
            draft = selected?.content ?? ""
        }
        .onChange(of: selectedID) { _, _ in
            flush()
            draft = selected?.content ?? ""
        }
        .onDisappear { flush() }
    }

    private var listPane: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(PopoverChrome.inkTertiary)
                TextField("링크 · 쪽지 검색", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous)
                    .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
            )
            .padding(.horizontal, 12)
            .padding(.top, 16)

            if refs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "pin")
                        .font(.system(size: 28))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                    Text("참고 자료가 없습니다")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                    Text("URL을 붙여 넣으면 여기에 모입니다")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(refs) { memo in
                            Button {
                                selectedID = memo.id
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(memo.titleLine)
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundStyle(PopoverChrome.ink)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    if MemoClassifier.looksLikeURL(memo.content) {
                                        Text("링크")
                                            .font(.system(size: 10, weight: .bold, design: .rounded))
                                            .foregroundStyle(PopoverChrome.accent)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(
                                    selectedID == memo.id ? PopoverChrome.accentSoft.opacity(0.42) : PopoverChrome.card,
                                    in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if let url = MemoClassifier.firstURL(in: memo.content) {
                                    Button("브라우저에서 열기") { NSWorkspace.shared.open(url) }
                                }
                                Button("삭제", role: .destructive) { delete(memo) }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }

            VStack(spacing: 8) {
                TextField("https:// 또는 쪽지", text: $newURL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addReference)
                Button(action: addReference) {
                    Label("추가", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(newURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: 280)
        .background(PopoverChrome.surface)
    }

    @ViewBuilder
    private var editorPane: some View {
        if let memo = selected {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("References")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                    Spacer()
                    if let url = MemoClassifier.firstURL(in: memo.content) {
                        Button("브라우저에서 열기") { NSWorkspace.shared.open(url) }
                            .controlSize(.small)
                    }
                    Button("삭제", role: .destructive) { delete(memo) }
                        .controlSize(.small)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)

                Divider().overlay(PopoverChrome.divider)

                TextEditor(text: $draft)
                    .font(.system(size: 15, design: .rounded))
                    .scrollContentBackground(.hidden)
                    .padding(16)
                    .onChange(of: draft) { _, newValue in
                        memo.content = newValue
                        scheduleSave(memo)
                    }
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "pin")
                    .font(.system(size: 32))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                Text("자주 여는 링크나 작업 쪽지를 남겨 두세요")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                Text("데스크톱 포스트잇 위젯은 다음에 붙입니다")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func addReference() {
        let content = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        let memo = Memo(content: content, section: .reference)
        modelContext.insert(memo)
        try? modelContext.save()
        newURL = ""
        selectedID = memo.id
        draft = content
    }

    private func delete(_ memo: Memo) {
        if selectedID == memo.id { selectedID = nil }
        modelContext.delete(memo)
        try? modelContext.save()
    }

    private func scheduleSave(_ memo: Memo) {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            memo.updatedAt = Date()
            try? modelContext.save()
        }
    }

    private func flush() {
        saveTask?.cancel()
        saveTask = nil
        if let memo = selected {
            memo.updatedAt = Date()
            try? modelContext.save()
        }
    }
}
