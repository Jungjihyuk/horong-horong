import Foundation

enum MemoSection: String, CaseIterable, Identifiable {
    case quickNote
    case todo
    case reference

    var id: String { rawValue }
}

enum TodoBucket: String, CaseIterable, Identifiable {
    case overdue
    case today
    case upcoming
    case someday
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overdue: return "지남"
        case .today: return "오늘"
        case .upcoming: return "예정"
        case .someday: return "언젠가"
        case .completed: return "완료"
        }
    }

    var symbol: String {
        switch self {
        case .overdue: return "exclamationmark.circle"
        case .today: return "sun.max"
        case .upcoming: return "calendar"
        case .someday: return "tray"
        case .completed: return "checkmark.circle"
        }
    }

    /// 기준일 = 마감, 없으면 시작일. 날짜 없음 = 언젠가.
    static func of(
        startDate: Date?,
        deadline: Date?,
        isCompleted: Bool,
        now: Date,
        calendar: Calendar = .current
    ) -> TodoBucket {
        if isCompleted { return .completed }
        guard let basis = deadline ?? startDate else { return .someday }
        let day = calendar.startOfDay(for: basis)
        let today = calendar.startOfDay(for: now)
        if day < today { return .overdue }
        if day == today { return .today }
        return .upcoming
    }

    /// 카드를 섹션으로 떨어뜨렸을 때 날짜·완료 상태를 어떻게 바꿀지.
    static func placement(
        into bucket: TodoBucket,
        startDate: Date?,
        deadline: Date?,
        isCompleted: Bool,
        now: Date,
        calendar: Calendar = .current
    ) -> (startDate: Date?, deadline: Date?, isCompleted: Bool) {
        let current = of(
            startDate: startDate,
            deadline: deadline,
            isCompleted: isCompleted,
            now: now,
            calendar: calendar
        )
        switch bucket {
        case .completed:
            return (startDate, deadline, true)
        case .someday:
            return (nil, nil, false)
        case .today:
            return dated(now, offset: 0, startDate: startDate, deadline: deadline, calendar: calendar)
        case .upcoming:
            if current == .upcoming {
                return (startDate, deadline, false)
            }
            return dated(now, offset: 1, startDate: startDate, deadline: deadline, calendar: calendar)
        case .overdue:
            if current == .overdue {
                return (startDate, deadline, false)
            }
            return dated(now, offset: -1, startDate: startDate, deadline: deadline, calendar: calendar)
        }
    }

    private static func dated(
        _ now: Date,
        offset: Int,
        startDate: Date?,
        deadline: Date?,
        calendar: Calendar
    ) -> (startDate: Date?, deadline: Date?, isCompleted: Bool) {
        let day = calendar.date(byAdding: .day, value: offset, to: now) ?? now
        let stamped = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        if deadline != nil {
            let start = startDate.map { min($0, stamped) } ?? nil
            return (start, stamped, false)
        }
        return (stamped, nil, false)
    }
}

struct TodoDueChip: Equatable {
    enum Tone: Equatable {
        case over
        case today
        case soon
        case later
    }

    let label: String
    let tone: Tone

    static func of(
        startDate: Date?,
        deadline: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> TodoDueChip? {
        guard let basis = deadline ?? startDate else { return nil }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: basis)
        ).day ?? 0
        if days < 0 {
            return TodoDueChip(label: "\(-days)일 지남", tone: .over)
        }
        if days == 0 {
            return TodoDueChip(label: "오늘", tone: .today)
        }
        if days == 1 {
            return TodoDueChip(label: "내일", tone: .soon)
        }
        if days <= 6 {
            return TodoDueChip(label: "\(days)일 뒤", tone: .soon)
        }
        let month = calendar.component(.month, from: basis)
        let day = calendar.component(.day, from: basis)
        return TodoDueChip(label: "\(month)월 \(day)일", tone: .later)
    }
}

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

enum DiaryMood: String, CaseIterable, Identifiable {
    case great = "최고"
    case good = "좋음"
    case ok = "보통"
    case low = "별로"
    case bad = "나쁨"

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .great: return "😄"
        case .good: return "🙂"
        case .ok: return "😐"
        case .low: return "😕"
        case .bad: return "😞"
        }
    }
}
