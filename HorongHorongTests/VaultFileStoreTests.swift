import XCTest
@testable import 호롱호롱

final class VaultFileStoreTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testCreationRejectsCollisionAndTraversal() async throws {
        let store = VaultFileStore()
        let url = try await store.create(name: "노트", directory: false, parent: root, root: root)
        XCTAssertEqual(url.lastPathComponent, "노트.md")
        do { _ = try await store.create(name: "노트", directory: false, parent: root, root: root); XCTFail("기존 파일을 덮어쓰면 안 됨") }
        catch { XCTAssertEqual(error as? VaultError, .alreadyExists) }
        do { _ = try await store.create(name: "../outside", directory: false, parent: root, root: root); XCTFail("경로 탈출") }
        catch { XCTAssertEqual(error as? VaultError, .invalidName) }
    }

    func testSavePreservesOriginalTextAndRejectsExternalChanges() async throws {
        let store = VaultFileStore()
        let url = root.appendingPathComponent("Note.md")
        let original = "---\r\n# comment\r\npriority: 1\r\n---\r\n**bold**\r\n"
        try Data(original.utf8).write(to: url)
        let snapshot = try await store.snapshot(at: url)
        XCTAssertEqual(snapshot.text, original)
        let saved = try await store.save(original + "한글", document: snapshot, root: root)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), original + "한글")
        try "external".write(to: url, atomically: true, encoding: .utf8)
        do { _ = try await store.save("draft", document: saved, root: root); XCTFail("외부 변경 덮어쓰기") }
        catch { XCTAssertEqual(error as? VaultError, .conflict) }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "external")
    }

    func testSymlinkCannotEscapeRoot() async throws {
        let store = VaultFileStore()
        let link = root.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.deletingLastPathComponent())
        do { _ = try await store.resource(path: "escape/secret", vault: root); XCTFail("심볼릭 링크 경로 탈출") }
        catch { XCTAssertEqual(error as? VaultError, .outsideRoot) }
    }

    func testIndexRefreshReflectsCreationModificationAndDeletion() async throws {
        let store = VaultFileStore()
        let url = try await store.create(name: "First", directory: false, parent: root, root: root)
        let first = try await store.index(vault: root)
        XCTAssertEqual(first.map(\.path), ["First.md"])
        let snapshot = try await store.snapshot(at: url)
        _ = try await store.save("# Changed", document: snapshot, root: root)
        let updated = try await store.index(vault: root)
        XCTAssertEqual(updated.first?.text, "# Changed")
        try FileManager.default.removeItem(at: url)
        let deleted = try await store.index(vault: root)
        XCTAssertTrue(deleted.isEmpty)
    }

    func testDeleteRemovesFileAndRejectsRootOrOutsideRoot() async throws {
        let store = VaultFileStore()
        let url = try await store.create(name: "DeleteTarget", directory: false, parent: root, root: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        try await store.delete(at: url, root: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        do {
            try await store.delete(at: root, root: root)
            XCTFail("루트 삭제 거부 실패")
        } catch {
            XCTAssertEqual(error as? VaultError, .outsideRoot)
        }
    }
}
