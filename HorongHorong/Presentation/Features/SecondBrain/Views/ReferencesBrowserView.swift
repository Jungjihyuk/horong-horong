import SwiftUI
import AppKit

/// 참고 자료 목록과 편집기.
///
/// **`@Query`·`ModelContext` 를 쓰지 않는다.** 화면은 ViewModel 이 준 값 타입만 본다.
/// 저장·조회는 `ReferenceRepository` 뒤에 있고, 이 파일은 SwiftData 를 import 하지 않는다.
struct ReferencesBrowserView: View {
    @State private var viewModel: ReferencesViewModel

    init(repository: ReferenceRepository) {
        _viewModel = State(initialValue: ReferencesViewModel(repository: repository))
    }

    var body: some View {
        HStack(spacing: 0) {
            listPane
            Divider().overlay(PopoverChrome.divider)
            editorPane
        }
        .onAppear { viewModel.reload() }
        .onDisappear { viewModel.flush() }
    }

    private var listPane: some View {
        VStack(spacing: 12) {
            searchField
            if viewModel.references.isEmpty {
                emptyList
            } else {
                list
            }
            composer
        }
        .frame(width: 280)
        .background(PopoverChrome.surface)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(PopoverChrome.inkTertiary)
            TextField("링크 · 쪽지 검색", text: $viewModel.searchText)
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
    }

    private var emptyList: some View {
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
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.references) { reference in
                    ReferenceRowView(
                        reference: reference,
                        isSelected: viewModel.selected?.id == reference.id
                    )
                    .onTapGesture { viewModel.select(reference.id) }
                    .contextMenu {
                        if let url = reference.linkURL {
                            Button("브라우저에서 열기") { NSWorkspace.shared.open(url) }
                        }
                        Button("삭제", role: .destructive) { viewModel.delete(reference.id) }
                    }
                }
                if viewModel.canLoadMore {
                    // 목록 끝에 실제로 닿았을 때만 다음 쪽을 청한다.
                    Color.clear
                        .frame(height: 1)
                        .onAppear { viewModel.loadMore() }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            TextField("https:// 또는 쪽지", text: $viewModel.newContent)
                .textFieldStyle(.roundedBorder)
                .onSubmit { viewModel.add() }
            Button { viewModel.add() } label: {
                Label("추가", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.newContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var editorPane: some View {
        if let reference = viewModel.selected {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("References")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                    Spacer()
                    if let url = reference.linkURL {
                        Button("브라우저에서 열기") { NSWorkspace.shared.open(url) }
                            .controlSize(.small)
                    }
                    Button("삭제", role: .destructive) { viewModel.delete(reference.id) }
                        .controlSize(.small)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)

                Divider().overlay(PopoverChrome.divider)

                TextEditor(text: $viewModel.draft)
                    .font(.system(size: 15, design: .rounded))
                    .scrollContentBackground(.hidden)
                    .padding(16)
                    .onChange(of: viewModel.draft) { _, _ in viewModel.draftChanged() }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
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

/// 목록 한 줄. **값 타입을 받는 `struct` 라 자기만의 렌더 경계를 가진다**(CLAUDE.md R3).
private struct ReferenceRowView: View, Equatable {
    let reference: ReferenceItem
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(reference.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if reference.isLink {
                Text("링크")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            isSelected ? PopoverChrome.accentSoft.opacity(0.42) : PopoverChrome.card,
            in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous)
        )
        .contentShape(Rectangle())
    }
}
