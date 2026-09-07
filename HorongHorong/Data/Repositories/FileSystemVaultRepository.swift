import Foundation

/// `VaultRepository` 의 파일 시스템 구현.
///
/// 순회와 캐시는 `VaultScanner`(actor)가 메인 스레드 밖에서 한다. 이 타입은 그 앞의
/// 얇은 껍데기다 — 화면이 actor·캐시 같은 사정을 알 필요가 없게 한다.
@MainActor
struct FileSystemVaultRepository: VaultRepository {
    private let scanner: VaultScanner

    init(scanner: VaultScanner = .shared) {
        self.scanner = scanner
    }

    func scan(kind: VaultKind, vault: URL, forceReload: Bool) async -> VaultScan {
        await scanner.scan(kind: kind, vault: vault, forceReload: forceReload)
    }

    func document(at url: URL) async -> String? {
        try? await VaultFileStore.shared.snapshot(at: url).text
    }

    func snapshot(at url: URL) async throws -> VaultDocument { try await VaultFileStore.shared.snapshot(at: url) }
    func save(_ text: String, document: VaultDocument, root: URL) async throws -> VaultDocument {
        try await VaultFileStore.shared.save(text, document: document, root: root)
    }
    func create(name: String, directory: Bool, parent: URL, root: URL) async throws -> URL {
        try await VaultFileStore.shared.create(name: name, directory: directory, parent: parent, root: root)
    }
    func delete(at url: URL, root: URL) async throws {
        try await VaultFileStore.shared.delete(at: url, root: root)
    }
    func index(vault: URL) async throws -> [VaultIndexedDocument] { try await VaultFileStore.shared.index(vault: vault) }
    func resource(path: String, vault: URL) async throws -> Data { try await VaultFileStore.shared.resource(path: path, vault: vault) }
    func validate(root: URL) async throws { try await VaultFileStore.shared.validate(root: root) }

    func resolveWikiLink(_ title: String, from current: URL?, in index: [String: [URL]]) -> URL? {
        VaultCatalog.resolveWikiLink(title, from: current, in: index)
    }
}
