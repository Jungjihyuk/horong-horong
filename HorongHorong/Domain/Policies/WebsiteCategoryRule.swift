import Foundation

struct WebsiteCategoryMatch: Equatable, Sendable {
    let domain: String
    let category: String
}

enum WebsiteCategoryRule {
    static let bundleIdentifierPrefix = "website-domain://"

    static func normalizedDomain(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let source = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: source),
              var host = components.host?.lowercased(),
              !host.isEmpty,
              !host.contains(where: \.isWhitespace) else {
            return nil
        }

        while host.hasSuffix(".") {
            host.removeLast()
        }
        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        guard !host.isEmpty else { return nil }
        return host
    }

    static func bundleIdentifier(for domain: String) -> String {
        "\(bundleIdentifierPrefix)\(domain)"
    }

    static func domain(from bundleIdentifier: String) -> String? {
        guard bundleIdentifier.hasPrefix(bundleIdentifierPrefix) else { return nil }
        let domain = String(bundleIdentifier.dropFirst(bundleIdentifierPrefix.count))
        return normalizedDomain(from: domain)
    }

    static func matchesTrackedBundleIdentifier(
        _ trackedBundleIdentifier: String,
        domain: String
    ) -> Bool {
        guard let normalizedDomain = normalizedDomain(from: domain) else { return false }
        return trackedBundleIdentifier.hasSuffix(".website.\(normalizedDomain)")
    }

    static func bestMatch(
        for url: String,
        rules: [String: String]
    ) -> WebsiteCategoryMatch? {
        guard let components = URLComponents(string: url),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased() else {
            return nil
        }

        return rules.keys
            .filter { host == $0 || host.hasSuffix(".\($0)") }
            .sorted { $0.count > $1.count }
            .first
            .flatMap { domain in
                rules[domain].map {
                    WebsiteCategoryMatch(domain: domain, category: $0)
                }
            }
    }
}
