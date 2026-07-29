import Foundation

/// 브리핑에 쓰이는 일정 한 건. SwiftData 모델과 분리해 두어 로직만 따로 테스트한다.
struct CompanionBriefingItem: Hashable, Sendable {
    let title: String
    let isCompleted: Bool
    let startDate: Date?
    let deadline: Date?
}

enum CompanionBriefingComposer {
    /// 오늘 시작하거나 오늘 마감인 항목만 고른다. 마감이 이른 순으로 정렬한다.
    static func todayItems(
        from items: [CompanionBriefingItem],
        now: Date,
        calendar: Calendar = .current,
        includingCompleted: Bool = false
    ) -> [CompanionBriefingItem] {
        items
            .filter { item in
                guard includingCompleted || !item.isCompleted else { return false }
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
}

/// 모델에게 넘길 "오늘 할일" 요약문.
///
/// 온디바이스 모델은 도구 호출을 안정적으로 하지 못한다(지시문이 조금만 길어져도 호출률이 0에 가까워진다).
/// 그래서 모델의 판단에 맡기지 않고 이 요약문을 프롬프트에 직접 끼워 넣는다.
/// 여기 없는 내용은 모델이 지어낸 것이므로, 문구는 사실만 담고 인용하기 어려운 형태로 둔다.
enum CompanionTaskDigest {
    /// 프롬프트에 넣을 항목 수 상한. 컨텍스트가 짧아 넉넉히 두지 않는다.
    static let maxItemCount = 6

    static func format(
        items: [CompanionBriefingItem],
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        let todays = CompanionBriefingComposer.todayItems(
            from: items,
            now: now,
            calendar: calendar,
            includingCompleted: true
        )
        guard !todays.isEmpty else {
            return "오늘 등록된 할일: 없음"
        }

        var lines = todays.prefix(maxItemCount).map { item -> String in
            var line = "- \(item.title)"
            if let deadline = item.deadline, calendar.isDate(deadline, inSameDayAs: now) {
                line += " (\(timeFormatter.string(from: deadline)) 마감)"
            }
            if item.isCompleted {
                line += " (완료됨)"
            }
            return line
        }
        let remaining = todays.count - lines.count
        if remaining > 0 {
            lines.append("- 외 \(remaining)개")
        }

        return "오늘 등록된 할일:\n" + lines.joined(separator: "\n")
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "a h:mm"
        return formatter
    }()
}

/// 대화창에 타임라인으로 그릴 일정 한 줄.
/// 모델이 만든 문장이 아니라 저장된 데이터를 그대로 쓴다.
struct CompanionScheduleEntry: Identifiable, Hashable, Sendable {
    let id = UUID()
    let time: Date?
    let title: String
    let isCompleted: Bool

    private enum CodingKeys: String, CodingKey {
        case time, title, isCompleted
    }
}

/// 브리핑 말풍선 위에 붙는 한 줄 요약.
enum CompanionBriefingSummary {
    static func headline(for entries: [CompanionScheduleEntry]) -> String {
        guard !entries.isEmpty else { return "오늘 일정 없음" }
        let remaining = entries.filter { !$0.isCompleted }.count
        if remaining == 0 {
            return "오늘 할 일 \(entries.count)개 · 모두 완료"
        }
        return "오늘 할 일 \(entries.count)개 · \(remaining)개 남음"
    }
}

enum CompanionScheduleBuilder {
    /// 오늘 항목을 시각 순으로 정렬한다. 시각이 없는 항목은 뒤로 보낸다.
    static func entries(
        from items: [CompanionBriefingItem],
        now: Date,
        calendar: Calendar = .current
    ) -> [CompanionScheduleEntry] {
        CompanionBriefingComposer
            .todayItems(from: items, now: now, calendar: calendar, includingCompleted: true)
            .map { item in
                // 시각은 마감에서만 가져온다. startDate 는 "오늘 할일로 담은 시각"이라
                // 일정 시각으로 쓰면 생성 시각이 타임라인에 그대로 노출된다.
                let isToday = item.deadline.map { calendar.isDate($0, inSameDayAs: now) } ?? false
                return CompanionScheduleEntry(
                    time: isToday ? item.deadline : nil,
                    title: item.title,
                    isCompleted: item.isCompleted
                )
            }
            .sorted { lhs, rhs in
                switch (lhs.time, rhs.time) {
                case let (l?, r?): return l < r
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return lhs.title < rhs.title
                }
            }
    }
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
        return calendar.date(byAdding: .day, value: 1, to: todayFireDate)
            ?? todayFireDate.addingTimeInterval(86_400)
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
