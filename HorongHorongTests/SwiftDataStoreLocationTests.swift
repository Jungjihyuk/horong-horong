import XCTest
@testable import 호롱호롱

final class SwiftDataStoreLocationTests: XCTestCase {
    func testStoreURLUsesAppSpecificApplicationSupportDirectory() throws {
        let applicationSupportDirectory = temporaryApplicationSupportDirectory()

        let storeURL = try SwiftDataStoreLocation.storeURL(
            applicationSupportDirectory: applicationSupportDirectory
        )

        XCTAssertEqual(
            storeURL.path,
            applicationSupportDirectory
                .appendingPathComponent("HorongHorong", isDirectory: true)
                .appendingPathComponent("default.store", isDirectory: false)
                .path
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: applicationSupportDirectory
                    .appendingPathComponent("HorongHorong", isDirectory: true)
                    .path
            )
        )
    }

    func testStoreURLCopiesLegacyStoreFilesWhenNewStoreDoesNotExist() throws {
        let applicationSupportDirectory = temporaryApplicationSupportDirectory()
        try writeLegacyStoreFiles(in: applicationSupportDirectory)

        _ = try SwiftDataStoreLocation.storeURL(
            applicationSupportDirectory: applicationSupportDirectory
        )

        let appDirectory = applicationSupportDirectory.appendingPathComponent(
            "HorongHorong",
            isDirectory: true
        )
        XCTAssertEqual(
            try String(contentsOf: appDirectory.appendingPathComponent("default.store")),
            "store"
        )
        XCTAssertEqual(
            try String(contentsOf: appDirectory.appendingPathComponent("default.store-shm")),
            "shm"
        )
        XCTAssertEqual(
            try String(contentsOf: appDirectory.appendingPathComponent("default.store-wal")),
            "wal"
        )
    }

    func testStoreURLDoesNotOverwriteExistingAppStore() throws {
        let applicationSupportDirectory = temporaryApplicationSupportDirectory()
        let appDirectory = applicationSupportDirectory.appendingPathComponent(
            "HorongHorong",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: appDirectory,
            withIntermediateDirectories: true
        )
        try "existing".write(
            to: appDirectory.appendingPathComponent("default.store"),
            atomically: true,
            encoding: .utf8
        )
        try writeLegacyStoreFiles(in: applicationSupportDirectory)

        _ = try SwiftDataStoreLocation.storeURL(
            applicationSupportDirectory: applicationSupportDirectory
        )

        XCTAssertEqual(
            try String(contentsOf: appDirectory.appendingPathComponent("default.store")),
            "existing"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: appDirectory.appendingPathComponent("default.store-wal").path
            )
        )
    }

    private func temporaryApplicationSupportDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func writeLegacyStoreFiles(in applicationSupportDirectory: URL) throws {
        try FileManager.default.createDirectory(
            at: applicationSupportDirectory,
            withIntermediateDirectories: true
        )
        try "store".write(
            to: applicationSupportDirectory.appendingPathComponent("default.store"),
            atomically: true,
            encoding: .utf8
        )
        try "shm".write(
            to: applicationSupportDirectory.appendingPathComponent("default.store-shm"),
            atomically: true,
            encoding: .utf8
        )
        try "wal".write(
            to: applicationSupportDirectory.appendingPathComponent("default.store-wal"),
            atomically: true,
            encoding: .utf8
        )
    }
}
