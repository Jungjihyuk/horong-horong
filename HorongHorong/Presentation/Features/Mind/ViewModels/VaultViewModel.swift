import Foundation
import Observation

/// Knowledge·Works 화면의 상태.
///
/// SwiftData 를 쓰지 않는 기능이라 `@Query` 문제는 없었다. 그래도 옮긴 이유는
/// **읽기 로직이 화면에 붙어 있으면 검사할 수 없어서**다 — 검색 필터·늦게 온 응답 버리기
/// 같은 규칙이 여기 있다.
@MainActor
@Observable
final class VaultViewModel {
    let kind: VaultKind

    private(set) var roots: [VaultNode] = []
    private(set) var selectedURL: URL?
    private(set) var markdown = ""
    private(set) var loadError: String?
    private(set) var isScanning = false

    var searchText = ""

    private let repository: VaultRepository
    private var wikiIndex: [String: [URL]] = [:]

    init(kind: VaultKind, repository: VaultRepository) {
        self.kind = kind
        self.repository = repository
    }

    /// 검색어에 맞는 가지만 남긴 트리. 폴더 이름이 맞으면 그 아래는 통째로 남긴다.
    var filteredRoots: [VaultNode] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return roots }
        return roots.compactMap { Self.filter($0, query: query) }
    }

    func load(vault: URL, forceReload: Bool = false) async {
        isScanning = true
        let scan = await repository.scan(kind: kind, vault: vault, forceReload: forceReload)
        isScanning = false
        guard !Task.isCancelled else { return }

        roots = scan.roots
        wikiIndex = scan.wikiIndex
        if let selectedURL { await open(selectedURL) }
    }

    func open(_ url: URL) async {
        selectedURL = url
        loadError = nil
        markdown = ""
        guard url.pathExtension.lowercased() == "md" else { return }

        let result = await repository.document(at: url)
        // 읽는 사이에 사용자가 다른 문서를 골랐으면 늦게 온 결과를 버린다.
        guard selectedURL == url else { return }
        if let result {
            markdown = result
        } else {
            loadError = "파일을 읽지 못했습니다"
        }
    }

    /// `[[제목]]` 을 눌렀을 때. 가리키는 문서가 없으면 아무 일도 하지 않는다.
    func followWikiLink(_ title: String) async {
        guard let target = repository.resolveWikiLink(title, from: selectedURL, in: wikiIndex) else { return }
        await open(target)
    }

    private static func filter(_ node: VaultNode, query: String) -> VaultNode? {
        if node.name.localizedCaseInsensitiveContains(query) { return node }
        let children = node.children.compactMap { filter($0, query: query) }
        guard !children.isEmpty else { return nil }
        return VaultNode(name: node.name, url: node.url, isDirectory: node.isDirectory, children: children)
    }
}
