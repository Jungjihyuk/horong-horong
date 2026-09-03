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
        // 큰 노트를 메인 스레드에서 읽으면 그동안 화면이 멈춘다.
        await Task.detached(priority: .userInitiated) {
            try? String(contentsOf: url, encoding: .utf8)
        }.value
    }

    func resolveWikiLink(_ title: String, from current: URL?, in index: [String: [URL]]) -> URL? {
        VaultCatalog.resolveWikiLink(title, from: current, in: index)
    }
}
