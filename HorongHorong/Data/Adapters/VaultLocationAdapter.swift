import AppKit

@MainActor
final class VaultLocationAdapter: VaultLocationGateway {
    private let defaults: UserDefaults
    private var accessed: [URL] = []

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    static func key(_ kind: VaultKind) -> String { "mind.\(kind.title.lowercased()).root" }

    func location(for kind: VaultKind) -> VaultLocation? {
        let key = Self.key(kind)
        // 기존 경로를 두 탭의 초기값으로만 이전한다. 신규 설치에 개인 경로를 주입하지 않는다.
        if defaults.string(forKey: key) == nil,
           let legacy = defaults.string(forKey: Constants.AppStorageKey.mindVaultPath), !legacy.isEmpty {
            defaults.set(legacy, forKey: key)
        }
        guard let path = defaults.string(forKey: key), !path.isEmpty else { return nil }
        let root = restore(key: key, fallback: URL(fileURLWithPath: path))
        let reference = restore(key: key + ".reference", fallback: Self.referenceRoot(root))
        return VaultLocation(root: root, reference: reference)
    }

    func choose(for kind: VaultKind) -> VaultLocation? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = location(for: kind)?.root
        panel.prompt = "루트로 선택"
        guard panel.runModal() == .OK, let root = panel.url else { return nil }
        var reference = Self.referenceRoot(root)
        // 샌드박스에서 하위 폴더의 권한은 상위 vault까지 확장되지 않는다.
        if reference != root, ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil {
            panel.directoryURL = reference
            panel.message = "기존 링크와 Dataview를 읽기 위해 상위 Obsidian vault를 선택하세요."
            panel.prompt = "참조 vault 선택"
            guard panel.runModal() == .OK, let granted = panel.url,
                  VaultPathPolicy.contains(root, in: granted) else { return nil }
            reference = granted
        }
        let key = Self.key(kind)
        persist(root, key: key)
        persist(reference, key: key + ".reference")
        return VaultLocation(root: root, reference: reference)
    }

    static func referenceRoot(_ root: URL) -> URL {
        var candidate = root.standardizedFileURL
        while candidate.path != "/" {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent(".obsidian").path, isDirectory: &isDirectory), isDirectory.boolValue { return candidate }
            candidate.deleteLastPathComponent()
        }
        return root
    }

    private func persist(_ url: URL, key: String) {
        defaults.set(url.path, forKey: key)
        if let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(bookmark, forKey: key + ".bookmark")
        }
        access(url)
    }

    private func restore(key: String, fallback: URL) -> URL {
        var stale = false
        if let data = defaults.data(forKey: key + ".bookmark"),
           let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) {
            access(url)
            if stale { persist(url, key: key) }
            return url
        }
        return fallback
    }

    private func access(_ url: URL) {
        if !accessed.contains(url), url.startAccessingSecurityScopedResource() { accessed.append(url) }
    }
}
