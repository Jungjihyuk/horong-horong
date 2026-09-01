import Foundation

enum VaultKind: Sendable {
    case knowledge
    case works

    var title: String {
        switch self {
        case .knowledge: return "Knowledge"
        case .works: return "Works"
        }
    }
}

struct VaultRoot: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let title: String
    let url: URL
    /// vault 루트 기준 상대 경로. 이 폴더와 그 하위는 트리에서 뺀다.
    let excludedRelativePaths: [String]
}

struct VaultNode: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let name: String
    let url: URL
    let isDirectory: Bool
    var children: [VaultNode]

    var listChildren: [VaultNode]? {
        isDirectory ? children : nil
    }
}

/// 한 번의 순회가 내놓는 결과. 트리와 위키링크 지도를 **함께** 만든다.
///
/// 예전에는 `tree(for:)` 와 `indexMarkdown(in:)` 이 같은 디렉터리를 각각 훑었다.
/// 목적은 다르지만 방문 대상이 같아서 순회를 두 번 한 셈이었다
/// (실측 Knowledge 108ms → 합쳐서 33ms).
struct VaultScan: Sendable {
    let roots: [VaultNode]
    /// 파일명(확장자 제외) → 후보 경로들.
    ///
    /// **배열인 이유**: 같은 이름의 노트가 여러 폴더에 있을 수 있다. 예전에는
    /// `[String: URL]` 이라 나중에 만난 것이 앞의 것을 조용히 덮어썼고, 위키링크가
    /// 엉뚱한 파일로 갔다 (실측 2026-09-01: Knowledge 의 md 1,369개 중 34개가 이름 충돌).
    let wikiIndex: [String: [URL]]

    static let empty = VaultScan(roots: [], wikiIndex: [:])
}

enum VaultCatalog {
    static func roots(kind: VaultKind, vault: URL) -> [VaultRoot] {
        switch kind {
        case .knowledge:
            return [
                VaultRoot(title: "Study", url: vault.appendingPathComponent("2. Study"), excludedRelativePaths: []),
                VaultRoot(
                    title: "Life Canvas",
                    url: vault.appendingPathComponent("1. Life Canvas"),
                    excludedRelativePaths: ["Self Management/Planner"]
                ),
            ]
        case .works:
            return [
                VaultRoot(title: "Projects", url: vault.appendingPathComponent("3. Projects"), excludedRelativePaths: []),
                VaultRoot(title: "Work", url: vault.appendingPathComponent("4. Work"), excludedRelativePaths: []),
            ]
        }
    }

    /// 디스크를 훑는다. **메인 스레드에서 부르지 마라** — `VaultScanner` 를 거친다.
    static func scan(roots: [VaultRoot]) -> VaultScan {
        var index: [String: [URL]] = [:]
        var nodes: [VaultNode] = []

        for root in roots {
            var isDirectory: ObjCBool = false
            let path = root.url.standardizedFileURL.path
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { continue }
            if let node = buildNode(
                url: root.url,
                name: root.title,
                isDirectory: isDirectory.boolValue,
                excluded: excludedURLs(for: root),
                into: &index
            ) {
                nodes.append(node)
            }
        }
        return VaultScan(roots: nodes, wikiIndex: index)
    }

    /// `[[제목]]` 이 가리키는 파일을 고른다.
    ///
    /// 이름이 겹칠 때 **아무거나 고르면 안 된다.** 우선순위는
    /// ① 지금 보고 있는 문서와 같은 폴더 ② 경로가 짧은 것(루트에 가까운 것).
    /// ②는 «가장 그럴듯해서»가 아니라 **실행할 때마다 같은 답이 나오게** 하려는 것이다.
    static func resolveWikiLink(_ title: String, from current: URL?, in index: [String: [URL]]) -> URL? {
        guard let candidates = index[title], !candidates.isEmpty else { return nil }
        if candidates.count == 1 { return candidates[0] }

        if let current {
            let folder = current.deletingLastPathComponent().standardizedFileURL.path
            if let sameFolder = candidates.first(where: {
                $0.deletingLastPathComponent().standardizedFileURL.path == folder
            }) {
                return sameFolder
            }
        }
        return candidates.min { ($0.path.count, $0.path) < ($1.path.count, $1.path) }
    }

    private static func excludedURLs(for root: VaultRoot) -> Set<String> {
        Set(root.excludedRelativePaths.map { root.url.appendingPathComponent($0).standardizedFileURL.path })
    }

    /// 트리 노드를 만들면서 마크다운이면 위키링크 지도에도 넣는다.
    ///
    /// `isDirectory` 를 **인자로 받는다.** 호출부의 `contentsOfDirectory(includingPropertiesForKeys:)`
    /// 가 이미 알려준 값이라, 노드마다 `fileExists` 를 다시 부를 이유가 없다.
    /// 그 중복 호출이 노드당 비용의 상당 부분이었다.
    private static func buildNode(
        url: URL,
        name: String,
        isDirectory: Bool,
        excluded: Set<String>,
        into index: inout [String: [URL]]
    ) -> VaultNode? {
        if excluded.contains(url.standardizedFileURL.path) { return nil }

        guard isDirectory else {
            if url.pathExtension.lowercased() == "md" {
                index[url.deletingPathExtension().lastPathComponent, default: []].append(url)
            }
            return VaultNode(name: name, url: url, isDirectory: false, children: [])
        }

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        // isDirectory 를 항목마다 한 번만 읽어 `(URL, Bool)` 로 붙여 둔다.
        // 비교자 안에서 읽으면 정렬하는 동안 O(k log k) 번 다시 조회하게 된다.
        let decorated = contents
            .filter { shouldInclude($0) }
            .map { ($0, (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 && !rhs.1 }
                return lhs.0.lastPathComponent.localizedStandardCompare(rhs.0.lastPathComponent) == .orderedAscending
            }

        var children: [VaultNode] = []
        children.reserveCapacity(decorated.count)
        for (childURL, childIsDirectory) in decorated {
            if let node = buildNode(
                url: childURL,
                name: childURL.lastPathComponent,
                isDirectory: childIsDirectory,
                excluded: excluded,
                into: &index
            ) {
                children.append(node)
            }
        }

        return VaultNode(name: name, url: url, isDirectory: true, children: children)
    }

    private static func shouldInclude(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if name.hasPrefix(".") { return false }
        return name != ".obsidian" && name != ".my-wiki"
    }
}

/// vault 순회를 메인 스레드 밖으로 빼고, 결과를 들고 있는다.
///
/// 캐시가 필요한 이유는 `PersonalRecordView.content` 가 `switch` 라서다 — Knowledge/Works 로
/// 갈 때마다 `VaultBrowserView` 가 새로 만들어지고 `.onAppear` 가 다시 터진다.
/// 캐시가 없으면 탭을 오갈 때마다 디스크를 통째로 다시 훑는다.
///
/// 파일 감시(FSEvents)는 넣지 않았다. vault 가 앱 밖에서 바뀌면 새로고침 버튼으로 반영한다.
actor VaultScanner {
    static let shared = VaultScanner()

    private var cache: [String: VaultScan] = [:]

    func scan(kind: VaultKind, vault: URL, forceReload: Bool = false) -> VaultScan {
        let key = "\(kind.title)|\(vault.standardizedFileURL.path)"
        if !forceReload, let cached = cache[key] { return cached }

        let result = VaultCatalog.scan(roots: VaultCatalog.roots(kind: kind, vault: vault))
        cache[key] = result
        return result
    }
}
