import Foundation

/// 브리핑에 쓰이는 일정 한 건. SwiftData 모델과 분리해 두어 로직만 따로 테스트한다.
struct CompanionBriefingItem: Hashable, Sendable {
    let title: String
    let isCompleted: Bool
    let startDate: Date?
    let deadline: Date?
}

struct CompanionBriefing: Hashable, Sendable {
    let headline: String
    let lines: [String]

    var isEmpty: Bool { lines.isEmpty }
}

enum CompanionBriefingComposer {
    /// 오늘 시작하거나 오늘 마감인 미완료 일정만 고른다. 마감이 이른 순으로 정렬한다.
    static func todayItems(
        from items: [CompanionBriefingItem],
        now: Date,
        calendar: Calendar = .current
    ) -> [CompanionBriefingItem] {
        items
            .filter { item in
                guard !item.isCompleted else { return false }
                let startsToday = item.startDate.map { calendar.isDate($0, inSameDayAs: now) } ?? false
                let dueToday = item.deadline.map { calendar.isDate($0, inSameDayAs: now) } ?? false
                return startsToday || dueToday
            }
            .sorted { lhs, rhs in
                switch (lhs.deadline, rhs.deadline) {
                case let (lhsDeadline?, rhsDeadline?):
                    return lhsDeadline < rhsDeadline
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.title < rhs.title
                }
            }
    }

    static func compose(
        items: [CompanionBriefingItem],
        now: Date,
        calendar: Calendar = .current,
        maxLineCount: Int = 3
    ) -> CompanionBriefing {
        let todays = todayItems(from: items, now: now, calendar: calendar)
        guard !todays.isEmpty else {
            return CompanionBriefing(headline: "오늘 일정 없음", lines: [])
        }

        var lines = todays.prefix(maxLineCount).map { item -> String in
            guard let deadline = item.deadline, calendar.isDate(deadline, inSameDayAs: now) else {
                return "• \(item.title)"
            }
            return "• \(item.title) — \(timeFormatter.string(from: deadline))"
        }
        let remaining = todays.count - lines.count
        if remaining > 0 {
            lines.append("… 그리고 \(remaining)개 더")
        }

        return CompanionBriefing(headline: "오늘 할 일 \(todays.count)개", lines: lines)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "a h:mm"
        return formatter
    }()
}

enum CompanionBriefingSchedule {
    /// `date` 이후 처음 도래하는 브리핑 시각. 오늘 시각이 이미 지났으면 내일로 넘긴다.
    static func nextFireDate(
        after date: Date,
        hour: Int,
        minute: Int,
        calendar: Calendar = .current
    ) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = normalizedHour(hour)
        components.minute = normalizedMinute(minute)
        components.second = 0
        guard let todayFireDate = calendar.date(from: components) else {
            return date.addingTimeInterval(60)
        }
        if todayFireDate > date { return todayFireDate }
        return calendar.date(byAdding: .day, value: 1, to: todayFireDate) ?? todayFireDate.addingTimeInterval(86_400)
    }

    /// 브리핑 시각을 지났고 오늘 아직 전달하지 않았을 때만 true.
    static func shouldDeliver(
        now: Date,
        hour: Int,
        minute: Int,
        lastDeliveredAt: Date?,
        calendar: Calendar = .current
    ) -> Bool {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = normalizedHour(hour)
        components.minute = normalizedMinute(minute)
        components.second = 0
        guard let todayFireDate = calendar.date(from: components), now >= todayFireDate else {
            return false
        }
        guard let lastDeliveredAt else { return true }
        return !calendar.isDate(lastDeliveredAt, inSameDayAs: now)
    }

    static func normalizedHour(_ hour: Int) -> Int { min(max(hour, 0), 23) }
    static func normalizedMinute(_ minute: Int) -> Int { min(max(minute, 0), 59) }
}
