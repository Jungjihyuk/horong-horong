import SwiftUI
import AppKit

/// vault 문서 트리와 읽기 전용 미리보기.
///
/// 화면에 남은 상태는 vault 위치(`@AppStorage`)뿐이다 — 나머지는 ViewModel 이 든다.
struct VaultBrowserView: View {
    @State private var viewModel: VaultViewModel
    @AppStorage(Constants.AppStorageKey.mindVaultPath)
    private var vaultPath: String = Constants.defaultMindVaultPath

    init(kind: VaultKind, repository: VaultRepository) {
        _viewModel = State(initialValue: VaultViewModel(kind: kind, repository: repository))
    }

    private var vaultURL: URL { URL(fileURLWithPath: vaultPath) }

    var body: some View {
        HStack(spacing: 0) {
            treePane
            Divider().overlay(PopoverChrome.divider)
            previewPane
        }
        // `.task` 는 뷰가 사라지면 자동으로 취소된다. 탭을 빨리 오갈 때
        // 이미 의미 없어진 순회가 계속 도는 것을 막는다.
        .task { await viewModel.load(vault: vaultURL) }
    }

    // MARK: - 트리

    private var treePane: some View {
        VStack(alignment: .leading, spacing: 10) {
            treeHeader
            searchField

            if viewModel.roots.isEmpty {
                missingVault
            } else {
                List(selection: selectionBinding) {
                    ForEach(viewModel.filteredRoots) { node in
                        OutlineGroup(node, children: \.listChildren) { child in
                            Label(child.name, systemImage: child.isDirectory ? "folder" : markdownIcon(child))
                                .tag(child.url)
                                .lineLimit(1)
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(width: 280)
        .background(PopoverChrome.surfaceAlt)
    }

    private var treeHeader: some View {
        HStack {
            Text(viewModel.kind.title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
            Spacer()
            if viewModel.isScanning {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    Task { await viewModel.load(vault: vaultURL, forceReload: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("다시 읽기")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(PopoverChrome.inkTertiary)
            TextField("파일명 검색", text: $viewModel.searchText)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 12)
    }

    private var missingVault: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 26))
                .foregroundStyle(PopoverChrome.inkTertiary)
            Text("vault를 찾지 못했습니다")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)
            Text(vaultPath)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(PopoverChrome.inkTertiary)
                .textSelection(.enabled)
            Button("폴더 선택") { chooseVault() }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
    }

    /// `List` 의 선택은 양방향이라 바인딩이 필요하다. 읽기는 ViewModel 에서,
    /// 쓰기는 «문서를 연다» 는 동작으로 넘긴다.
    private var selectionBinding: Binding<URL?> {
        Binding(
            get: { viewModel.selectedURL },
            set: { url in
                guard let url else { return }
                Task { await viewModel.open(url) }
            }
        )
    }

    // MARK: - 미리보기

    @ViewBuilder
    private var previewPane: some View {
        if let url = viewModel.selectedURL {
            VStack(spacing: 0) {
                previewHeader(url)
                Divider().overlay(PopoverChrome.divider)
                previewBody(url)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "book.closed")
                    .font(.system(size: 32))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                Text("왼쪽에서 문서를 고르면 읽기 전용으로 보여 줍니다")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                Text("원본은 옵시디언 vault에 그대로 둡니다")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func previewHeader(_ url: URL) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                Text(url.path.replacingOccurrences(of: vaultPath + "/", with: ""))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func previewBody(_ url: URL) -> some View {
        if url.pathExtension.lowercased() == "md" {
            if let loadError = viewModel.loadError {
                Text(loadError)
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MarkdownDocumentView(markdown: viewModel.markdown) { title in
                    Task { await viewModel.followWikiLink(title) }
                }
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "doc")
                    .font(.system(size: 30))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                Text("이 형식은 1차 뷰어에서 열지 않습니다")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                Button("Finder에서 열기") { NSWorkspace.shared.open(url) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func markdownIcon(_ node: VaultNode) -> String {
        node.url.pathExtension.lowercased() == "md" ? "doc.richtext" : "doc"
    }

    private func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = vaultURL
        panel.prompt = "선택"
        if panel.runModal() == .OK, let url = panel.url {
            vaultPath = url.path
            Task { await viewModel.load(vault: url, forceReload: true) }
        }
    }
}
