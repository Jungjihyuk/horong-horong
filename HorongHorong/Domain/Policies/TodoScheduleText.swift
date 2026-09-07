import Foundation

/// 상세 화면이 날짜를 사람 말로 옮길 때 쓰는 문구.
///
/// **저장하지 않는다.** «오늘» 배지는 자정이 지나면 «어제» 가 되어야 하므로 볼 때마다 계산한다.
/// `now` 를 주입받는 이유도 그래서다 — 자정 경계를 자정까지 기다리지 않고 검사할 수 있어야 한다.
enum TodoScheduleText {
    /// 큰 날짜 줄. «8월 31일 월요일», 해가 다르면 «2027년 1월 3일 일요일».
    static func fullDay(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let style = Date.FormatStyle.dateTime.month(.defaultDigits).day().weekday(.wide)
        return date.formatted(sameYear ? style : style.year())
    }

    /// 칸이 좁을 때 쓰는 짧은 날짜. 요일만 줄인다 — «9. 10. 목요일» → «9. 10. (목)».
    ///
    /// 날짜를 통째로 감추지 않는 이유는, 좁아졌다고 «무슨 날인지» 를 잃으면
    /// 일정 카드가 제 구실을 못 하기 때문이다.
    static func shortDay(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let style = Date.FormatStyle.dateTime.month(.defaultDigits).day().weekday(.abbreviated)
        return date.formatted(sameYear ? style : style.year())
    }

    /// 날짜 옆 배지. 가까운 날에만 붙고 그 밖에는 붙이지 않는다.
    static func relativeBadge(_ date: Date, now: Date, calendar: Calendar = .current) -> String? {
        switch calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: date)
        ).day {
        case 0: return "오늘"
        case 1: return "내일"
        case 2: return "모레"
        case -1: return "어제"
        case .some(let days) where days < 0: return "\(-days)일 지남"
        default: return nil
        }
    }

    /// 미리알림 카드 아래 안내. «"업무" 목록에 8월 31일 월요일로 올라갑니다».
    static func reminderDestination(
        listTitle: String,
        date: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        guard let date else { return "“\(listTitle)” 목록에 날짜 없이 올라갑니다" }
        return "“\(listTitle)” 목록에 \(fullDay(date, now: now, calendar: calendar))로 올라갑니다"
    }

    /// 7일 띠의 한 칸 이름. 앞 이틀만 «오늘»·«내일» 로 부르고 나머지는 요일로 부른다.
    static func stripDayName(
        offset: Int,
        date: Date,
        calendar: Calendar = .current
    ) -> String {
        switch offset {
        case 0: return "오늘"
        case 1: return "내일"
        default:
            let index = calendar.component(.weekday, from: date) - 1
            return calendar.shortWeekdaySymbols[index]
        }
    }
}
