import SwiftUI
import AppKit

struct VaultBrowserView: View {
    let kind: VaultKind
    @AppStorage(Constants.AppStorageKey.personalRecordVaultPath)
    private var vaultPath: String = Constants.defaultSecondBrainVaultPath
    @State private var roots: [VaultNode] = []
    @State private var selectedURL: URL?
    @State private var markdown: String = ""
    @State private var loadError: String?
    @State private var wikiIndex: [String: [URL]] = [:]
    @State private var searchText = ""
    @State private var isScanning = false

    private var vaultURL: URL {
        URL(fileURLWithPath: vaultPath)
    }

    var body: some View {
        HStack(spacing: 0) {
            treePane
            Divider().overlay(PopoverChrome.divider)
            previewPane
        }
        // `.task` 는 뷰가 사라지면 자동으로 취소된다. 탭을 빨리 오갈 때
        // 이미 의미 없어진 순회가 계속 도는 것을 막는다.
        .task { await load() }
    }

    private var treePane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(kind.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                Spacer()
                if isScanning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        Task { await load(forceReload: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("다시 읽기")
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(PopoverChrome.inkTertiary)
                TextField("파일명 검색", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 12)

            if roots.isEmpty {
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
            } else {
                List(selection: $selectedURL) {
                    ForEach(filteredRoots) { node in
                        OutlineGroup(node, children: \.listChildren) { child in
                            Label(child.name, systemImage: child.isDirectory ? "folder" : markdownIcon(child))
                                .tag(child.url)
                                .lineLimit(1)
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .onChange(of: selectedURL) { _, url in
                    if let url { open(url) }
                }
            }
        }
        .frame(width: 280)
        .background(PopoverChrome.surfaceAlt)
    }

    @ViewBuilder
    private var previewPane: some View {
        if let url = selectedURL {
            VStack(spacing: 0) {
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
                Divider().overlay(PopoverChrome.divider)
                if url.pathExtension.lowercased() == "md" {
                    if let loadError {
                        Text(loadError)
                            .foregroundStyle(PopoverChrome.inkSecondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        MarkdownDocumentView(markdown: markdown) { title in
                            if let target = VaultCatalog.resolveWikiLink(
                                title, from: selectedURL, in: wikiIndex
                            ) {
                                selectedURL = target
                            }
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

    private var filteredRoots: [VaultNode] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return roots }
        return roots.compactMap { filter($0, query: query) }
    }

    private func filter(_ node: VaultNode, query: String) -> VaultNode? {
        if node.name.localizedCaseInsensitiveContains(query) { return node }
        let children = node.children.compactMap { filter($0, query: query) }
        guard !children.isEmpty else { return nil }
        return VaultNode(name: node.name, url: node.url, isDirectory: node.isDirectory, children: children)
    }

    private func markdownIcon(_ node: VaultNode) -> String {
        node.url.pathExtension.lowercased() == "md" ? "doc.richtext" : "doc"
    }

    /// 순회는 `VaultScanner`(actor) 가 백그라운드에서 하고, 결과만 받아 화면에 꽂는다.
    /// 두 번째부터는 액터의 캐시가 바로 답해서 탭을 오가도 다시 훑지 않는다.
    private func load(forceReload: Bool = false) async {
        isScanning = true
        defer { isScanning = false }

        let scan = await VaultScanner.shared.scan(
            kind: kind,
            vault: vaultURL,
            forceReload: forceReload
        )
        guard !Task.isCancelled else { return }

        roots = scan.roots
        wikiIndex = scan.wikiIndex
        if let selectedURL { open(selectedURL) }
    }

    private func open(_ url: URL) {
        loadError = nil
        guard url.pathExtension.lowercased() == "md" else {
            markdown = ""
            return
        }
        markdown = ""
        Task {
            // 큰 노트를 메인 스레드에서 읽으면 그동안 화면이 멈춘다.
            let result = await Task.detached(priority: .userInitiated) {
                try? String(contentsOf: url, encoding: .utf8)
            }.value

            // 읽는 사이에 사용자가 다른 문서를 골랐으면 늦게 온 결과를 버린다.
            guard selectedURL == url else { return }
            if let result {
                markdown = result
            } else {
                loadError = "파일을 읽지 못했습니다"
            }
        }
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
            Task { await load(forceReload: true) }
        }
    }
}
