import SwiftUI
import SwiftData

struct QuickNoteBrowserView: View {
    @Environment(\.modelContext) private var modelContext
    // 정렬 키는 편집으로 바뀌지 않는 필드여야 한다. `updatedAt` 을 쓰면 기록을 고칠 때마다
    // fetch 가 무효화돼 창 전체가 재계산된다. 표시 순서는 아래 `notes` 에서 다시 정한다.
    @Query(sort: \Memo.createdAt, order: .reverse) private var allMemos: [Memo]
    @State private var selectedID: UUID?
    @State private var searchText = ""
    @State private var composerText = ""
    @State private var draft = ""
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var composerFocused: Bool

    private var notes: [Memo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return allMemos
            .filter { memo in
                guard memo.resolvedSection == .quickNote, !memo.isArchivedValue else { return false }
                if query.isEmpty { return true }
                return memo.content.localizedCaseInsensitiveContains(query)
            }
            .sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
                return $0.updatedAt > $1.updatedAt
            }
    }

    private var selected: Memo? {
        notes.first { $0.id == selectedID } ?? notes.first
    }

    var body: some View {
        HStack(spacing: 0) {
            listPane
            Divider().overlay(PopoverChrome.divider)
            editorPane
                .frame(width: 300)
        }
        .onChange(of: selectedID) { _, _ in
            flush()
            draft = selected?.content ?? ""
        }
        .onChange(of: notes.map(\.id)) { _, ids in
            if let selectedID, ids.contains(selectedID) { return }
            selectedID = ids.first
            draft = selected?.content ?? ""
        }
        .onAppear {
            selectedID = selected?.id
            draft = selected?.content ?? ""
        }
        .onDisappear { flush() }
    }

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            composer
            if notes.isEmpty {
                emptyList
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(notes) { memo in
                            noteRow(memo)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 18)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(PopoverChrome.surface)
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Quick Note")
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                Text("떠오르는 생각을 바로 적어두세요. 정리는 나중에 도와줄게요")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(PopoverChrome.inkTertiary)
                TextField("기록 검색", text: $searchText)
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
        HStack(alignment: .top, spacing: 10) {
            Text("⚡")
                .font(.system(size: 15))
                .padding(.top, 2)
            TextField("예: 내일 오전 치과, 주말에 엄마한테 전화", text: $composerText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5, design: .rounded))
                .lineLimit(1...5)
                .focused($composerFocused)
                .onSubmit(submitComposer)
            Button(action: submitComposer) {
                Text("기록")
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? PopoverChrome.accentInk.opacity(0.55) : PopoverChrome.accentInk)
                    .padding(.horizontal, 13)
                    .frame(height: 34)
                    .background(PopoverChrome.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PopoverChrome.accent.opacity(0.35), lineWidth: 1.5)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var emptyList: some View {
        Text(searchText.isEmpty ? "해당하는 기록이 없어요" : "검색과 맞는 기록이 없어요")
            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            .foregroundStyle(PopoverChrome.inkTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 36)
    }

    private func noteRow(_ memo: Memo) -> some View {
        let rest = restLine(of: memo.content)
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top, spacing: 5) {
                    if memo.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(PopoverChrome.accent)
                            .padding(.top, 3)
                    }
                    Text(memo.titleLine)
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(PopoverChrome.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                if let rest {
                    Text(rest)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .lineLimit(1)
                }
                Text(elapsed(memo.createdAt))
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { selectedID = memo.id }

            Menu {
                Button(memo.isPinned ? "고정 해제" : "고정") { togglePinned(memo) }
                Divider()
                Button("Todo로 보내기") { promoteToTodo(memo) }
                Divider()
                Button("삭제", role: .destructive) { delete(memo) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 12)
        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(
                    selectedID == memo.id ? PopoverChrome.accent : Color.clear,
                    lineWidth: 1.5
                )
        )
        .shadow(color: Color.black.opacity(selectedID == memo.id ? 0.06 : 0.03), radius: selectedID == memo.id ? 8 : 4, y: 2)
    }

    @ViewBuilder
    private var editorPane: some View {
        if let memo = selected {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("\(elapsed(memo.createdAt)) · 자동 저장됨")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                    Spacer()
                    Button {
                        togglePinned(memo)
                    } label: {
                        Label("고정", systemImage: memo.isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(memo.isPinned ? PopoverChrome.accent : PopoverChrome.inkSecondary)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(
                                memo.isPinned ? PopoverChrome.accentSoft : PopoverChrome.card,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(memo.isPinned ? Color.clear : PopoverChrome.border, lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 13)
                .padding(.bottom, 9)

                Divider().overlay(PopoverChrome.divider)

                TextEditor(text: $draft)
                    .font(.system(size: 15, design: .rounded))
                    .lineSpacing(6)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .onChange(of: draft) { _, newValue in
                        memo.content = newValue
                        scheduleSave(memo)
                    }

                VStack(alignment: .leading, spacing: 8) {
                    Text("여기서 자라면 →")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                    HStack(spacing: 7) {
                        promoteButton("Todo", systemImage: "checkmark") {
                            promoteToTodo(memo)
                        }
                        promoteButton("Knowledge", systemImage: "arrow.up") {
                            /* vault 쓰기는 다음 슬라이스 */
                        }
                        .disabled(true)
                        .help("Knowledge로 옮기기는 다음에 열립니다")
                        promoteButton("Works", systemImage: "arrow.up") {
                            /* vault 쓰기는 다음 슬라이스 */
                        }
                        .disabled(true)
                        .help("Works로 옮기기는 다음에 열립니다")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .overlay(alignment: .top) {
                    Divider().overlay(PopoverChrome.divider)
                }
            }
            .background(PopoverChrome.surfaceAlt.opacity(0.35))
        } else {
            VStack(spacing: 10) {
                Text("⚡")
                    .font(.system(size: 32))
                Text("기록을 고르면 여기서 이어 쓸 수 있어요")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(36)
        }
    }

    private func promoteButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
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
        let content = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        let memo = Memo(content: content, section: .quickNote)
        modelContext.insert(memo)
        try? modelContext.save()
        composerText = ""
        selectedID = memo.id
        draft = content
        composerFocused = true
    }

    private func togglePinned(_ memo: Memo) {
        memo.isPinned.toggle()
        persist(memo)
    }

    private func promoteToTodo(_ memo: Memo) {
        memo.assignSection(.todo)
        if memo.startDate == nil && memo.deadline == nil {
            memo.startDate = Date()
        }
        persist(memo)
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
            persist(memo)
        }
    }

    private func flush() {
        saveTask?.cancel()
        saveTask = nil
        if let memo = selected { persist(memo) }
    }

    private func persist(_ memo: Memo) {
        memo.updatedAt = Date()
        try? modelContext.save()
    }

    private func restLine(of content: String) -> String? {
        let lines = content
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count > 1 else { return nil }
        return lines.dropFirst().joined(separator: " ")
    }

    private func elapsed(_ date: Date) -> String {
        Self.elapsedFormatter.localizedString(for: date, relativeTo: Date())
    }

    /// 행마다·렌더마다 새로 만들면 로케일 데이터 로드가 그만큼 반복된다.
    private static let elapsedFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .short
        return formatter
    }()
}
