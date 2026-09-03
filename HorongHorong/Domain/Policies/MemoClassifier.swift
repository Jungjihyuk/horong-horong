import Foundation

/// 섹션이 정해지지 않은 기록을 내용으로 분류한다.
///
/// 지금은 `Memo.init` 이 생성 시점에 섹션을 정하므로 새 기록에는 쓰이지 않는다.
/// 이관 전 기록을 메우는 `migrateMemoSections` 가 주 사용처다.
enum MemoClassifier {
    /// 기존 메모 이관 규칙. 이미 `sectionRaw` 가 있는 기록에는 쓰지 않는다.
    /// URL(첫 줄 또는 전체) → References, 아니면 시작/마감이 있으면 Todo, 나머지 Quick Note.
    static func classify(content: String, startDate: Date?, deadline: Date?) -> MemoSection {
        if looksLikeURL(content) { return .reference }
        if startDate != nil || deadline != nil { return .todo }
        return .quickNote
    }

    static func looksLikeURL(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let firstLine = trimmed
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? trimmed
        return isURLString(firstLine) || isURLString(trimmed)
    }

    static func isURLString(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: value), let scheme = url.scheme?.lowercased() {
            return scheme == "http" || scheme == "https"
        }
        if value.lowercased().hasPrefix("www."),
           URL(string: "https://\(value)") != nil {
            return true
        }
        return false
    }

    static func firstURL(in content: String) -> URL? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? trimmed
        if let url = url(from: firstLine) { return url }
        return url(from: trimmed)
    }

    private static func url(from raw: String) -> URL? {
        if let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return url
        }
        if raw.lowercased().hasPrefix("www.") {
            return URL(string: "https://\(raw)")
        }
        return nil
    }
}
