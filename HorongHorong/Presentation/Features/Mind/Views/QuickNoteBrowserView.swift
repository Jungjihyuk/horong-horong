import SwiftUI

/// Quick Note 목록과 편집기.
///
/// **`@Query`·`ModelContext` 를 쓰지 않는다.** 화면은 ViewModel 이 준 값 타입만 본다.
/// 저장·조회는 `QuickNoteRepository` 뒤에 있고, 이 파일은 SwiftData 를 import 하지 않는다.
struct QuickNoteBrowserView: View {
    @State private var viewModel: QuickNoteViewModel
    @FocusState private var composerFocused: Bool

    init(repository: QuickNoteRepository) {
        _viewModel = State(initialValue: QuickNoteViewModel(repository: repository))
    }

    var body: some View {
        HStack(spacing: 0) {
            listPane
            Divider().overlay(PopoverChrome.divider)
            editorPane
                .frame(width: 300)
        }
        .onAppear { viewModel.reload() }
        .onDisappear { viewModel.flush() }
    }

    // MARK: - 목록

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            composer
            if viewModel.notes.isEmpty {
                emptyList
            } else {
                list
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
                TextField("기록 검색", text: $viewModel.searchText)
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
            TextField("예: 내일 오전 치과, 주말에 엄마한테 전화", text: $viewModel.composerText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5, design: .rounded))
                .lineLimit(1...5)
                .focused($composerFocused)
                .onSubmit(submit)
            Button(action: submit) {
                Text("기록")
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(viewModel.canSubmitComposer ? PopoverChrome.accentInk : PopoverChrome.accentInk.opacity(0.55))
                    .padding(.horizontal, 13)
                    .frame(height: 34)
                    .background(PopoverChrome.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSubmitComposer)
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
        Text(viewModel.searchText.isEmpty ? "해당하는 기록이 없어요" : "검색과 맞는 기록이 없어요")
            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            .foregroundStyle(PopoverChrome.inkTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 36)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.notes) { note in
                    QuickNoteRowView(note: note, isSelected: viewModel.selected?.id == note.id)
                        // **메뉴를 행 밖에 둔 이유**: 행이 동작 클로저를 들면 `Equatable` 합성이
                        // 깨져 값이 그대로여도 매번 다시 그린다(CLAUDE.md §5 «행은 값으로»).
                        .overlay(alignment: .topTrailing) { rowMenu(note) }
                        .contentShape(Rectangle())
                        .onTapGesture { viewModel.select(note.id) }
                }
                if viewModel.canLoadMore {
                    // 목록 끝에 실제로 닿았을 때만 다음 쪽을 청한다.
                    Color.clear
                        .frame(height: 1)
                        .onAppear { viewModel.loadMore() }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
    }

    private func rowMenu(_ note: QuickNote) -> some View {
        Menu {
            Button(note.isPinned ? "고정 해제" : "고정") { viewModel.togglePinned(note.id) }
            Divider()
            Button("Todo로 보내기") { viewModel.promoteToTodo(note.id) }
            Divider()
            Button("삭제", role: .destructive) { viewModel.delete(note.id) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PopoverChrome.inkSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .padding(.trailing, 8)
        .padding(.top, 12)
    }

    // MARK: - 편집기

    @ViewBuilder
    private var editorPane: some View {
        if let note = viewModel.selected {
            VStack(alignment: .leading, spacing: 0) {
                editorHeader(note)

                Divider().overlay(PopoverChrome.divider)

                TextEditor(text: $viewModel.draft)
                    .font(.system(size: 15, design: .rounded))
                    .lineSpacing(6)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .onChange(of: viewModel.draft) { _, _ in viewModel.draftChanged() }

                promoteBar(note)
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

    private func editorHeader(_ note: QuickNote) -> some View {
        HStack {
            Text("\(QuickNoteElapsed.text(note.createdAt)) · 자동 저장됨")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
            Spacer()
            Button {
                viewModel.togglePinned(note.id)
            } label: {
                Label("고정", systemImage: note.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(note.isPinned ? PopoverChrome.accent : PopoverChrome.inkSecondary)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(
                        note.isPinned ? PopoverChrome.accentSoft : PopoverChrome.card,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(note.isPinned ? Color.clear : PopoverChrome.border, lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .padding(.bottom, 9)
    }

    private func promoteBar(_ note: QuickNote) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("여기서 자라면 →")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
            HStack(spacing: 7) {
                promoteButton("Todo", systemImage: "checkmark") {
                    viewModel.promoteToTodo(note.id)
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

    private func submit() {
        viewModel.submitComposer()
        composerFocused = true
    }
}

/// 목록의 한 행. **값만 들고 있어 `Equatable` 이 성립한다** — 내용이 그대로면 다시 그리지 않는다.
private struct QuickNoteRowView: View, Equatable {
    let note: QuickNote
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 5) {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(PopoverChrome.accent)
                        .padding(.top, 3)
                }
                Text(note.title)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            if let rest = note.rest {
                Text(rest)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .lineLimit(1)
            }
            Text(QuickNoteElapsed.text(note.createdAt))
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 14)
        // 오른쪽 위 메뉴 버튼(28pt + 여백 8pt) 자리를 비워 둔다.
        .padding(.trailing, 36)
        .padding(.vertical, 12)
        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(isSelected ? PopoverChrome.accent : Color.clear, lineWidth: 1.5)
        )
        .shadow(color: Color.black.opacity(isSelected ? 0.06 : 0.03), radius: isSelected ? 8 : 4, y: 2)
    }
}

/// 행마다·렌더마다 새로 만들면 로케일 데이터 로드가 그만큼 반복된다.
///
/// `@MainActor` 인 이유: `RelativeDateTimeFormatter` 는 `Sendable` 이 아니라 그냥 `static let`
/// 으로 두면 Swift 6 에서 컴파일되지 않는다. 부르는 곳이 뷰뿐이라 격리로 막는 편이 간단하다.
@MainActor
private enum QuickNoteElapsed {
    static func text(_ date: Date) -> String {
        formatter.localizedString(for: date, relativeTo: Date())
    }

    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .short
        return formatter
    }()
}
