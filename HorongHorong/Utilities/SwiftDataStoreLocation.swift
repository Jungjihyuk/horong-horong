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
    // 구버전이 새 스키마를 열지 못하도록 @Model 속성이나 엔티티 변경 시 반드시 증가시킨다.
    static let storeGeneration = 2
    static let maximumBackupCount = 5

    private static let storesDirectoryName = "Stores"
    private static let backupsDirectoryName = "Backups"
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
        let generationDirectory = appDirectory
            .appendingPathComponent(storesDirectoryName, isDirectory: true)
            .appendingPathComponent("v\(storeGeneration)", isDirectory: true)
        try fileManager.createDirectory(
            at: generationDirectory,
            withIntermediateDirectories: true
        )

        let targetStoreURL = generationDirectory.appendingPathComponent(
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
        var candidates: [URL] = []

        if storeGeneration > 1 {
            for generation in stride(from: storeGeneration - 1, through: 1, by: -1) {
                candidates.append(
                    appDirectory
                        .appendingPathComponent(storesDirectoryName, isDirectory: true)
                        .appendingPathComponent("v\(generation)", isDirectory: true)
                        .appendingPathComponent(storeFileName, isDirectory: false)
                )
            }
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
            .appendingPathComponent("v\(storeGeneration)", isDirectory: true)
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
