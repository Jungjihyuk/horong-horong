import Foundation

enum SwiftDataStoreLocation {
    enum Scope: Equatable {
        case production
        case development

        var directoryName: String {
            switch self {
            case .production:
                "HorongHorong"
            case .development:
                "HorongHorong-Debug"
            }
        }
    }

    static let directoryName = "HorongHorong"
    static let storeFileName = "default.store"
    static let maximumBackupCount = 5

    private static let storesDirectoryName = "Stores"
    private static let backupsDirectoryName = "Backups"
    private static let activeBackupsDirectoryName = "current"
    /// 단일 저장소 도입 전 사용하던 경로. 새 저장소가 없을 때만 최신 순서로 복사한다.
    private static let legacyStoreDirectoryNames = ["v2", "v1"]
    private static let storeFileSuffixes = ["", "-shm", "-wal"]

    static var currentScope: Scope {
        #if DEBUG
        .development
        #else
        .production
        #endif
    }

    static func applicationDirectoryURL(
        fileManager: FileManager = .default
    ) throws -> URL {
        guard let applicationSupportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw SwiftDataStoreLocationError.missingApplicationSupportDirectory
        }

        return applicationSupportDirectory.appendingPathComponent(
            currentScope.directoryName,
            isDirectory: true
        )
    }

    static func storeURL(fileManager: FileManager = .default) throws -> URL {
        guard let applicationSupportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw SwiftDataStoreLocationError.missingApplicationSupportDirectory
        }

        return try storeURL(
            applicationSupportDirectory: applicationSupportDirectory,
            scope: currentScope,
            fileManager: fileManager
        )
    }

    static func storeURL(
        applicationSupportDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        try storeURL(
            applicationSupportDirectory: applicationSupportDirectory,
            scope: .production,
            fileManager: fileManager
        )
    }

    static func storeURL(
        applicationSupportDirectory: URL,
        scope: Scope,
        backupIdentifier: String? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let appDirectory = applicationSupportDirectory.appendingPathComponent(
            scope.directoryName,
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: appDirectory,
            withIntermediateDirectories: true
        )
        let storesDirectory = appDirectory.appendingPathComponent(
            storesDirectoryName,
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: storesDirectory,
            withIntermediateDirectories: true
        )

        let targetStoreURL = storesDirectory.appendingPathComponent(
            storeFileName,
            isDirectory: false
        )
        let targetExisted = fileManager.fileExists(atPath: targetStoreURL.path)

        if !targetExisted {
            try migrateStoreIfNeeded(
                applicationSupportDirectory: applicationSupportDirectory,
                appDirectory: appDirectory,
                targetStoreURL: targetStoreURL,
                scope: scope,
                fileManager: fileManager
            )
        } else {
            try backupStoreIfNeeded(
                storeURL: targetStoreURL,
                appDirectory: appDirectory,
                identifier: backupIdentifier ?? currentBuildIdentifier,
                fileManager: fileManager
            )
        }

        return targetStoreURL
    }

    private static var currentBuildIdentifier: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        return "\(version)-\(build)"
    }

    private static func migrateStoreIfNeeded(
        applicationSupportDirectory: URL,
        appDirectory: URL,
        targetStoreURL: URL,
        scope: Scope,
        fileManager: FileManager
    ) throws {
        var candidates = legacyStoreDirectoryNames.map { directoryName in
            appDirectory
                .appendingPathComponent(storesDirectoryName, isDirectory: true)
                .appendingPathComponent(directoryName, isDirectory: true)
                .appendingPathComponent(storeFileName, isDirectory: false)
        }

        candidates.append(
            appDirectory.appendingPathComponent(storeFileName, isDirectory: false)
        )

        if scope == .production {
            candidates.append(
                applicationSupportDirectory.appendingPathComponent(
                    storeFileName,
                    isDirectory: false
                )
            )
        }

        guard let sourceStoreURL = candidates.first(where: {
            fileManager.fileExists(atPath: $0.path)
        }) else {
            return
        }

        try copyStoreFiles(
            from: sourceStoreURL,
            to: targetStoreURL,
            fileManager: fileManager
        )
    }

    private static func backupStoreIfNeeded(
        storeURL: URL,
        appDirectory: URL,
        identifier: String,
        fileManager: FileManager
    ) throws {
        let backupRoot = appDirectory
            .appendingPathComponent(backupsDirectoryName, isDirectory: true)
            .appendingPathComponent(activeBackupsDirectoryName, isDirectory: true)
        try fileManager.createDirectory(
            at: backupRoot,
            withIntermediateDirectories: true
        )

        let safeIdentifier = sanitizedBackupIdentifier(identifier)
        let backupDirectory = backupRoot.appendingPathComponent(
            safeIdentifier,
            isDirectory: true
        )
        guard !fileManager.fileExists(atPath: backupDirectory.path) else { return }

        let stagingDirectory = backupRoot.appendingPathComponent(
            ".\(safeIdentifier)-\(UUID().uuidString)",
            isDirectory: true
        )

        do {
            try fileManager.createDirectory(
                at: stagingDirectory,
                withIntermediateDirectories: true
            )
            let stagedStoreURL = stagingDirectory.appendingPathComponent(
                storeFileName,
                isDirectory: false
            )
            try copyStoreFiles(
                from: storeURL,
                to: stagedStoreURL,
                fileManager: fileManager
            )
            try fileManager.moveItem(at: stagingDirectory, to: backupDirectory)
        } catch {
            try? fileManager.removeItem(at: stagingDirectory)
            throw error
        }

        try removeExpiredBackups(in: backupRoot, fileManager: fileManager)
    }

    private static func copyStoreFiles(
        from sourceStoreURL: URL,
        to targetStoreURL: URL,
        fileManager: FileManager
    ) throws {
        var copiedURLs: [URL] = []

        do {
            for suffix in storeFileSuffixes {
                let sourceURL = URL(
                    fileURLWithPath: sourceStoreURL.path + suffix,
                    isDirectory: false
                )
                guard fileManager.fileExists(atPath: sourceURL.path) else { continue }

                let targetURL = URL(
                    fileURLWithPath: targetStoreURL.path + suffix,
                    isDirectory: false
                )
                guard !fileManager.fileExists(atPath: targetURL.path) else { continue }

                try fileManager.copyItem(at: sourceURL, to: targetURL)
                copiedURLs.append(targetURL)
            }
        } catch {
            for copiedURL in copiedURLs {
                try? fileManager.removeItem(at: copiedURL)
            }
            throw error
        }
    }

    private static func removeExpiredBackups(
        in backupRoot: URL,
        fileManager: FileManager
    ) throws {
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .contentModificationDateKey,
        ]
        let backups = try fileManager.contentsOfDirectory(
            at: backupRoot,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )
        .filter {
            (try? $0.resourceValues(forKeys: resourceKeys).isDirectory) == true
        }
        .sorted {
            let left = try? $0.resourceValues(forKeys: resourceKeys).contentModificationDate
            let right = try? $1.resourceValues(forKeys: resourceKeys).contentModificationDate
            return (left ?? .distantPast) < (right ?? .distantPast)
        }

        for backup in backups.dropLast(maximumBackupCount) {
            try fileManager.removeItem(at: backup)
        }
    }

    private static func sanitizedBackupIdentifier(_ identifier: String) -> String {
        let components = identifier.components(
            separatedBy: CharacterSet.alphanumerics.inverted
        )
        let sanitized = components.filter { !$0.isEmpty }.joined(separator: "-")
        return sanitized.isEmpty ? "unknown" : sanitized
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
