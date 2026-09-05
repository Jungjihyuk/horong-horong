import Foundation

/// 빠른 입력 한 줄을 «제목 + 일정» 으로 나눈다.
///
/// 문법은 맨 앞 접두어 두 개뿐이다 — `[내일|모레] [n분|n시간] 제목`.
/// 접두어가 없으면 예전과 같이 **오늘 오전 9시**로 들어간다.
///
/// **`now` 를 주입받는다.** 자정·월말 경계에서 «내일» 이 어디로 가는지 검사할 수 있어야
/// 하기 때문이다(CLAUDE.md R9). 저장소가 `Date()` 를 직접 읽던 자리를 여기로 옮겼다 —
/// 「어느 날 몇 시로 잡을지」는 저장 기술이 아니라 도메인 규칙이다.
enum TodoComposerPolicy {
    /// 해석 결과. 저장소는 이 값을 그대로 받아 적는다.
    struct Entry: Equatable, Sendable {
        let title: String
        let startDate: Date
        /// `n분`·`n시간` 을 적었을 때만 있다. 시작에 소요 시간을 더한 값이다.
        let deadline: Date?
    }

    /// 접두어가 시각을 정하지 않으므로 하루의 시작을 여기로 잡는다.
    static let defaultHour = 9

    static func parse(_ text: String, now: Date, calendar: Calendar = .current) -> Entry {
        var rest = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var dayOffset = 0
        var minutes: Int?

        if let keyword = leadingDayKeyword(of: rest), let tail = tail(of: rest, after: keyword.token) {
            dayOffset = keyword.dayOffset
            rest = tail
        }
        if let duration = leadingDuration(of: rest), let tail = tail(of: rest, after: duration.token) {
            minutes = duration.minutes
            rest = tail
        }

        let day = calendar.date(byAdding: .day, value: dayOffset, to: now) ?? now
        let start = calendar.date(bySettingHour: defaultHour, minute: 0, second: 0, of: day) ?? day
        return Entry(
            title: rest,
            startDate: start,
            deadline: minutes.map { start.addingTimeInterval(TimeInterval($0 * 60)) }
        )
    }

    /// 맨 앞 낱말이 날짜를 가리키는지. 오늘로부터 며칠 뒤인지를 함께 돌려준다.
    private static func leadingDayKeyword(of text: String) -> (token: String, dayOffset: Int)? {
        if text.hasPrefix("내일") { return ("내일", 1) }
        if text.hasPrefix("모레") { return ("모레", 2) }
        return nil
    }

    /// 맨 앞 낱말이 `n분`·`n시간` 인지 본다.
    ///
    /// 자릿수를 제한하는 이유: 여섯 자리를 넘는 수는 `× 60` 에서 넘칠 수 있고,
    /// 그런 숫자를 적은 사람은 소요 시간이 아니라 제목을 적은 것이다.
    private static func leadingDuration(of text: String) -> (token: String, minutes: Int)? {
        let token = text.prefix { !$0.isWhitespace }
        let digits = token.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.count <= 6, let amount = Int(digits), amount > 0 else { return nil }

        switch String(token.dropFirst(digits.count)) {
        case "분": return (String(token), amount)
        case "시간": return (String(token), amount * 60)
        default: return nil
        }
    }

    /// 접두어 뒤에 **띄어쓰기와 제목이 모두** 있어야 접두어로 인정한다.
    ///
    /// 「내일」 한 낱말만 적은 사람은 이름 없는 할 일이 아니라 「내일」이라는 제목을 원한 것이다.
    /// 「내일부터 장보기」처럼 낱말 중간에 걸리는 것도 이 규칙이 막는다.
    private static func tail(of text: String, after prefix: String) -> String? {
        let remainder = text.dropFirst(prefix.count)
        guard let first = remainder.first, first.isWhitespace else { return nil }
        let trimmed = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
