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
    ///   - until: 기간 조회의 끝 날짜. 빈 문자열이면 `date` 하루만 본다.
    ///   - after: 빈 문자열이면 시각으로 거르지 않는다. 시각이 없는 항목은 시간 조건에 걸리지 않는다.
    static func lookup(
        _ entries: [Entry],
        date: String,
        until: String = "",
        after: String,
        nextOnly: Bool,
        now: Date,
        calendar: Calendar
    ) -> [Entry] {
        let last = until.isEmpty ? date : until
        var result = entries
            // `date...last` 범위는 끝이 앞서면 멈춘다. 판단 검증이 막아 주지만 여기서는 그 전제에 기대지 않는다.
            .filter { (date.isEmpty || (date <= $0.date && $0.date <= last)) && (after.isEmpty || $0.time >= after) }
            .sorted { ($0.date, $0.time, $0.memo.title) < ($1.date, $1.time, $1.memo.title) }
        if nextOnly {
            // 시각 필터는 모델이 아니라 코드가 적용한다. 모델에게는 after 를 비우라고 지시했다.
            let nowKey = day(now, calendar) + "T" + clock(now, calendar)
            result = Array(result.filter { $0.date + "T" + $0.time >= nowKey }.prefix(1))
        }
        return result
    }

    /// 옮길 대상. 평가기처럼 모델이 준 제목이 할 일 제목에 들어 있으면 후보로 본다.
    /// 하나일 때만 옮기고, 없거나 여럿이면 바꾸지 않고 사용자에게 되묻게 한다.
    static func moveTargets(_ entries: [Entry], title: String) -> [Entry] {
        let keyword = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return [] }
        return entries.filter { $0.memo.title.contains(keyword) && !$0.memo.isCompleted }
    }

    /// 옮긴 뒤의 때. 새 시각을 말하지 않았으면 **원래 시각과 길이를 그대로** 두고 날짜만 바꾼다
    /// (평가기 `schedule_move`: after 가 비면 time 을 유지. 성취 화면의 `moveMemo` 와 같은 규칙).
    /// 새 시각을 말했으면 시작을 그 시각으로 두고 시작~마감 길이를 지킨다.
    static func movedDates(
        _ entry: Entry,
        date: String,
        after: String,
        calendar: Calendar
    ) -> (startDate: Date?, deadline: Date?)? {
        guard let newDay = saveDates(date: date, after: "", calendar: calendar)?.startDate else { return nil }
        let memo = entry.memo
        if !after.isEmpty {
            guard let start = saveDates(date: date, after: after, calendar: calendar)?.startDate else { return nil }
            let length = memo.startDate.flatMap { begin in memo.deadline.map { max(0, $0.timeIntervalSince(begin)) } } ?? 0
            return (start, memo.deadline == nil ? nil : start.addingTimeInterval(length))
        }
        func sameClock(_ source: Date?) -> Date? {
            source.flatMap {
                let parts = calendar.dateComponents([.hour, .minute], from: $0)
                return calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: newDay)
            }
        }
        let start = sameClock(memo.startDate) ?? (memo.deadline == nil ? newDay : nil)
        var deadline = sameClock(memo.deadline)
        // 마감이 시작보다 앞서면 그날 끝으로 민다(`moveMemo` 와 같다).
        if let begin = start, let end = deadline, end < begin {
            deadline = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: newDay)
        }
        return (start, deadline)
    }

    /// 코드 안전망. 프롬프트(연도 규칙·날짜표)로 줄였지만 보장하지 못하는 날짜 실수를 저장 전에 잡는다.
    ///
    /// 날짜를 코드가 **고치지는 않는다.** 사용자가 무엇을 원했는지 모르므로 저장하지 않고 되묻는다.
    enum DateIssue: Equatable {
        /// 추가·옮기기 날짜가 오늘보다 앞이다. 예: "10월 2일"이 2024-10-02 로 나온 경우.
        case past(date: String)
        /// 사용자가 말한 요일과 날짜의 요일이 다르다.
        case weekdayMismatch(date: String, said: String, actual: String)
    }

    static let weekdayNames = ["일요일", "월요일", "화요일", "수요일", "목요일", "금요일", "토요일"]

    static func dateIssue(
        date: String,
        isWrite: Bool,
        message: String,
        now: Date,
        calendar: Calendar
    ) -> DateIssue? {
        guard let day = saveDates(date: date, after: "", calendar: calendar)?.startDate else { return nil }
        if isWrite, date < self.day(now, calendar) {
            return .past(date: date)
        }
        // 요일을 하나만 말했을 때만 본다. "월요일에서 수요일로"처럼 둘 이상이면 어느 쪽인지 모른다.
        let said = weekdayNames.filter { message.contains($0) }
        let actual = weekdayNames[calendar.component(.weekday, from: day) - 1]
        if said.count == 1, let only = said.first, only != actual {
            return .weekdayMismatch(date: date, said: only, actual: actual)
        }
        return nil
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
