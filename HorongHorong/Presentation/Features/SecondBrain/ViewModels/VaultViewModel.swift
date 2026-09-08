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
    /// 열어 둔 문서. 브라우저 탭처럼 제목 줄에 남겨 두고 오간다.
    ///
    /// 초안은 탭마다 들고 있지 않는다. 탭을 옮길 때 `open` 이 먼저 저장하므로
    /// 본문·스냅샷은 항상 `selectedURL` 하나만 가리킨다.
    private(set) var openTabs: [URL] = []
    private(set) var markdown = ""
    private(set) var loadError: String?
    private(set) var isScanning = false
    private(set) var location: VaultLocation?
    private(set) var indexedDocuments: [VaultIndexedDocument] = []
    private(set) var indexVersion = 0
    private(set) var snapshot: VaultDocument?
    private(set) var hasConflict = false
    private(set) var isSaving = false
    private(set) var documentVersion = 0
    var isReadingMode = false
    var isTreeVisible = true
    var expandedFolders: Set<URL> = []
    struct TreeRow: Identifiable {
        var id: URL { node.url }
        let node: VaultNode
        let depth: Int
    }
    var visibleRows: [TreeRow] {
        var rows: [TreeRow] = []
        func append(_ nodes: [VaultNode], depth: Int) {
            for node in nodes {
                rows.append(TreeRow(node: node, depth: depth))
                if expandedFolders.contains(node.url) || !searchText.isEmpty { append(node.children, depth: depth + 1) }
            }
        }
        append(filteredRoots, depth: 0)
        return rows
    }
    var actionError: String?
    var isDirty: Bool { snapshot.map { $0.text != markdown } ?? false }
    var canEdit: Bool {
        guard let location, let selectedURL else { return false }
        return VaultPathPolicy.contains(selectedURL, in: location.root)
    }

    var searchText = ""

    private let repository: VaultRepository
    private var wikiIndex: [String: [URL]] = [:]
    private let locations: VaultLocationGateway?
    private var autosave: Task<Void, Never>?
    private var generation = 0
    private var saveTask: Task<VaultDocument, Error>?

    init(kind: VaultKind, repository: VaultRepository, locations: VaultLocationGateway? = nil) {
        self.kind = kind
        self.repository = repository
        self.locations = locations
    }

    /// 검색어에 맞는 가지만 남긴 트리. 폴더 이름이 맞으면 그 아래는 통째로 남긴다.
    var filteredRoots: [VaultNode] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return roots }
        return roots.compactMap { Self.filter($0, query: query) }
    }

    func load(vault: URL, forceReload: Bool = false) async {
        generation += 1
        let request = generation
        isScanning = true
        if location == nil { location = VaultLocation(root: vault, reference: vault) }
        do { try await repository.validate(root: vault) }
        catch { loadError = error.localizedDescription; isScanning = false; return }
        let scan = await repository.scan(kind: kind, vault: vault, forceReload: forceReload)
        guard request == generation else { return }
        isScanning = false
        guard !Task.isCancelled else { return }

        roots = scan.roots
        wikiIndex = scan.wikiIndex
        loadError = nil
        if let root = roots.first { expandedFolders.insert(root.url) }
        await refreshIndex()
    }

    func open(_ url: URL) async {
        if roots.contains(where: { Self.isDirectory(url, node: $0) }) { return }
        guard await save() else { return }
        if !openTabs.contains(url) { openTabs.append(url) }
        selectedURL = url
        snapshot = nil
        loadError = nil
        markdown = ""
        guard url.pathExtension.lowercased() == "md" else { return }

        let result = try? await repository.snapshot(at: url)
        // 읽는 사이에 사용자가 다른 문서를 골랐으면 늦게 온 결과를 버린다.
        guard selectedURL == url else { return }
        if let result {
            snapshot = result
            markdown = result.text
            documentVersion += 1
        } else {
            loadError = "파일을 읽지 못했습니다"
        }
    }

    /// 탭을 고른다. **보고 있던 문서면 다시 읽지 않는다** — 다시 읽으면
    /// `documentVersion` 이 올라가 편집기가 재초기화되고 커서·undo 가 날아간다.
    func select(_ url: URL) async {
        guard selectedURL != url else { return }
        await open(url)
    }

    /// 탭을 닫는다. 보고 있던 탭이면 오른쪽(없으면 왼쪽) 탭으로 옮긴다.
    func close(_ url: URL) async {
        guard let index = openTabs.firstIndex(of: url) else { return }
        let wasActive = selectedURL == url
        // 초안이 있으면 닫기 전에 저장한다. 실패하면 탭을 남겨 사용자가 처리하게 둔다.
        if wasActive {
            guard await save() else { return }
        }
        openTabs.remove(at: index)
        guard wasActive else { return }
        let next = openTabs.indices.contains(index) ? openTabs[index] : openTabs.last
        clearDocument()
        if let next { await open(next) }
    }

    /// `[[제목]]` 을 눌렀을 때. 가리키는 문서가 없으면 아무 일도 하지 않는다.
    func followWikiLink(_ title: String) async {
        guard let target = repository.resolveWikiLink(title, from: selectedURL, in: wikiIndex) else { return }
        await open(target)
    }

    func initialize() async {
        guard let value = locations?.location(for: kind), value != location, await save() else { return }
        clearDocument()
        openTabs = []
        location = value
        await load(vault: value.root)
        await openPreferredDocumentIfNeeded()
    }

    /// 스크린샷 캡처 또는 지정된 환경변수가 있을 때 대표 문서를 자동으로 열고 폴더 트리를 펼친다.
    private func openPreferredDocumentIfNeeded() async {
        guard let location else { return }
        let isScreenshot = ProcessInfo.processInfo.environment["HORONGHORONG_SCREENSHOT_TARGET"] != nil
            || ProcessInfo.processInfo.arguments.contains("--screenshot-target")
        let preferredPath: String?
        switch kind {
        case .knowledge:
            preferredPath = ProcessInfo.processInfo.environment["HORONGHORONG_VAULT_KNOWLEDGE_DOCUMENT"]
                ?? (isScreenshot ? "AI Engineering/LLM/04-실행 스택/01-프레임워크/GGML 계열/GBNF 문법.md" : nil)
        case .works:
            preferredPath = ProcessInfo.processInfo.environment["HORONGHORONG_VAULT_WORKS_DOCUMENT"]
                ?? (isScreenshot ? "하이미디어/강의 계획서/강의 계획서.md" : nil)
        }

        guard let relPath = preferredPath, !relPath.isEmpty else { return }
        let targetURL = location.root.appendingPathComponent(relPath)
        guard FileManager.default.fileExists(atPath: targetURL.path) else { return }

        // 상위 폴더들을 트리에 펼치기
        var folder = targetURL.deletingLastPathComponent()
        while folder.path.hasPrefix(location.root.path) {
            expandedFolders.insert(folder)
            if folder.path == location.root.path { break }
            folder = folder.deletingLastPathComponent()
        }

        await open(targetURL)
    }

    func chooseRoot() async {
        guard await save(), let value = locations?.choose(for: kind) else { return }
        generation += 1
        location = value
        clearDocument()
        openTabs = []
        roots = []
        indexedDocuments = []
        searchText = ""
        expandedFolders = []
        await load(vault: value.root, forceReload: true)
    }

    func reload() async {
        guard let location else { return }
        await load(vault: location.root, forceReload: true)
        await checkExternalDocument()
    }

    func edit(_ text: String) {
        guard canEdit, snapshot != nil else { return }
        markdown = text
        autosave?.cancel()
        guard !hasConflict else { return }
        autosave = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            _ = await self?.save()
        }
    }

    @discardableResult
    func save() async -> Bool {
        if let pending = saveTask {
            _ = try? await pending.value
            // 저장 완료 처리도 동일한 MainActor에서 끝난 뒤 최신 초안을 다시 확인한다.
            while isSaving { await Task.yield() }
        }
        guard isDirty else { return true }
        guard !hasConflict, let snapshot, let location, canEdit else { return false }
        let text = markdown
        isSaving = true
        let task = Task { try await repository.save(text, document: snapshot, root: location.root) }
        saveTask = task
        do {
            let saved = try await task.value
            self.snapshot = saved
            actionError = nil
            isSaving = false
            saveTask = nil
            return isDirty ? await save() : true
        } catch {
            hasConflict = (error as? VaultError) == .conflict
            actionError = error.localizedDescription
            isSaving = false
            saveTask = nil
            return false
        }
    }

    func create(name: String, directory: Bool, parent: URL? = nil) async {
        guard let location, await save() else { return }
        do {
            let folder = parent ?? location.root
            let created = try await repository.create(name: name, directory: directory, parent: folder, root: location.root)
            expandedFolders.insert(folder)
            searchText = ""
            await reload()
            if !directory { await open(created) }
        } catch { actionError = error.localizedDescription }
    }

    func delete(at url: URL) async {
        guard let location else { return }
        do {
            try await repository.delete(at: url, root: location.root)
            let index = selectedURL.flatMap { openTabs.firstIndex(of: $0) } ?? 0
            let wasActive = selectedURL.map { VaultPathPolicy.contains($0, in: url) } ?? false
            openTabs.removeAll { VaultPathPolicy.contains($0, in: url) }
            if wasActive {
                // 사라진 파일에 초안을 쓰려 들지 않도록 본문을 먼저 비운 뒤 이웃 탭을 연다.
                clearDocument()
                if let next = openTabs.indices.contains(index) ? openTabs[index] : openTabs.last {
                    await open(next)
                }
            }
            actionError = nil
            await reload()
        } catch { actionError = error.localizedDescription }
    }

    func discardDraft() async {
        guard let selectedURL else { return }
        do {
            let value = try await repository.snapshot(at: selectedURL)
            snapshot = value
            markdown = value.text
            hasConflict = false
            actionError = nil
            documentVersion += 1
        } catch { actionError = error.localizedDescription }
    }

    func saveConflictCopy() async {
        guard let location, let selectedURL else { return }
        do {
            let name = selectedURL.deletingPathExtension().lastPathComponent + " (내 변경 \(UUID().uuidString.prefix(8)))"
            let url = try await repository.create(name: name, directory: false, parent: location.root, root: location.root)
            let empty = try await repository.snapshot(at: url)
            let saved = try await repository.save(markdown, document: empty, root: location.root)
            // 사본으로 갈아탄다. 원본 탭을 남기면 초안이 없는 충돌 상태만 다시 보게 된다.
            if let index = openTabs.firstIndex(of: selectedURL) { openTabs[index] = url }
            else { openTabs.append(url) }
            self.selectedURL = url
            snapshot = saved
            hasConflict = false
            actionError = nil
            documentVersion += 1
            await reload()
        } catch { actionError = error.localizedDescription }
    }

    func resource(_ path: String) async throws -> Data {
        guard let location else { throw VaultError.unavailable }
        return try await repository.resource(path: path, vault: location.reference)
    }

    func openRelative(_ path: String) async {
        guard let location else { return }
        let url = location.reference.appendingPathComponent(path.components(separatedBy: "#")[0])
        guard VaultPathPolicy.contains(url, in: location.reference) else { return }
        await open(url)
    }

    /// 파일 메타데이터만 비교하고 변경된 문서만 다시 파싱한다. 숨은 탭도 초안을 잃지 않는다.
    func observe() async {
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            await checkExternalDocument()
            await refreshIndex()
            if let location {
                let scan = await repository.scan(kind: kind, vault: location.root, forceReload: true)
                if scan.roots != roots { roots = scan.roots }
            }
        }
    }

    private func refreshIndex() async {
        guard let location else { return }
        let value = try? await repository.index(vault: location.reference)
        guard self.location == location, let value else { return }
        if value != indexedDocuments { indexedDocuments = value; indexVersion += 1 }
        for file in value {
            let url = location.reference.appendingPathComponent(file.path)
            let key = url.deletingPathExtension().lastPathComponent
            if !(wikiIndex[key] ?? []).contains(url) { wikiIndex[key, default: []].append(url) }
        }
    }

    private func checkExternalDocument() async {
        guard let snapshot, !isSaving else { return }
        do {
            let value = try await repository.snapshot(at: snapshot.url)
            guard self.snapshot == snapshot, selectedURL == snapshot.url, !isSaving,
                  value.revision != snapshot.revision else { return }
            if isDirty { hasConflict = true; actionError = VaultError.conflict.localizedDescription }
            else { self.snapshot = value; markdown = value.text; documentVersion += 1 }
        } catch {
            guard selectedURL == snapshot.url else { return }
            actionError = error.localizedDescription
        }
    }

    /// 보고 있던 문서를 놓는다. 탭 목록은 건드리지 않는다 — 호출부마다 규칙이 다르다.
    private func clearDocument() {
        selectedURL = nil
        snapshot = nil
        markdown = ""
    }

    private static func isDirectory(_ url: URL, node: VaultNode) -> Bool {
        if node.url == url { return node.isDirectory }
        return node.children.contains { isDirectory(url, node: $0) }
    }

    private static func filter(_ node: VaultNode, query: String) -> VaultNode? {
        if node.name.localizedCaseInsensitiveContains(query) { return node }
        let children = node.children.compactMap { filter($0, query: query) }
        guard !children.isEmpty else { return nil }
        return VaultNode(name: node.name, url: node.url, isDirectory: node.isDirectory, children: children)
    }
}
