import Foundation

enum ReferenceURLPolicy {
    static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \Character.isWhitespace) else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host, host.contains(".") else { return nil }
        return components.url?.absoluteString
    }

    static func fallbackTitle(for normalizedURL: String) -> String {
        let host = URL(string: normalizedURL)?.host() ?? normalizedURL
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
