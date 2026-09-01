import Foundation

enum VaultKind {
    case knowledge
    case works

    var title: String {
        switch self {
        case .knowledge: return "Knowledge"
        case .works: return "Works"
        }
    }
}

struct VaultRoot: Identifiable, Hashable {
    var id: String { url.path }
    let title: String
    let url: URL
    /// vault 루트 기준 상대 경로. 이 폴더와 그 하위는 트리에서 뺀다.
    let excludedRelativePaths: [String]
}

struct VaultNode: Identifiable, Hashable {
    var id: String { url.path }
    let name: String
    let url: URL
    let isDirectory: Bool
    var children: [VaultNode]

    var listChildren: [VaultNode]? {
        isDirectory ? children : nil
    }
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

    static func tree(for root: VaultRoot) -> VaultNode? {
        buildNode(url: root.url, name: root.title, excluded: excludedURLs(for: root))
    }

    static func indexMarkdown(in roots: [VaultRoot]) -> [String: URL] {
        var map: [String: URL] = [:]
        for root in roots {
            walkMarkdown(url: root.url, excluded: excludedURLs(for: root), into: &map)
        }
        return map
    }

    private static func excludedURLs(for root: VaultRoot) -> Set<String> {
        Set(root.excludedRelativePaths.map { root.url.appendingPathComponent($0).standardizedFileURL.path })
    }

    private static func buildNode(url: URL, name: String, excluded: Set<String>) -> VaultNode? {
        let path = url.standardizedFileURL.path
        if excluded.contains(path) { return nil }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return nil
        }

        if !isDirectory.boolValue {
            return VaultNode(name: name, url: url, isDirectory: false, children: [])
        }

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let children = contents
            .filter { shouldInclude($0) }
            .sorted { lhs, rhs in
                let leftDir = (try? lhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let rightDir = (try? rhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if leftDir != rightDir { return leftDir && !rightDir }
                return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }
            .compactMap { child in
                buildNode(url: child, name: child.lastPathComponent, excluded: excluded)
            }

        return VaultNode(name: name, url: url, isDirectory: true, children: children)
    }

    private static func shouldInclude(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if name.hasPrefix(".") { return false }
        if name == ".obsidian" || name == ".my-wiki" { return false }
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if isDirectory { return true }
        return true
    }

    private static func walkMarkdown(url: URL, excluded: Set<String>, into map: inout [String: URL]) {
        let path = url.standardizedFileURL.path
        if excluded.contains(path) { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return }
        if !isDirectory.boolValue {
            if url.pathExtension.lowercased() == "md" {
                map[url.deletingPathExtension().lastPathComponent] = url
            }
            return
        }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for child in contents where shouldInclude(child) {
            walkMarkdown(url: child, excluded: excluded, into: &map)
        }
    }
}
