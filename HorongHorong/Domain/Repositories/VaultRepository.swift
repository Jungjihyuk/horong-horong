import Foundation

/// 원문과 읽었을 때의 버전을 함께 전달하여 외부 앱의 변경을 덮어쓰지 않는다.
@MainActor
protocol VaultRepository {
    /// 폴더를 훑어 트리와 위키 링크 색인을 만든다.
    ///
    /// `forceReload` 가 `false` 면 캐시를 쓴다. 탭을 오갈 때마다 디스크를 다시 훑지
    /// 않기 위해서다 — vault 가 앱 밖에서 바뀌면 새로고침으로 반영한다.
    func scan(kind: VaultKind, vault: URL, forceReload: Bool) async -> VaultScan

    /// 문서 본문. 읽지 못하면 `nil`.
    func document(at url: URL) async -> String?

    /// `[[제목]]` 이 가리키는 문서를 찾는다. 같은 이름이 여럿이면 현재 문서에 가까운 쪽.
    func resolveWikiLink(_ title: String, from current: URL?, in index: [String: [URL]]) -> URL?
    func snapshot(at url: URL) async throws -> VaultDocument
    func save(_ text: String, document: VaultDocument, root: URL) async throws -> VaultDocument
    func create(name: String, directory: Bool, parent: URL, root: URL) async throws -> URL
    func delete(at url: URL, root: URL) async throws
    func index(vault: URL) async throws -> [VaultIndexedDocument]
    func resource(path: String, vault: URL) async throws -> Data
    func validate(root: URL) async throws
}

extension VaultRepository {
    func snapshot(at url: URL) async throws -> VaultDocument {
        guard let text = await document(at: url) else { throw VaultError.unavailable }
        return VaultDocument(url: url, text: text, revision: text)
    }
    func save(_ text: String, document: VaultDocument, root: URL) async throws -> VaultDocument { throw VaultError.readOnly }
    func create(name: String, directory: Bool, parent: URL, root: URL) async throws -> URL { throw VaultError.readOnly }
    func delete(at url: URL, root: URL) async throws { throw VaultError.readOnly }
    func index(vault: URL) async throws -> [VaultIndexedDocument] { [] }
    func resource(path: String, vault: URL) async throws -> Data { throw VaultError.unavailable }
    func validate(root: URL) async throws {}
}
