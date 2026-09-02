import SwiftUI
import SwiftData

struct QuickNoteBrowserView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedID: UUID?
    @State private var searchText = ""
    @State private var composerText = ""
    @State private var draft = ""
    @State private var saveTask: Task<Void, Never>?
    /// 한 번에 가져올 개수. 목록 끝에 닿으면 늘린다.
    ///
    /// 전량을 가져오면 상주량이 기록 수에 비례한다 —
    /// 실측 2026-09-02: 4,333건 fetch 50.5ms 대 50건 fetch 1.4ms (**36배**).
    @State private var pageLimit = Self.pageSize
    @FocusState private var composerFocused: Bool

    private static let pageSize = 50

    private var selected: Memo? {
        guard let selectedID else { return nil }
        return memo(id: selectedID)
    }

    /// 에디터가 볼 기록 한 건만 가져온다.
    ///
    /// 예전에는 목록 배열에서 찾았는데, 그러면 **에디터가 목록 전체에 의존**한다.
    /// 페이징을 하면 선택한 기록이 현재 페이지 밖일 수 있어 그 방식이 성립하지 않는다.
    private func memo(id: UUID) -> Memo? {
        var descriptor = FetchDescriptor<Memo>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
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
        .onAppear {
            draft = selected?.content ?? ""
        }
        .onDisappear { flush() }
    }

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            composer
            QuickNoteList(
                searchText: searchText,
                limit: pageLimit,
                row: { noteRow($0) },
                empty: { emptyList },
                onReachEnd: { pageLimit += Self.pageSize },
                // 목록을 자식이 들고 있으므로, 선택이 사라졌는지도 자식이 알려준다.
                onVisibleChange: { ids in
                    if let selectedID, ids.contains(selectedID) { return }
                    selectedID = ids.first
                    draft = selected?.content ?? ""
                }
            )
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

/// 페이징된 기록 목록.
///
/// **별도 struct 인 이유**: `@Query` 의 `FetchDescriptor` 는 뷰가 만들어질 때 고정된다.
/// 개수를 늘리려면 그 뷰를 다시 만들어야 하므로, 개수를 인자로 받는 자식으로 뗀다.
/// 부모가 `limit` 을 늘리면 이 뷰가 새 descriptor 로 다시 생긴다.
private struct QuickNoteList<Row: View, Empty: View>: View {
    /// 고정한 기록. **개수를 제한하지 않는다** — 몇 건 안 되고, 항상 맨 위에 있어야 한다.
    @Query private var pinned: [Memo]
    /// 나머지. 이쪽만 페이징한다.
    @Query private var others: [Memo]

    private let row: (Memo) -> Row
    private let empty: () -> Empty
    private let onReachEnd: () -> Void
    private let onVisibleChange: ([UUID]) -> Void
    private let isPaged: Bool
    private let searchQuery: String
    private let limit: Int

    init(
        searchText: String,
        limit: Int,
        @ViewBuilder row: @escaping (Memo) -> Row,
        @ViewBuilder empty: @escaping () -> Empty,
        onReachEnd: @escaping () -> Void,
        onVisibleChange: @escaping ([UUID]) -> Void
    ) {
        self.row = row
        self.empty = empty
        self.onReachEnd = onReachEnd
        self.onVisibleChange = onVisibleChange
        self.limit = limit

        // 검색 중에는 개수를 제한하지 않는다.
        // `localizedCaseInsensitiveContains` 는 SQL 로 번역되지 않아 앱에서 걸러야 하는데,
        // 앞 50건만 가져와서 거르면 **51번째부터는 검색해도 안 나온다.**
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.searchQuery = query
        self.isPaged = query.isEmpty

        // 고정 여부로 쿼리를 둘로 나누는 이유: `Bool` 은 `Comparable` 이 아니라
        // `SortDescriptor` 의 정렬 키가 될 수 없다. «고정 먼저» 를 DB 정렬로 표현할 방법이 없다.
        //
        // 그리고 한 쿼리에 제한을 걸면 고정한 기록이 51번째에 있을 때 아예 안 보인다.
        // 나눠 두면 고정은 항상 전부, 나머지만 잘라 온다.
        _pinned = Query(FetchDescriptor<Memo>(
            // `!= true` 가 NULL 을 빠뜨리지 않는 것은 `normalizeMemoFlags` 가 메워 주기 때문이다.
            predicate: #Predicate { $0.sectionRaw == "quickNote" && $0.isArchived != true && $0.isPinned },
            sortBy: [SortDescriptor(\Memo.updatedAt, order: .reverse)]
        ))

        var rest = FetchDescriptor<Memo>(
            predicate: #Predicate { $0.sectionRaw == "quickNote" && $0.isArchived != true && !$0.isPinned },
            sortBy: [SortDescriptor(\Memo.updatedAt, order: .reverse)]
        )
        if query.isEmpty { rest.fetchLimit = limit }
        _others = Query(rest)
    }

    var body: some View {
        let visible = filtered
        if visible.isEmpty {
            empty()
                .onAppear { onVisibleChange([]) }
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(visible) { memo in
                        row(memo)
                    }
                    if isPaged, others.count >= limit {
                        // 가져온 만큼 다 찼다는 건 더 있을 수 있다는 뜻이다.
                        // 목록 끝이 실제로 화면에 닿을 때만 다음 쪽을 청한다.
                        Color.clear
                            .frame(height: 1)
                            .onAppear(perform: onReachEnd)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
            .onChange(of: visible.map(\.id), initial: true) { _, ids in
                onVisibleChange(ids)
            }
        }
    }

    /// 검색어는 `localizedCaseInsensitiveContains` 라 SQL 로 번역되지 않는다.
    /// 그래서 여기서 거르고, 대신 검색 중에는 개수 제한을 두지 않는다(위 `init` 참고).
    private var filtered: [Memo] {
        let all = pinned + others
        guard !searchQuery.isEmpty else { return all }
        return all.filter { $0.content.localizedCaseInsensitiveContains(searchQuery) }
    }
}
