import Foundation

/// 하루 안에서 감정을 적는 칸.
///
/// **셋 다 선택이고 순서 강제도 없다.** 하나만 적어도, 둘만 적어도, 아예 안 적어도 된다.
/// 하루에 한 칸뿐이던 시절에는 «오전엔 기뻤고 오후엔 화났는데 뭘 골라야 하지» 에서 막혀
/// 아무것도 안 적게 됐다.
enum DiaryMoodSlot: String, CaseIterable, Identifiable, Sendable {
    case morning
    case afternoon
    case wholeDay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning: return "오전"
        case .afternoon: return "오후"
        case .wholeDay: return "하루"
        }
    }

    /// 타임라인 x축에서 이 칸이 놓이는 시각.
    ///
    /// 실제로 그때 적었다는 뜻이 아니라 **같은 날의 세 칸을 시간 순으로 늘어놓기 위한 기준점**이다.
    /// 셋을 같은 좌표에 두면 점이 겹쳐 오전과 오후를 구분할 수 없다.
    var anchorHour: Int {
        switch self {
        case .morning: return 9
        case .afternoon: return 18
        case .wholeDay: return 12
        }
    }

    /// 이 칸이 속한 흐름. 오전·오후는 하루를 쪼갠 기록이고 «하루» 는 그날 전체의 요약이다.
    var stream: DiaryMoodStream {
        self == .wholeDay ? .wholeDay : .daypart
    }

    func timestamp(on day: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .hour, value: anchorHour, to: start) ?? start
    }
}

/// 감정 기록의 두 흐름.
///
/// **섞어서 잇지 않는다.** 오전·오후·하루를 한 줄로 세우면 «오후 → 하루» 같은 전이가 생기는데,
/// 그건 감정이 바뀐 것이 아니라 같은 날을 두 번 적은 것뿐이다.
enum DiaryMoodStream: String, CaseIterable, Identifiable, Sendable {
    case daypart
    case wholeDay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daypart: return "오전·오후"
        case .wholeDay: return "하루"
        }
    }
}
