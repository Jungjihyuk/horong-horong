import XCTest
@testable import 호롱호롱

final class SwiftDataStoreLocationTests: XCTestCase {
    func testStoreURLUsesVersionedProductionDirectory() throws {
        let applicationSupportDirectory = temporaryApplicationSupportDirectory()

        let storeURL = try SwiftDataStoreLocation.storeURL(
            applicationSupportDirectory: applicationSupportDirectory
        )

        XCTAssertEqual(
            storeURL.path,
            versionedStoreURL(
                in: applicationSupportDirectory,
                scope: .production
            ).path
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: storeURL.deletingLastPathComponent().path
            )
        )
    }

    func testStoreURLCopiesUnversionedAppStoreIntoCurrentGeneration() throws {
        let applicationSupportDirectory = temporaryApplicationSupportDirectory()
        let unversionedStoreURL = applicationSupportDirectory
            .appendingPathComponent("HorongHorong", isDirectory: true)
            .appendingPathComponent("default.store", isDirectory: false)
        try writeStoreFiles(at: unversionedStoreURL)

        let storeURL = try SwiftDataStoreLocation.storeURL(
            applicationSupportDirectory: applicationSupportDirectory
        )

        try assertStoreFiles(at: storeURL)
    }

    func testStoreURLCopiesPreviousGenerationIntoCurrentGeneration() throws {
        let applicationSupportDirectory = temporaryApplicationSupportDirectory()
        let previousStoreURL = applicationSupportDirectory
            .appendingPathComponent("HorongHorong", isDirectory: true)
            .appendingPathComponent("Stores", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
            .appendingPathComponent("default.store", isDirectory: false)
        try writeStoreFiles(at: previousStoreURL)

        let storeURL = try SwiftDataStoreLocation.storeURL(
            applicationSupportDirectory: applicationSupportDirectory
        )

        try assertStoreFiles(at: storeURL)
    }

    func testStoreURLCopiesLegacyRootStoreIntoCurrentGeneration() throws {
        let applicationSupportDirectory = temporaryApplicationSupportDirectory()
        let legacyStoreURL = applicationSupportDirectory.appendingPathComponent(
            "default.store",
            isDirectory: false
        )
        try writeStoreFiles(at: legacyStoreURL)

        let storeURL = try SwiftDataStoreLocation.storeURL(
            applicationSupportDirectory: applicationSupportDirectory
        )

        try assertStoreFiles(at: storeURL)
    }

    func testStoreURLDoesNotOverwriteExistingVersionedStore() throws {
        let applicationSupportDirectory = temporaryApplicationSupportDirectory()
        let storeURL = versionedStoreURL(
            in: applicationSupportDirectory,
            scope: .production
        )
        try writeStoreFiles(at: storeURL, includeSidecars: false, storeContents: "existing")
        try writeStoreFiles(
            at: applicationSupportDirectory.appendingPathComponent("default.store")
        )

        _ = try SwiftDataStoreLocation.storeURL(
            applicationSupportDirectory: applicationSupportDirectory,
            scope: .production,
            backupIdentifier: "existing-build"
        )

        XCTAssertEqual(try String(contentsOf: storeURL), "existing")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: storeURL.path + "-wal")
        )
    }

    func testDevelopmentStoreIsIsolatedFromProductionData() throws {
        let applicationSupportDirectory = temporaryApplicationSupportDirectory()
        try writeStoreFiles(
            at: applicationSupportDirectory
                .appendingPathComponent("HorongHorong", isDirectory: true)
                .appendingPathComponent("default.store", isDirectory: false)
        )
        try writeStoreFiles(
            at: applicationSupportDirectory.appendingPathComponent("default.store")
        )

        let developmentStoreURL = try SwiftDataStoreLocation.storeURL(
            applicationSupportDirectory: applicationSupportDirectory,
            scope: .development
        )

        XCTAssertEqual(
            developmentStoreURL,
            versionedStoreURL(
                in: applicationSupportDirectory,
                scope: .development
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: developmentStoreURL.path)
        )
    }

    func testExistingStoreIsBackedUpOncePerBuild() throws {
        let applicationSupportDirectory = temporaryApplicationSupportDirectory()
        let storeURL = versionedStoreURL(
            in: applicationSupportDirectory,
            scope: .production
        )
        try writeStoreFiles(at: storeURL)

        _ = try SwiftDataStoreLocation.storeURL(
            applicationSupportDirectory: applicationSupportDirectory,
            scope: .production,
            backupIdentifier: "0.2.2 (3)"
        )
        try "changed".write(to: storeURL, atomically: true, encoding: .utf8)
        _ = try SwiftDataStoreLocation.storeURL(
            applicationSupportDirectory: applicationSupportDirectory,
            scope: .production,
            backupIdentifier: "0.2.2 (3)"
        )

        let backupStoreURL = backupRoot(
            in: applicationSupportDirectory,
            scope: .production
        )
        .appendingPathComponent("0-2-2-3", isDirectory: true)
        .appendingPathComponent("default.store", isDirectory: false)
        XCTAssertEqual(try String(contentsOf: backupStoreURL), "store")
        XCTAssertEqual(
            try String(contentsOf: URL(fileURLWithPath: backupStoreURL.path + "-shm")),
            "shm"
        )
        XCTAssertEqual(
            try String(contentsOf: URL(fileURLWithPath: backupStoreURL.path + "-wal")),
            "wal"
        )
    }

    func testBackupRetentionKeepsLatestFiveBuilds() throws {
        let applicationSupportDirectory = temporaryApplicationSupportDirectory()
        let storeURL = versionedStoreURL(
            in: applicationSupportDirectory,
            scope: .production
        )
        try writeStoreFiles(at: storeURL)

        for index in 0...SwiftDataStoreLocation.maximumBackupCount {
            _ = try SwiftDataStoreLocation.storeURL(
                applicationSupportDirectory: applicationSupportDirectory,
                scope: .production,
                backupIdentifier: "build-\(index)"
            )
        }

        let backups = try FileManager.default.contentsOfDirectory(
            at: backupRoot(
                in: applicationSupportDirectory,
                scope: .production
            ),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        XCTAssertEqual(backups.count, SwiftDataStoreLocation.maximumBackupCount)
    }

    private func temporaryApplicationSupportDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func versionedStoreURL(
        in applicationSupportDirectory: URL,
        scope: SwiftDataStoreLocation.Scope
    ) -> URL {
        applicationSupportDirectory
            .appendingPathComponent(scope.directoryName, isDirectory: true)
            .appendingPathComponent("Stores", isDirectory: true)
            .appendingPathComponent(
                "v\(SwiftDataStoreLocation.storeGeneration)",
                isDirectory: true
            )
            .appendingPathComponent("default.store", isDirectory: false)
    }

    private func backupRoot(
        in applicationSupportDirectory: URL,
        scope: SwiftDataStoreLocation.Scope
    ) -> URL {
        applicationSupportDirectory
            .appendingPathComponent(scope.directoryName, isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent(
                "v\(SwiftDataStoreLocation.storeGeneration)",
                isDirectory: true
            )
    }

    private func writeStoreFiles(
        at storeURL: URL,
        includeSidecars: Bool = true,
        storeContents: String = "store"
    ) throws {
        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try storeContents.write(to: storeURL, atomically: true, encoding: .utf8)
        guard includeSidecars else { return }

        try "shm".write(
            to: URL(fileURLWithPath: storeURL.path + "-shm"),
            atomically: true,
            encoding: .utf8
        )
        try "wal".write(
            to: URL(fileURLWithPath: storeURL.path + "-wal"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func assertStoreFiles(at storeURL: URL) throws {
        XCTAssertEqual(try String(contentsOf: storeURL), "store")
        XCTAssertEqual(
            try String(contentsOf: URL(fileURLWithPath: storeURL.path + "-shm")),
            "shm"
        )
        XCTAssertEqual(
            try String(contentsOf: URL(fileURLWithPath: storeURL.path + "-wal")),
            "wal"
        )
    }
}

final class AppUpdateManagerSafetyTests: XCTestCase {
    #if DEBUG
    @MainActor
    func testDebugBuildDisablesAppUpdates() {
        XCTAssertFalse(AppUpdateManager.updatesAllowedForCurrentBuild)
        XCTAssertFalse(AppUpdateManager.shared.canCheckForUpdates)
    }

    func testDebugBuildUsesIsolatedStoreScope() {
        XCTAssertEqual(SwiftDataStoreLocation.currentScope, .development)
    }
    #endif
}
