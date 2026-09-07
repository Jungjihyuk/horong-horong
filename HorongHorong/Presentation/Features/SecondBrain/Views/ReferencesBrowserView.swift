import SwiftUI
import AppKit

/// 참고 자료 — 링크 카드와 포스트잇 쪽지.
///
/// **`@Query`·`ModelContext` 를 쓰지 않는다.** 화면은 ViewModel 이 준 값 타입만 본다.
struct ReferencesBrowserView: View {
    @State private var viewModel: ReferencesViewModel

    private let repository: ReferenceRepository

    init(repository: ReferenceRepository) {
        self.repository = repository
        _viewModel = State(initialValue: ReferencesViewModel(repository: repository))
    }

    var body: some View {
        HStack(spacing: 0) {
            gridPane
            Divider().overlay(PopoverChrome.divider)
            detailPane
                .frame(width: 300)
        }
        .onAppear { viewModel.reload() }
        .onDisappear { viewModel.flush() }
        // 위젯 창에서 고친 내용이 여기에도 바로 비쳐야 한다.
        .onReceive(NotificationCenter.default.publisher(for: ReferenceChangeBroadcast.name)) { notification in
            guard let id = ReferenceChangeBroadcast.id(from: notification) else { return }
            viewModel.refreshExternally(id: id)
        }
    }

    // MARK: - 목록

    private var gridPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            modeBar
            grid
        }
        .frame(maxWidth: .infinity)
        .background(PopoverChrome.surface)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                // **제목은 접지 않는다.** 검색 칸이 폭을 먼저 차지하면 «Referenc / es» 로 잘린다.
                Text("References")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .lineLimit(2)
            }
            .layoutPriority(1)
            Spacer(minLength: 6)
            searchField
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var subtitle: String {
        let total = viewModel.references.count
        guard viewModel.widgetCount > 0 else {
            return "링크와 쪽지 \(total)개 · 쪽지를 위젯으로 꺼내 창 위에 둘 수 있어요"
        }
        return "링크와 쪽지 \(total)개 · 위젯 \(viewModel.widgetCount)개 띄움"
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(PopoverChrome.inkTertiary)
            TextField("검색", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .rounded))
        }
        .padding(.horizontal, 10)
        // 좁아지면 검색 칸이 먼저 줄어든다 — 돋보기와 몇 글자는 남는다.
        .frame(minWidth: 96, maxWidth: 200)
        .frame(height: 30)
        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(PopoverChrome.border, lineWidth: 0.5)
        )
    }

    private var modeBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                modeButton(nil, "전체")
                modeButton(.link, "링크")
                modeButton(.note, "쪽지")
            }
            .padding(3)
            .background(PopoverChrome.surfaceAlt, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Spacer(minLength: 0)

            addButton("링크", kind: .link)
            addButton("쪽지", kind: .note)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func modeButton(_ kind: ReferenceKind?, _ label: String) -> some View {
        let isActive = viewModel.mode == kind
        return Button { viewModel.mode = kind } label: {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(isActive ? PopoverChrome.selectionInk : PopoverChrome.inkSecondary)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(
                    isActive ? PopoverChrome.selectionFill : .clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func addButton(_ label: String, kind: ReferenceKind) -> some View {
        Button { viewModel.add(kind: kind) } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                Text(label).font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(PopoverChrome.inkSecondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(PopoverChrome.border, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var grid: some View {
        if viewModel.references.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 12)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(viewModel.references) { item in
                        card(item)
                            .onTapGesture { viewModel.select(item.id) }
                            .contextMenu {
                                if let url = item.linkURL {
                                    Button("브라우저에서 열기") { NSWorkspace.shared.open(url) }
                                }
                                Button("삭제", role: .destructive) { viewModel.delete(item.id) }
                            }
                    }
                    if viewModel.canLoadMore {
                        // 목록 끝에 실제로 닿았을 때만 다음 쪽을 청한다.
                        Color.clear
                            .frame(height: 1)
                            .onAppear { viewModel.loadMore() }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }

    @ViewBuilder
    private func card(_ item: ReferenceItem) -> some View {
        let isSelected = viewModel.selected?.id == item.id
        switch item.kind {
        case .link:
            ReferenceLinkCard(item: item, isSelected: isSelected).equatable()
        case .note:
            ReferenceNoteCard(item: item, isSelected: isSelected).equatable()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "pin")
                .font(.system(size: 30))
                .foregroundStyle(PopoverChrome.inkTertiary)
            Text(viewModel.searchText.isEmpty ? "아직 비어 있어요" : "해당하는 항목이 없어요")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)
            Text("자주 여는 링크나 붙여 둘 쪽지를 더해 보세요")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 상세

    @ViewBuilder
    private var detailPane: some View {
        if let item = viewModel.selected {
            VStack(alignment: .leading, spacing: 0) {
                detailHeader(item)
                Divider().overlay(PopoverChrome.divider)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        titleField
                        if item.kind == .link {
                            linkEditor(item)
                        } else {
                            noteEditor(item)
                        }
                    }
                    .padding(16)
                }
            }
            .background(PopoverChrome.surfaceAlt)
        } else {
            placeholder
        }
    }

    private func detailHeader(_ item: ReferenceItem) -> some View {
        HStack(spacing: 8) {
            Text(item.kind.title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
            Spacer(minLength: 0)
            Button { viewModel.delete(item.id) } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("삭제")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var titleField: some View {
        TextField("제목", text: $viewModel.titleDraft)
            .textFieldStyle(.plain)
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(PopoverChrome.ink)
            .onChange(of: viewModel.titleDraft) { _, _ in viewModel.draftChanged() }
    }

    private func linkEditor(_ item: ReferenceItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ReferenceBadge(seed: item.host ?? item.title, size: 26)
                TextField("https://", text: $viewModel.urlDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .rounded))
                    .onChange(of: viewModel.urlDraft) { _, _ in viewModel.draftChanged() }
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(PopoverChrome.border, lineWidth: 0.5)
            )

            if let url = item.linkURL {
                Button {
                    viewModel.flush()
                    NSWorkspace.shared.open(url)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "link").font(.system(size: 10, weight: .bold))
                        Text("\(item.host ?? "링크") 열기")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(PopoverChrome.accentInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(PopoverChrome.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func noteEditor(_ item: ReferenceItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                ForEach(ReferenceNoteColor.allCases) { color in
                    Button { viewModel.setColor(color) } label: {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(color.paper)
                            .frame(width: 24, height: 24)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(item.color == color ? PopoverChrome.accent : color.edge, lineWidth: item.color == color ? 2 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(color.rawValue)
                }
                Spacer(minLength: 0)
            }

            Button { viewModel.setWidget(!item.isWidget) } label: {
                Text(item.isWidget ? "위젯에서 내리기" : "위젯으로 꺼내기")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(item.isWidget ? PopoverChrome.accentInk : PopoverChrome.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background(
                        item.isWidget ? PopoverChrome.accent : PopoverChrome.card,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(item.isWidget ? .clear : PopoverChrome.border, lineWidth: 0.5)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ZStack(alignment: .topLeading) {
                StickyNoteShape(color: item.color)
                TextEditor(text: $viewModel.bodyDraft)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(item.color.ink)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .onChange(of: viewModel.bodyDraft) { _, _ in viewModel.draftChanged() }
            }
            .frame(minHeight: 200)
            .shadow(color: .black.opacity(0.09), radius: 6, y: 3)
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "pin")
                .font(.system(size: 30))
                .foregroundStyle(PopoverChrome.inkTertiary)
            Text("항목을 고르면 여기서 다듬을 수 있어요")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PopoverChrome.surfaceAlt)
    }
}

/// 도메인 첫 글자 배지.
struct ReferenceBadge: View, Equatable {
    let seed: String
    var size: CGFloat = 20

    var body: some View {
        Text(ReferencePalette.badgeLetter(for: seed))
            .font(.system(size: size * 0.48, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(ReferencePalette.badgeTint(for: seed), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// 링크 카드. **값만 들고 있어 `Equatable` 이 성립한다**(R3).
struct ReferenceLinkCard: View, Equatable {
    let item: ReferenceItem
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ReferenceBadge(seed: item.host ?? item.title)
                Text(item.host ?? "링크 없음")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .lineLimit(1)
            }
            Text(item.displayTitle)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            Text(ReferenceDateText.elapsed(item.updatedAt))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
        }
        .padding(12)
        .frame(minHeight: 128, alignment: .topLeading)
        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? PopoverChrome.accent : PopoverChrome.border, lineWidth: isSelected ? 1.5 : 0.5)
        )
        .contentShape(Rectangle())
    }
}

/// 포스트잇 쪽지 카드.
struct ReferenceNoteCard: View, Equatable {
    let item: ReferenceItem
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            StickyNoteShape(color: item.color)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.displayTitle)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text(item.body.isEmpty ? "비어 있는 쪽지" : item.body)
                    .font(.system(size: 12, design: .rounded))
                    .lineLimit(5)
                    .multilineTextAlignment(.leading)
                    .opacity(item.body.isEmpty ? 0.5 : 0.85)
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    if item.isWidget {
                        Text("위젯")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    Spacer(minLength: 0)
                    Text(ReferenceDateText.elapsed(item.updatedAt))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .opacity(0.55)
                }
            }
            .foregroundStyle(item.color.ink)
            .padding(12)
        }
        .frame(minHeight: 128, alignment: .topLeading)
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 0, bottomTrailingRadius: 3, topTrailingRadius: 3, style: .continuous)
                .stroke(isSelected ? PopoverChrome.accent : .clear, lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.09), radius: 5, y: 2)
        .contentShape(Rectangle())
    }
}

@MainActor
enum ReferenceDateText {
    /// "4시간 전". 정확한 날짜보다 «얼마나 오래됐나» 가 목록에서 더 쓸모 있다.
    static func elapsed(_ date: Date) -> String {
        formatter.localizedString(for: date, relativeTo: Date())
    }

    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .short
        return formatter
    }()
}
