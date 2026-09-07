import Foundation
import CryptoKit

/// 파일 I/O를 직렬화하고, 수정 시각이 같은 외부 변경도 원문 해시로 감지한다.
actor VaultFileStore {
    static let shared = VaultFileStore()
    private var indexed: [URL: VaultIndexedDocument] = [:]

    func snapshot(at url: URL) throws -> VaultDocument {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else { throw VaultError.unavailable }
        return VaultDocument(url: url, text: text, revision: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }

    func save(_ text: String, document: VaultDocument, root: URL) throws -> VaultDocument {
        guard VaultPathPolicy.contains(document.url, in: root) else { throw VaultError.outsideRoot }
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<VaultDocument, Error> = .failure(VaultError.unavailable)
        coordinator.coordinate(writingItemAt: document.url, options: .forReplacing, error: &coordinationError) { url in
            result = Result {
                guard try snapshot(at: url).revision == document.revision else { throw VaultError.conflict }
                try Data(text.utf8).write(to: url, options: .atomic)
                indexed.removeValue(forKey: url)
                return try snapshot(at: url)
            }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    func create(name: String, directory: Bool, parent: URL, root: URL) throws -> URL {
        let filename = try VaultPathPolicy.filename(name, directory: directory)
        let target = parent.appendingPathComponent(filename, isDirectory: directory)
        guard VaultPathPolicy.contains(target, in: root) else { throw VaultError.outsideRoot }
        guard !FileManager.default.fileExists(atPath: target.path) else { throw VaultError.alreadyExists }
        if directory { try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false) }
        else { try Data().write(to: target, options: .withoutOverwriting) }
        return target
    }

    func delete(at url: URL, root: URL) throws {
        guard VaultPathPolicy.contains(url, in: root),
              VaultPathPolicy.canonicalURL(url).path != VaultPathPolicy.canonicalURL(root).path else { throw VaultError.outsideRoot }
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        indexed.removeValue(forKey: url)
    }

    func validate(root: URL) throws {
        _ = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
    }

    func resource(path: String, vault: URL) throws -> Data {
        let url = vault.appendingPathComponent(path)
        guard !path.hasPrefix("/"), VaultPathPolicy.contains(url, in: vault) else { throw VaultError.outsideRoot }
        return try Data(contentsOf: url)
    }

    func index(vault: URL) throws -> [VaultIndexedDocument] {
        try validate(root: vault)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .creationDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: vault, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { throw VaultError.unavailable }
        var result: [VaultIndexedDocument] = []
        let canonicalVault = VaultPathPolicy.canonicalURL(vault)
        let prefixLength = canonicalVault.path == "/" ? 1 : canonicalVault.path.count + 1
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            guard values.isRegularFile == true, url.pathExtension.lowercased() == "md" else { continue }
            let modified = (values.contentModificationDate ?? .distantPast).timeIntervalSince1970 * 1000
            let size = values.fileSize ?? 0
            let canonicalURL = VaultPathPolicy.canonicalURL(url)
            guard canonicalURL.path.hasPrefix(canonicalVault.path == "/" ? "/" : canonicalVault.path + "/") else { continue }
            let relative = String(canonicalURL.path.dropFirst(prefixLength))
            if let cached = indexed[url], cached.modified == modified, cached.size == size, cached.path == relative {
                result.append(cached)
            } else if let text = try? String(contentsOf: url, encoding: .utf8) {
                let item = VaultIndexedDocument(path: relative, text: text, modified: modified, created: (values.creationDate ?? .distantPast).timeIntervalSince1970 * 1000, size: size)
                indexed[url] = item
                result.append(item)
            }
        }
        return result.sorted { $0.path < $1.path }
    }
}
