import Foundation

/// 컴패니언의 일정 조회 도구가 어떤 할 일을 돌려줄지 정한다.
///
/// 평가기의 가짜 저장소(`Evals/companion_eval.py` `FakeTools.execute`)와 같은 규칙이다 —
/// 날짜가 같고, 시간 조건 이후이며, 날짜·시각 순. "바로 다음 것만"이면 지금 이후의 첫 항목 하나.
/// 평가는 이 규칙을 전제로 모델을 골랐으므로 앱이 다르게 고르면 평가 결과를 옮겨 쓸 수 없다.
///
/// 일정의 날짜·시각은 **마감**에서 가져온다. `startDate` 는 "오늘 할 일로 담은 시각"이라 시각으로 쓰면
/// 담은 시각이 일정처럼 보인다(→ `CompanionScheduleBuilder`). 마감이 없으면 담은 날짜만 쓰고 시각은 비운다.
enum CompanionScheduleLookupPolicy {
    struct Entry: Equatable, Sendable {
        let memo: CompanionMemoSummary
        /// `YYYY-MM-DD`
        let date: String
        /// `HH:MM`, 시각이 없으면 빈 문자열
        let time: String
    }

    static func entries(from memos: [CompanionMemoSummary], calendar: Calendar) -> [Entry] {
        memos.compactMap { memo in
            if let deadline = memo.deadline {
                return Entry(memo: memo, date: day(deadline, calendar), time: clock(deadline, calendar))
            }
            if let startDate = memo.startDate {
                return Entry(memo: memo, date: day(startDate, calendar), time: "")
            }
            return nil
        }
    }

    /// - Parameters:
    ///   - date: 빈 문자열이면 날짜로 거르지 않는다.
    ///   - after: 빈 문자열이면 시각으로 거르지 않는다. 시각이 없는 항목은 시간 조건에 걸리지 않는다.
    static func lookup(
        _ entries: [Entry],
        date: String,
        after: String,
        nextOnly: Bool,
        now: Date,
        calendar: Calendar
    ) -> [Entry] {
        var result = entries
            .filter { (date.isEmpty || $0.date == date) && (after.isEmpty || $0.time >= after) }
            .sorted { ($0.date, $0.time, $0.memo.title) < ($1.date, $1.time, $1.memo.title) }
        if nextOnly {
            // 시각 필터는 모델이 아니라 코드가 적용한다. 모델에게는 after 를 비우라고 지시했다.
            let nowKey = day(now, calendar) + "T" + clock(now, calendar)
            result = Array(result.filter { $0.date + "T" + $0.time >= nowKey }.prefix(1))
        }
        return result
    }

    /// 판단 값(`YYYY-MM-DD` + 선택 `HH:MM`)을 저장할 때를 만든다. 채팅 저장(`CompanionMemoSchedule`)과 같은 규칙이다 —
    /// 시각이 있으면 시작·마감을 그 시각으로, 날짜만 있으면 그날 0시를 시작으로 두고 마감은 비운다.
    static func saveDates(date: String, after: String, calendar: Calendar) -> (startDate: Date, deadline: Date?)? {
        let dayParts = date.split(separator: "-").compactMap { Int($0) }
        guard dayParts.count == 3 else { return nil }
        var components = DateComponents(year: dayParts[0], month: dayParts[1], day: dayParts[2])
        guard !after.isEmpty else {
            return calendar.date(from: components).map { ($0, nil) }
        }
        let timeParts = after.split(separator: ":").compactMap { Int($0) }
        guard timeParts.count == 2 else { return nil }
        components.hour = timeParts[0]
        components.minute = timeParts[1]
        return calendar.date(from: components).map { ($0, $0) }
    }

    static func day(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func clock(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
