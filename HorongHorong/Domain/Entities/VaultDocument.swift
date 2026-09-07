import Foundation

struct VaultDocument: Sendable, Equatable {
    let url: URL
    let text: String
    let revision: String
}

struct VaultIndexedDocument: Sendable, Equatable, Codable {
    let path: String
    let text: String
    let modified: Double
    let created: Double
    let size: Int
}

struct VaultLocation: Sendable, Equatable {
    let root: URL
    let reference: URL
}

enum VaultError: Error, LocalizedError, Equatable {
    case invalidName, outsideRoot, alreadyExists, conflict, unavailable, readOnly

    var errorDescription: String? {
        switch self {
        case .invalidName: "이름에는 /, :, 줄바꿈을 사용할 수 없습니다."
        case .outsideRoot: "선택한 폴더 밖의 경로입니다."
        case .alreadyExists: "같은 이름의 항목이 이미 있습니다."
        case .conflict: "파일이 다른 앱에서 변경되었습니다. 내 변경은 초안으로 보관됩니다."
        case .unavailable: "폴더나 파일을 읽을 수 없습니다. 위치와 접근 권한을 확인하세요."
        case .readOnly: "참조 문서입니다. 편집하려면 이 문서가 포함된 폴더를 루트로 선택하세요."
        }
    }
}

enum VaultPathPolicy {
    static func canonicalURL(_ url: URL) -> URL {
        var current = url.standardizedFileURL
        var missingComponents: [String] = []
        let fm = FileManager.default
        while !fm.fileExists(atPath: current.path) && current.path != "/" {
            missingComponents.append(current.lastPathComponent)
            current = current.deletingLastPathComponent()
        }
        var resolved = current.resolvingSymlinksInPath()
        for comp in missingComponents.reversed() {
            resolved = resolved.appendingPathComponent(comp)
        }
        return resolved.standardizedFileURL
    }

    static func contains(_ url: URL, in root: URL) -> Bool {
        let path = canonicalURL(url).path
        let base = canonicalURL(root).path
        return path == base || path.hasPrefix(base == "/" ? "/" : base + "/")
    }

    static func filename(_ input: String, directory: Bool) throws -> String {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/"), !name.contains(":"),
              name.rangeOfCharacter(from: .controlCharacters) == nil else { throw VaultError.invalidName }
        return directory || name.lowercased().hasSuffix(".md") ? name : name + ".md"
    }
}
