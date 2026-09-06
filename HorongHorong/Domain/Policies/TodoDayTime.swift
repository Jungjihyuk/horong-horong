import Foundation

/// 시작 날짜에 붙은 **시각**을 다루는 규칙.
///
/// 날짜가 있으면 시각도 반드시 있다 — «종일» 같은 중간 상태를 두지 않는다.
enum TodoDayTime {
    /// «오전 8:00».
    static func label(_ date: Date, calendar: Calendar = .current) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// 날짜는 그대로 두고 시각만 갈아 끼운다.
    static func applying(hour: Int, minute: Int, to date: Date, calendar: Calendar = .current) -> Date {
        var parts = calendar.dateComponents([.year, .month, .day], from: date)
        parts.hour = hour
        parts.minute = minute
        parts.second = 0
        return calendar.date(from: parts) ?? date
    }
}

/// «시간» 줄에 늘어놓는 흔한 시각들. 하루를 여섯 토막으로 나눈 것이다.
enum TodoTimePreset: String, CaseIterable, Identifiable {
    case morning
    case lateMorning
    case lunch
    case afternoon
    case evening
    case night

    var id: String { rawValue }

    /// 칩 윗줄. 시각 자체보다 «언제쯤인지» 가 먼저 읽히게 한다.
    var title: String {
        switch self {
        case .morning: return "아침"
        case .lateMorning: return "오전"
        case .lunch: return "점심"
        case .afternoon: return "오후"
        case .evening: return "퇴근"
        case .night: return "밤"
        }
    }

    var hour: Int {
        switch self {
        case .morning: return 8
        case .lateMorning: return 10
        case .lunch: return 12
        case .afternoon: return 15
        case .evening: return 18
        case .night: return 21
        }
    }

    var minute: Int { self == .lunch ? 30 : 0 }

    /// 칩 아랫줄. 24시간제 대신 «3시» 처럼 평소 말하는 대로 적는다.
    var valueLabel: String {
        let displayHour = hour > 12 ? hour - 12 : hour
        return minute == 0 ? "\(displayHour)시" : "\(displayHour):\(String(format: "%02d", minute))"
    }
}
