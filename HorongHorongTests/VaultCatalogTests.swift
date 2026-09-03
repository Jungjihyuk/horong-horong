import XCTest
@testable import 호롱호롱

final class VaultCatalogTests: XCTestCase {
    /// 임시 vault 를 만들고 정리까지 맡는다.
    private func makeVault(_ files: [String], test: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for relative in files {
            let url = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try "# \(url.lastPathComponent)".write(to: url, atomically: true, encoding: .utf8)
        }
        try test(root)
    }

    private func leafNames(_ node: VaultNode) -> [String] {
        node.isDirectory ? node.children.flatMap(leafNames) : [node.name]
    }

    func testKnowledgeOmitsPlannerFolder() throws {
        try makeVault([
            "1. Life Canvas/Self Management/Planner/2026-09-01.md",
            "1. Life Canvas/Growth/Books/책.md",
        ]) { root in
            let roots = VaultCatalog.roots(kind: .knowledge, vault: root)
                .filter { $0.title == "Life Canvas" }
            let scan = VaultCatalog.scan(roots: roots)
            let names = scan.roots.flatMap(leafNames)

            XCTAssertTrue(names.contains("책.md"))
            XCTAssertFalse(names.contains("2026-09-01.md"), "Planner 는 트리에서 뺀다")
        }
    }

    /// 제외된 폴더는 위키링크 지도에도 들어가면 안 된다.
    /// 순회를 하나로 합치면서 두 결과가 같은 제외 규칙을 쓰는지 확인한다.
    func testExcludedFolderIsAlsoAbsentFromWikiIndex() throws {
        try makeVault([
            "1. Life Canvas/Self Management/Planner/2026-09-01.md",
            "1. Life Canvas/Growth/Books/책.md",
        ]) { root in
            let roots = VaultCatalog.roots(kind: .knowledge, vault: root)
                .filter { $0.title == "Life Canvas" }
            let scan = VaultCatalog.scan(roots: roots)

            XCTAssertNotNil(scan.wikiIndex["책"])
            XCTAssertNil(scan.wikiIndex["2026-09-01"])
        }
    }

    /// **이름이 겹쳐도 잃어버리지 않는다.**
    /// 예전 `[String: URL]` 은 나중에 만난 것이 앞의 것을 덮어써서
    /// 실제 vault 에서 34개 파일이 링크로 도달할 수 없었다.
    func testDuplicateFileNamesKeepAllCandidates() throws {
        try makeVault([
            "2. Study/A/2025-01-01.md",
            "2. Study/B/2025-01-01.md",
        ]) { root in
            let roots = VaultCatalog.roots(kind: .knowledge, vault: root)
                .filter { $0.title == "Study" }
            let scan = VaultCatalog.scan(roots: roots)

            XCTAssertEqual(scan.wikiIndex["2025-01-01"]?.count, 2)
        }
    }

    /// 이름이 겹치면 «지금 보고 있는 문서와 같은 폴더» 를 먼저 고른다.
    func testWikiLinkPrefersSameFolder() throws {
        try makeVault([
            "2. Study/A/2025-01-01.md",
            "2. Study/A/여기서본다.md",
            "2. Study/B/2025-01-01.md",
        ]) { root in
            let roots = VaultCatalog.roots(kind: .knowledge, vault: root)
                .filter { $0.title == "Study" }
            let scan = VaultCatalog.scan(roots: roots)
            let current = root.appendingPathComponent("2. Study/A/여기서본다.md")

            let resolved = VaultCatalog.resolveWikiLink("2025-01-01", from: current, in: scan.wikiIndex)
            XCTAssertEqual(resolved?.deletingLastPathComponent().lastPathComponent, "A")
        }
    }

    /// 같은 폴더에 없으면 무엇을 고르든 **실행할 때마다 같아야** 한다.
    func testWikiLinkIsDeterministicWhenAmbiguous() throws {
        try makeVault([
            "2. Study/깊은/더깊은/이름.md",
            "2. Study/얕은/이름.md",
        ]) { root in
            let roots = VaultCatalog.roots(kind: .knowledge, vault: root)
                .filter { $0.title == "Study" }
            let scan = VaultCatalog.scan(roots: roots)

            let first = VaultCatalog.resolveWikiLink("이름", from: nil, in: scan.wikiIndex)
            let second = VaultCatalog.resolveWikiLink("이름", from: nil, in: scan.wikiIndex)
            XCTAssertEqual(first, second)
            XCTAssertEqual(first?.deletingLastPathComponent().lastPathComponent, "얕은", "경로가 짧은 쪽")
        }
    }

    func testMissingRootIsSkippedWithoutCrashing() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString)")
        let scan = VaultCatalog.scan(roots: VaultCatalog.roots(kind: .works, vault: missing))
        XCTAssertTrue(scan.roots.isEmpty)
        XCTAssertTrue(scan.wikiIndex.isEmpty)
    }
}
