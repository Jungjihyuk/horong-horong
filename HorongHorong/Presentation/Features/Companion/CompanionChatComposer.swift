import Foundation

/// 사용자의 말이 오늘 할일·일정에 관한 것인지 판정한다.
///
/// 모델이 도구를 부를지 스스로 정하게 두면 호출률이 들쭉날쭉하므로,
/// 여기서 코드로 판정해 필요할 때만 할일 목록을 프롬프트에 끼워 넣는다.
enum CompanionTaskQuestion {
    private static let keywords = [
        "할일", "할 일", "일정", "스케줄", "계획", "태스크", "todo", "to-do",
        "뭐 해야", "뭐해야", "뭐부터", "무엇을 해야", "남은 거", "남은거",
    ]

    static func matches(_ message: String) -> Bool {
        let normalized = message.lowercased()
        // "내일 일정 추가해줘" 는 묻는 말이 아니라 시키는 말이다.
        // 저장 지시로 읽히지 못한 말투라도 오늘 일정 목록까지 들이밀지는 않게 막는다.
        guard !CompanionMemoIntent.soundsLikeSaveRequest(message) else { return false }
        return keywords.contains { normalized.contains($0) }
    }
}

/// 모델 응답 다듬기.
///
/// 프롬프트로 "목록·굵은 글씨 쓰지 마"라고 해도 작은 모델은 자주 어긴다.
/// 지시로 싸우는 대신 결과에서 마크다운 기호만 걷어낸다.
enum CompanionReplyFormatter {
    static func clean(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "**", with: "")
        result = result.replacingOccurrences(of: "__", with: "")

        let lines = result
            .components(separatedBy: .newlines)
            .map { stripBullet($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }

        // 줄바꿈은 살린다. 공백으로 이어 붙이면 시각·항목이 뭉개져 읽을 수 없다.
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 줄 앞의 `- `, `* `, `1. ` 같은 목록 기호를 뗀다.
    private static func stripBullet(_ line: String) -> String {
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        // "1. " / "12. " 형태
        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty {
            let rest = line.dropFirst(digits.count)
            if rest.hasPrefix(". ") {
                return String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
        }
        return line
    }
}

/// 사용자가 모델에게 답을 요구한 것이 아니라 메모 저장을 지시했는지 코드로 판정한다.
///
/// `.text` 에 담기는 값은 모델이 만든 요약이 아니라 사용자의 입력에서 저장 지시만
/// 떼어낸 원문이다. 지시만 말한 경우에는 직전 대화 말풍선을 저장한다.
struct CompanionMemoIntent: Equatable {
    enum Target: Equatable {
        case previousMessage
        case text(String)
    }

    let target: Target

    /// 어디에 담을지(대상) + 어떻게 담을지(동사) + 맺음말 조합으로 지시 말투를 만든다.
    /// 말투마다 문장을 손으로 적으면 "메모에 추가해줘" 같은 조합이 늘 빠진다.
    private static let targets = ["메모에", "메모로", "메모", "일정에", "일정으로", "일정", "할 일에", "할일에"]
    private static let transfers = ["남겨", "추가해", "저장해", "등록해", "넣어"]
    /// 대상을 말하지 않아도 뜻이 분명한 동사.
    private static let standaloneVerbs = ["메모해", "기록해", "적어"]
    private static let endings = ["줘", " 줘", "주세요", " 주세요", "둬", " 둬", "두세요", " 두세요"]

    private static let phrases: [String] = {
        var phrases = standaloneVerbs.flatMap { verb in
            endings.map { "\(verb)\($0)" }
        }
        for target in targets {
            for transfer in transfers {
                phrases.append(contentsOf: endings.map { "\(target) \(transfer)\($0)" })
            }
        }
        return phrases.sorted { $0.count > $1.count }
    }()

    /// 대상 없이 "추가해줘" 처럼 남겨 달라는 말투인지 본다.
    /// 저장 지시로 확정할 만큼은 아니지만 일정 질문으로 오해하면 안 되는 자리에 쓴다.
    static func soundsLikeSaveRequest(_ message: String) -> Bool {
        let verbs = standaloneVerbs + transfers
        return verbs.contains { verb in
            endings.contains { message.contains("\(verb)\($0)") }
        }
    }

    private static let previousMessageReferences = [
        "이거", "그거", "이 내용", "그 내용", "이 말", "그 말",
        "이 답변", "그 답변", "방금 말한 거", "방금 말한 내용", "방금 답변",
    ]

    static func parse(_ message: String) -> CompanionMemoIntent? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let command = commandRange(in: trimmed) else { return nil }

        // 지시 앞뒤에 남은 말이 곧 메모 내용이다. "…메모로 남겨줘. 14시 30분으로" 처럼
        // 지시 뒤에 시각을 덧붙이는 말투가 흔해서 양쪽을 모두 살린다.
        let before = String(trimmed[..<command.lowerBound])
            .trimmingCharacters(in: contentBoundaryCharacters)
        let after = trimmingLeadingMarks(String(trimmed[command.upperBound...]))
            .trimmingCharacters(in: contentBoundaryCharacters)
        let content = [before, after]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        // 지시만 말했거나("메모해 줘!") 앞 대화를 가리키면 직전 말풍선을 저장한다.
        guard content.contains(where: { $0.isLetter || $0.isNumber }),
              !isPreviousMessageReference(content)
        else {
            return CompanionMemoIntent(target: .previousMessage)
        }
        return CompanionMemoIntent(target: .text(content))
    }

    /// 문장 어디에 있든 저장 지시를 찾는다.
    /// 앞뒤가 말 경계여야 "메모해줘서 고마워" 같은 말을 지시로 잘못 읽지 않는다.
    private static func commandRange(in text: String) -> Range<String.Index>? {
        for phrase in phrases {
            var searchStart = text.startIndex
            while let range = text.range(of: phrase, range: searchStart..<text.endIndex) {
                let startsCleanly = range.lowerBound == text.startIndex
                    || isCommandBoundary(text[text.index(before: range.lowerBound)])
                let endsCleanly = range.upperBound == text.endIndex
                    || isCommandBoundary(text[range.upperBound])
                if startsCleanly, endsCleanly { return range }
                searchStart = range.upperBound
            }
        }
        return nil
    }

    private static let contentBoundaryCharacters = CharacterSet(charactersIn: " \t\n\r,:，：")
    /// 지시 뒤에 남은 문장 부호. 뒷말을 이어 붙이기 전에 앞에서만 떼어낸다.
    private static let leadingMarkCharacters = CharacterSet(charactersIn: " \t\n\r,:，：.!?…~·、。！？")

    private static func trimmingLeadingMarks(_ text: String) -> String {
        String(text.drop { character in
            character.unicodeScalars.allSatisfy(leadingMarkCharacters.contains)
        })
    }

    private static func isPreviousMessageReference(_ text: String) -> Bool {
        previousMessageReferences.contains(text)
    }

    private static func isCommandBoundary(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy {
            CharacterSet.whitespacesAndNewlines.contains($0)
                || CharacterSet.punctuationCharacters.contains($0)
        }
    }
}

/// 저장 지시 안의 날짜·시각 표현을 읽어 메모의 시작·마감으로 바꾼다.
///
/// - "내일 14시 30분" 처럼 시각이 하나면 시작과 마감을 같게 둔다.
/// - "13:30 ~ 14:30", "2시부터 4시까지" 처럼 구간이면 앞을 시작, 뒤를 마감으로 둔다.
/// - "13시 30분에 3시간" 처럼 길이가 붙으면 시작 + 길이를 마감으로 둔다.
/// - 날짜만 말했으면 그날 할 일로만 올린다.
///
/// 오전·오후를 말하지 않은 1~6시는 **메모를 쓴 시각**을 보고 읽는다.
/// 낮(06:00~18:00)에 썼으면 오후로("3시" → 15:00), 저녁·밤에 썼으면 말한 그대로 둔다.
/// 밤에는 "3시"가 정말 새벽을 가리키는 경우가 많아 함부로 옮기면 조용히 틀어진다.
struct CompanionMemoSchedule: Equatable {
    /// 날짜·시각 표현을 걷어낸 메모 본문.
    let title: String
    let startDate: Date?
    let deadline: Date?

    static func parse(
        _ text: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> CompanionMemoSchedule {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var removals: [Range<String.Index>] = []

        let day = dayToken(in: source)
        if let day { removals.append(day.range) }

        let times = timeTokens(in: source, writtenAt: now, calendar: calendar)
        let durations = durationTokens(in: source, excluding: times.map(\.range))

        var startDate: Date?
        var deadline: Date?

        if times.count >= 2 {
            let start = date(for: times[0], dayOffset: day?.offset, now: now, calendar: calendar)
            startDate = start

            // "2시부터 그 다음날 12시까지" 처럼 끝 시각이 하루 넘어가는 말.
            let connector = times[0].range.upperBound..<times[1].range.lowerBound
            let spansNextDay = nextDayWords.contains { source[connector].contains($0) }
            deadline = endDate(
                for: times[1],
                after: start,
                dayOffset: (day?.offset ?? 0) + (spansNextDay ? 1 : 0),
                now: now,
                calendar: calendar
            )
            removals.append(times[0].range)
            removals.append(times[1].range)
            // "13:30 ~ 14:30" 의 "~" 처럼 두 시각을 잇는 말만 남는 자리도 함께 걷어낸다.
            if spansNextDay || !source[connector].contains(where: { $0.isLetter || $0.isNumber }) {
                removals.append(connector)
            }
        } else if let time = times.first {
            let start = date(for: time, dayOffset: day?.offset, now: now, calendar: calendar)
            startDate = start
            removals.append(time.range)

            if let duration = durations.first(where: { $0.range.lowerBound >= time.range.upperBound }) {
                deadline = calendar.date(byAdding: .minute, value: duration.minutes, to: start)
                removals.append(duration.range)
            } else {
                deadline = start
            }
        } else if let day {
            startDate = calendar.startOfDay(for: shifted(now, by: day.offset, calendar: calendar))
        }

        return CompanionMemoSchedule(
            title: stripping(removals, from: source),
            startDate: startDate,
            deadline: deadline
        )
    }

    /// 저장한 때를 사람이 읽는 한 줄로 만든다. 날짜가 없으면 nil.
    func summary(now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let startDate else { return nil }
        let day = Self.dayLabel(for: startDate, now: now, calendar: calendar)
        guard let deadline else { return day }

        let start = Self.timeLabel(startDate, calendar: calendar)
        guard deadline != startDate else { return "\(day) \(start)" }

        let end = Self.timeLabel(deadline, calendar: calendar)
        guard calendar.isDate(deadline, inSameDayAs: startDate) else {
            let endDay = Self.dayLabel(for: deadline, now: now, calendar: calendar)
            return "\(day) \(start) ~ \(endDay) \(end)"
        }
        return "\(day) \(start) ~ \(end)"
    }

    // MARK: - 날짜 낱말

    private struct DayToken {
        let range: Range<String.Index>
        let offset: Int
    }

    private static let dayWords: [(word: String, offset: Int)] = [
        ("내일모레", 2), ("오늘", 0), ("내일", 1), ("모레", 2), ("글피", 3),
    ]

    /// 구간의 끝이 하루 넘어간다는 표시.
    private static let nextDayWords = ["다음날", "다음 날", "이튿날", "담날", "익일"]

    private static func dayToken(in source: String) -> DayToken? {
        dayWords
            .compactMap { word, offset in
                source.range(of: word).map { DayToken(range: $0, offset: offset) }
            }
            .min { $0.range.lowerBound < $1.range.lowerBound }
    }

    // MARK: - 시각

    private struct TimeToken {
        let range: Range<String.Index>
        let hour: Int
        let minute: Int
        let hasMeridiem: Bool
    }

    /// `시(?!간)` 로 "3시간"의 "3시"를 걸러내고, 뒤에 붙는 조사까지 범위에 넣어
    /// 본문에서 걷어낼 때 "14시 30분으로"의 "으로"가 남지 않게 한다.
    private static let timePattern =
        "(?:(오전|오후|아침|점심|저녁|밤|새벽)\\s*)?(\\d{1,2})\\s*"
        + "(?::(\\d{2})|시(?!간)(?:\\s*(\\d{1,2})\\s*분|\\s*(반))?)"
        + "(?:\\s*(?:부터|에서|까지|쯤|경|으로|로|에))?"

    private static func timeTokens(
        in source: String,
        writtenAt now: Date,
        calendar: Calendar
    ) -> [TimeToken] {
        matches(of: timePattern, in: source).compactMap { match, range in
            let meridiem = capture(match, 1, in: source)
            guard let rawHour = capture(match, 2, in: source).flatMap(Int.init) else { return nil }

            let minute: Int
            if let colonMinute = capture(match, 3, in: source).flatMap(Int.init) {
                minute = colonMinute
            } else if let spokenMinute = capture(match, 4, in: source).flatMap(Int.init) {
                minute = spokenMinute
            } else if capture(match, 5, in: source) != nil {
                minute = 30
            } else {
                minute = 0
            }

            let hour = adjustedHour(rawHour, meridiem: meridiem, writtenAt: now, calendar: calendar)
            guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
            return TimeToken(range: range, hour: hour, minute: minute, hasMeridiem: meridiem != nil)
        }
    }

    /// 오전·오후를 말하지 않은 1~6시만 쓴 시각을 보고 옮긴다.
    private static let ambiguousHours = 1...6
    /// 이 시간대에 쓴 메모는 1~6시를 오후로 읽는다.
    private static let daytimeHours = 6..<18

    private static func adjustedHour(
        _ hour: Int,
        meridiem: String?,
        writtenAt now: Date,
        calendar: Calendar
    ) -> Int {
        switch meridiem {
        case "오전", "새벽", "아침":
            return hour == 12 ? 0 : hour
        case "밤":
            return hour == 12 ? 0 : (hour < 12 ? hour + 12 : hour)
        case "오후", "점심", "저녁":
            return hour < 12 ? hour + 12 : hour
        default:
            guard ambiguousHours.contains(hour),
                  daytimeHours.contains(calendar.component(.hour, from: now))
            else {
                return hour
            }
            return hour + 12
        }
    }

    // MARK: - 걸리는 시간

    private struct DurationToken {
        let range: Range<String.Index>
        let minutes: Int
    }

    private static let durationPattern =
        "(?:(\\d{1,2})\\s*시간(?:\\s*(\\d{1,2})\\s*분|\\s*(반))?|(\\d{1,3})\\s*분)"
        + "(?:\\s*(?:동안|짜리|정도|간))?"

    /// 시각으로 이미 읽은 자리("14시 30분"의 "30분")는 길이로 다시 읽지 않는다.
    private static func durationTokens(
        in source: String,
        excluding excluded: [Range<String.Index>]
    ) -> [DurationToken] {
        matches(of: durationPattern, in: source).compactMap { match, range in
            guard !excluded.contains(where: { $0.overlaps(range) }) else { return nil }

            var minutes = 0
            if let hours = capture(match, 1, in: source).flatMap(Int.init) {
                minutes += hours * 60
                if let extra = capture(match, 2, in: source).flatMap(Int.init) {
                    minutes += extra
                } else if capture(match, 3, in: source) != nil {
                    minutes += 30
                }
            } else if let bare = capture(match, 4, in: source).flatMap(Int.init) {
                minutes = bare
            }

            guard minutes > 0 else { return nil }
            return DurationToken(range: range, minutes: minutes)
        }
    }

    // MARK: - 날짜 만들기

    private static func date(
        for time: TimeToken,
        dayOffset: Int?,
        now: Date,
        calendar: Calendar
    ) -> Date {
        let base = shifted(now, by: dayOffset ?? 0, calendar: calendar)
        var components = calendar.dateComponents([.year, .month, .day], from: base)
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        return calendar.date(from: components) ?? base
    }

    private static func endDate(
        for time: TimeToken,
        after start: Date,
        dayOffset: Int?,
        now: Date,
        calendar: Calendar
    ) -> Date {
        let end = date(for: time, dayOffset: dayOffset, now: now, calendar: calendar)
        guard end <= start else { return end }

        // "오후 2시부터 4시까지" 처럼 뒤 시각에 오전·오후가 없으면 앞 시각을 따라간다.
        if !time.hasMeridiem,
           time.hour < 12,
           let afternoon = calendar.date(byAdding: .hour, value: 12, to: end),
           afternoon > start {
            return afternoon
        }
        // 자정을 넘긴 구간.
        return calendar.date(byAdding: .day, value: 1, to: end) ?? end
    }

    private static func shifted(_ date: Date, by days: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    private static func dayLabel(for date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: date)
        ).day ?? 0

        switch days {
        case 0: return "오늘"
        case 1: return "내일"
        case 2: return "모레"
        default:
            let components = calendar.dateComponents([.month, .day], from: date)
            return "\(components.month ?? 0)월 \(components.day ?? 0)일"
        }
    }

    private static func timeLabel(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    // MARK: - 본문 다듬기

    /// 읽어낸 표현을 본문에서 걷어낸다. 남는 게 없으면 원문을 그대로 둔다.
    private static func stripping(_ ranges: [Range<String.Index>], from source: String) -> String {
        var kept: [Range<String.Index>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = kept.last, range.lowerBound < last.upperBound { continue }
            kept.append(range)
        }

        var result = source
        for range in kept.reversed() {
            result.removeSubrange(range)
        }

        let cleaned = result
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return cleaned.isEmpty ? source : nounPhrase(from: cleaned)
    }

    /// 말한 문장을 메모 제목처럼 다듬는다. "수진이랑 데이트 일정 있는데" → "수진이랑 데이트"
    ///
    /// 형태소 분석 없이 끝말만 떼어내므로, 남는 말이 두 글자보다 짧아지면 손대지 않는다.
    /// "맛있어" 의 "있어" 처럼 낱말 일부를 자르는 사고를 막는 최소 안전장치다.
    private static let trailingClauses = [
        "하려고 하는데", "하려고 해", "하기로 했는데", "하기로 했어", "하기로 함",
        "가야 하는데", "해야 하는데", "가야 해", "해야 해", "해야 돼", "해야겠어",
        "할 예정이야", "할 예정", "할 건데", "할건데", "갈 건데", "갈건데",
        "잡혀 있는데", "잡혀 있어", "잡혔는데", "잡혔어", "생겼는데", "생겼어",
        "있는데요", "있는데", "있습니다", "있어요", "있어", "있음",
        "하려는데", "하려고", "이라서", "인데",
    ]

    /// 앞말이 남아 있으면 굳이 제목에 둘 필요가 없는 일반 명사.
    private static let trailingNouns = ["일정", "스케줄", "계획"]

    private static let trailingPhrases: [String] = (trailingClauses + trailingNouns)
        .sorted { $0.count > $1.count }

    private static func nounPhrase(from title: String) -> String {
        var result = title
        var trimmedSomething = true

        while trimmedSomething {
            trimmedSomething = false
            for phrase in trailingPhrases where result.hasSuffix(phrase) {
                let remainder = String(result.dropLast(phrase.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard remainder.count >= 2 else { continue }
                result = remainder
                trimmedSomething = true
                break
            }
        }
        return result
    }

    // MARK: - 정규식 도우미

    /// 정규식은 부를 때마다 만든다. 한 문장에 한 번 쓰는 정도라 값이 싸고,
    /// 전역 상수로 두면 Swift 6 동시성 검사에 걸린다.
    private static func matches(
        of pattern: String,
        in source: String
    ) -> [(match: NSTextCheckingResult, range: Range<String.Index>)] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let full = NSRange(source.startIndex..., in: source)
        return expression.matches(in: source, range: full).compactMap { match in
            guard let range = Range(match.range, in: source) else { return nil }
            return (match, range)
        }
    }

    private static func capture(
        _ match: NSTextCheckingResult,
        _ index: Int,
        in source: String
    ) -> String? {
        guard index < match.numberOfRanges,
              let range = Range(match.range(at: index), in: source) else { return nil }
        return String(source[range])
    }
}

struct CompanionMemoSaveRequest {
    let messageID: UUID
    let content: String
    let icon: String
    let isTodayTask: Bool
    var startDate: Date?
    var deadline: Date?
}

enum CompanionMemoSaveResult: Equatable {
    case saved(UUID)
    case duplicate(UUID)
}

/// 한 대화 말풍선에서 메모가 하나만 만들어지도록 저장과 중복 판정을 한곳에서 맡는다.
@MainActor
final class CompanionMemoStore {
    private var memoIDsByMessageID: [UUID: UUID] = [:]

    func save(
        _ request: CompanionMemoSaveRequest,
        in repository: CompanionMemoRepository,
        now: Date = Date()
    ) throws -> CompanionMemoSaveResult {
        // 같은 말풍선에서 두 번 저장하지 않는다. 이 판단이 이 타입의 존재 이유다.
        if let memoID = memoIDsByMessageID[request.messageID] {
            return .duplicate(memoID)
        }

        let memoID = try repository.createMemo(
            content: request.content,
            icon: request.icon,
            // 말로 정해준 때가 있으면 그 값이 우선이다.
            startDate: request.startDate ?? (request.isTodayTask ? now : nil),
            deadline: request.deadline
        )
        memoIDsByMessageID[request.messageID] = memoID
        return .saved(memoID)
    }
}
