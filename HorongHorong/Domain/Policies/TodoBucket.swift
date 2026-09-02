import Foundation

/// 할 일이 어느 묶음(지남·오늘·예정·언젠가·완료)에 들어가는지 정한다.
///
/// **저장하지 않는다.** 자정이 지나면 «오늘» 이 «지남» 이 되어야 하므로 조회 시점에 계산한다.
/// `now` 를 주입받는 이유도 그래서다 — 자정·월말 경계를 테스트할 수 있어야 한다.
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
