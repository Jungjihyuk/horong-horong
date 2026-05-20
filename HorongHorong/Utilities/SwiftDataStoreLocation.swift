import Foundation

enum SwiftDataStoreLocation {
    static let directoryName = "HorongHorong"
    static let storeFileName = "default.store"

    private static let storeFileSuffixes = ["", "-shm", "-wal"]

    static func storeURL(fileManager: FileManager = .default) throws -> URL {
        guard let applicationSupportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw SwiftDataStoreLocationError.missingApplicationSupportDirectory
        }

        return try storeURL(
            applicationSupportDirectory: applicationSupportDirectory,
            fileManager: fileManager
        )
    }

    static func storeURL(
        applicationSupportDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let appDirectory = applicationSupportDirectory.appendingPathComponent(
            directoryName,
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: appDirectory,
            withIntermediateDirectories: true
        )
        try migrateLegacyStoreIfNeeded(
            applicationSupportDirectory: applicationSupportDirectory,
            appDirectory: appDirectory,
            fileManager: fileManager
        )

        return appDirectory.appendingPathComponent(storeFileName, isDirectory: false)
    }

    private static func migrateLegacyStoreIfNeeded(
        applicationSupportDirectory: URL,
        appDirectory: URL,
        fileManager: FileManager
    ) throws {
        let targetStoreURL = appDirectory.appendingPathComponent(storeFileName, isDirectory: false)
        guard !fileManager.fileExists(atPath: targetStoreURL.path) else { return }

        let legacyStoreURL = applicationSupportDirectory.appendingPathComponent(
            storeFileName,
            isDirectory: false
        )
        guard fileManager.fileExists(atPath: legacyStoreURL.path) else { return }

        for suffix in storeFileSuffixes {
            let legacyFileURL = applicationSupportDirectory.appendingPathComponent(
                storeFileName + suffix,
                isDirectory: false
            )
            let targetFileURL = appDirectory.appendingPathComponent(
                storeFileName + suffix,
                isDirectory: false
            )

            guard fileManager.fileExists(atPath: legacyFileURL.path),
                  !fileManager.fileExists(atPath: targetFileURL.path) else {
                continue
            }

            try fileManager.copyItem(at: legacyFileURL, to: targetFileURL)
        }
    }
}

enum SwiftDataStoreLocationError: LocalizedError {
    case missingApplicationSupportDirectory

    var errorDescription: String? {
        switch self {
        case .missingApplicationSupportDirectory:
            "Application Support 디렉터리를 찾을 수 없습니다."
        }
    }
}
