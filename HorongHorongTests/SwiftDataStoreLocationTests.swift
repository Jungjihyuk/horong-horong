import XCTest
@testable import 호롱호롱

final class SwiftDataStoreLocationTests: XCTestCase {
    func testStoreURLUsesStableProductionDirectory() throws {
        let applicationSupportDirectory = temporaryApplicationSupportDirectory()

        let storeURL = try SwiftDataStoreLocation.storeURL(
            applicationSupportDirectory: applicationSupportDirectory
        )

        XCTAssertEqual(
            storeURL.path,
            stableStoreURL(
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

    func testStoreURLCopiesUnversionedAppStoreIntoStableStore() throws {
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

    func testStoreURLCopiesVersionTwoStoreIntoStableStoreAndKeepsSource() throws {
        let applicationSupportDirectory = temporaryApplicationSupportDirectory()
        let versionTwoStoreURL = applicationSupportDirectory
            .appendingPathComponent("HorongHorong", isDirectory: true)
            .appendingPathComponent("Stores", isDirectory: true)
            .appendingPathComponent("v2", isDirectory: true)
            .appendingPathComponent("default.store", isDirectory: false)
        try writeStoreFiles(at: versionTwoStoreURL)

        let storeURL = try SwiftDataStoreLocation.storeURL(
            applicationSupportDirectory: applicationSupportDirectory
        )

        try assertStoreFiles(at: storeURL)
        try assertStoreFiles(at: versionTwoStoreURL)
    }

    func testStoreURLFallsBackToVersionOneStore() throws {
        let applicationSupportDirectory = temporaryApplicationSupportDirectory()
        let versionOneStoreURL = applicationSupportDirectory
            .appendingPathComponent("HorongHorong", isDirectory: true)
            .appendingPathComponent("Stores", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
            .appendingPathComponent("default.store", isDirectory: false)
        try writeStoreFiles(at: versionOneStoreURL)

        let storeURL = try SwiftDataStoreLocation.storeURL(
            applicationSupportDirectory: applicationSupportDirectory
        )

        try assertStoreFiles(at: storeURL)
    }

    func testStoreURLCopiesLegacyRootStoreIntoStableStore() throws {
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

    func testStoreURLDoesNotOverwriteExistingStableStore() throws {
        let applicationSupportDirectory = temporaryApplicationSupportDirectory()
        let storeURL = stableStoreURL(
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

    func testDevelopmentStoreSeedsFromProductionDataAndIsIsolated() throws {
        let applicationSupportDirectory = temporaryApplicationSupportDirectory()
        let prodStoreURL = applicationSupportDirectory
            .appendingPathComponent("HorongHorong", isDirectory: true)
            .appendingPathComponent("Stores", isDirectory: true)
            .appendingPathComponent("default.store", isDirectory: false)

        try writeStoreFiles(at: prodStoreURL, storeContents: "prod_data")

        let developmentStoreURL = try SwiftDataStoreLocation.storeURL(
            applicationSupportDirectory: applicationSupportDirectory,
            scope: .development
        )

        XCTAssertEqual(
            developmentStoreURL,
            stableStoreURL(
                in: applicationSupportDirectory,
                scope: .development
            )
        )
        // 1. 최초 실행 시 프로덕션 데이터가 디버그 저장소로 시드 복사됨
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: developmentStoreURL.path)
        )
        XCTAssertEqual(try String(contentsOf: developmentStoreURL), "prod_data")

        // 2. 디버그 저장소 수정 시 프로덕션 원본은 영향을 받지 않음 (격리 보장)
        try "debug_modified".write(to: developmentStoreURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(try String(contentsOf: prodStoreURL), "prod_data")
        XCTAssertEqual(try String(contentsOf: developmentStoreURL), "debug_modified")
    }

    func testExistingStoreIsBackedUpOncePerBuild() throws {
        let applicationSupportDirectory = temporaryApplicationSupportDirectory()
        let storeURL = stableStoreURL(
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
        let storeURL = stableStoreURL(
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

    private func stableStoreURL(
        in applicationSupportDirectory: URL,
        scope: SwiftDataStoreLocation.Scope
    ) -> URL {
        applicationSupportDirectory
            .appendingPathComponent(scope.directoryName, isDirectory: true)
            .appendingPathComponent("Stores", isDirectory: true)
            .appendingPathComponent("default.store", isDirectory: false)
    }

    private func backupRoot(
        in applicationSupportDirectory: URL,
        scope: SwiftDataStoreLocation.Scope
    ) -> URL {
        applicationSupportDirectory
            .appendingPathComponent(scope.directoryName, isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent("current", isDirectory: true)
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
