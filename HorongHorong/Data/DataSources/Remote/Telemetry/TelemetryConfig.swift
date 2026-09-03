import Foundation

struct TelemetryConfig {
    let supabaseURL: URL
    let publishableKey: String

    var isConfigured: Bool {
        !publishableKey.isEmpty
    }

    static func load(bundle: Bundle = .main) -> TelemetryConfig? {
        if let config = loadFromInfoPlist(bundle: bundle) {
            return config
        }

#if DEBUG
        return loadFromLocalSecrets(bundle: bundle)
#else
        return nil
#endif
    }

    private static func loadFromInfoPlist(bundle: Bundle) -> TelemetryConfig? {
        guard
            let rawURL = bundle.object(forInfoDictionaryKey: "SupabaseURL") as? String,
            let rawKey = bundle.object(forInfoDictionaryKey: "SupabasePublishableKey") as? String
        else {
            return nil
        }

        return makeConfig(rawURL: rawURL, rawKey: rawKey)
    }

    private static func makeConfig(rawURL: String, rawKey: String) -> TelemetryConfig? {
        let urlString = rawURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/$()/", with: "//")
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !urlString.isEmpty,
            !key.isEmpty,
            !urlString.hasPrefix("$("),
            !key.hasPrefix("$("),
            let url = URL(string: urlString)
        else {
            return nil
        }

        return TelemetryConfig(
            supabaseURL: url,
            publishableKey: key
        )
    }

#if DEBUG
    private static func loadFromLocalSecrets(bundle: Bundle) -> TelemetryConfig? {
        for directory in candidateDirectories(bundle: bundle) {
            let fileURL = directory
                .appendingPathComponent("HorongHorong")
                .appendingPathComponent("Config")
                .appendingPathComponent("Secrets.xcconfig")

            if let config = loadSecretsFile(fileURL) {
                return config
            }
        }

        return nil
    }

    private static func candidateDirectories(bundle: Bundle) -> [URL] {
        var candidates: [URL] = []
        appendParentDirectories(from: bundle.bundleURL, to: &candidates)
        appendParentDirectories(from: URL(fileURLWithPath: FileManager.default.currentDirectoryPath), to: &candidates)
        appendParentDirectories(from: URL(fileURLWithPath: #filePath), to: &candidates)

        return candidates.reduce(into: []) { unique, url in
            if !unique.contains(url) {
                unique.append(url)
            }
        }
    }

    private static func appendParentDirectories(from url: URL, to candidates: inout [URL]) {
        var current = url
        for _ in 0..<12 {
            candidates.append(current)
            let parent = current.deletingLastPathComponent()
            if parent == current {
                break
            }
            current = parent
        }
    }

    private static func loadSecretsFile(_ fileURL: URL) -> TelemetryConfig? {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }

        var values: [String: String] = [:]
        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else {
                continue
            }

            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            values[key] = value
        }

        guard
            let rawURL = values["SUPABASE_URL"],
            let rawKey = values["SUPABASE_PUBLISHABLE_KEY"]
        else {
            return nil
        }

        return makeConfig(rawURL: rawURL, rawKey: rawKey)
    }
#endif
}

enum TelemetryRuntimeInfo {
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    static var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}

enum AnonymousInstallID {
    static func current(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: Constants.AppStorageKey.anonymousInstallId),
           !existing.isEmpty {
            return existing
        }

        let generated = UUID().uuidString
        defaults.set(generated, forKey: Constants.AppStorageKey.anonymousInstallId)
        return generated
    }
}
