import XCTest
@testable import 호롱호롱

final class VaultCatalogTests: XCTestCase {
    func testKnowledgeOmitsPlannerFolder() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-test-\(UUID().uuidString)", isDirectory: true)
        let life = root.appendingPathComponent("1. Life Canvas", isDirectory: true)
        let planner = life.appendingPathComponent("Self Management/Planner", isDirectory: true)
        let books = life.appendingPathComponent("Growth/Books", isDirectory: true)
        try FileManager.default.createDirectory(at: planner, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: books, withIntermediateDirectories: true)
        try "# plan".write(to: planner.appendingPathComponent("2026-09-01.md"), atomically: true, encoding: .utf8)
        try "# book".write(to: books.appendingPathComponent("책.md"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let catalogRoot = VaultCatalog.roots(kind: .knowledge, vault: root)
            .first { $0.title == "Life Canvas" }
        let tree = try XCTUnwrap(catalogRoot.flatMap(VaultCatalog.tree(for:)))
        let names = leafNames(tree)
        XCTAssertTrue(names.contains("책.md"))
        XCTAssertFalse(names.contains("2026-09-01.md"))
    }

    private func leafNames(_ node: VaultNode) -> [String] {
        if !node.isDirectory { return [node.name] }
        return node.children.flatMap(leafNames)
    }
}
