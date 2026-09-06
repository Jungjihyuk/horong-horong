import Foundation

/// 상세 화면의 날짜 빠른 선택(«오늘»·«내일»·«주말»·«다음 주»·«언젠가»).
///
/// **저장하지 않는다.** «주말» 이 며칠 뒤인지는 오늘이 무슨 요일이냐에 달렸고 자정이 지나면 달라진다.
/// `now` 를 주입받는 이유도 그래서다 — 요일마다 달라지는 계산을 요일을 기다리지 않고 검사할 수 있어야 한다.
enum TodoQuickSchedule: String, CaseIterable, Identifiable {
    case today
    case tomorrow
    case weekend
    case nextWeek
    case someday

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "오늘"
        case .tomorrow: return "내일"
        case .weekend: return "주말"
        case .nextWeek: return "다음 주"
        case .someday: return "언젠가"
        }
    }

    /// 오늘로부터 며칠 뒤인지. «언젠가» 는 날짜를 지우는 것이라 갈 곳이 없다.
    func dayOffset(now: Date, calendar: Calendar = .current) -> Int? {
        switch self {
        case .today: return 0
        case .tomorrow: return 1
        case .weekend: return Self.offsetToWeekend(now: now, calendar: calendar)
        case .nextWeek: return Self.offsetToNextWeek(now: now, calendar: calendar)
        case .someday: return nil
        }
    }

    /// 다가오는 토요일. 이미 주말(토·일)이면 오늘을 가리킨다 —
    /// 토요일에 «주말» 을 눌렀는데 엿새 뒤로 밀리면 누른 사람의 뜻과 다르다.
    private static func offsetToWeekend(now: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: now)
        let saturday = 7
        let sunday = 1
        if weekday == saturday || weekday == sunday { return 0 }
        return saturday - weekday
    }

    /// 다음 주 월요일.
    ///
    /// «내일이 월요일이면 그게 다음 주» 로 세지 않는다 — 일요일에 눌렀을 때 하루 뒤로 가면
    /// 지역에 따라 아직 **이번** 주다. 그래서 요일이 아니라 주 단위로 넘긴 뒤 월요일을 찾는다.
    private static func offsetToNextWeek(now: Date, calendar: Calendar) -> Int {
        let fallback = 7
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now),
              let nextWeekStart = calendar.date(byAdding: .day, value: 7, to: thisWeek.start)
        else { return fallback }

        let monday = 2
        let toMonday = (monday - calendar.component(.weekday, from: nextWeekStart) + 7) % 7
        guard let target = calendar.date(byAdding: .day, value: toMonday, to: nextWeekStart),
              let offset = calendar.dateComponents(
                  [.day],
                  from: calendar.startOfDay(for: now),
                  to: calendar.startOfDay(for: target)
              ).day
        else { return fallback }
        return offset
    }
}
