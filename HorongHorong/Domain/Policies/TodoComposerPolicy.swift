import Foundation

/// 빠른 입력 한 줄을 «제목 + 일정» 으로 나눈다.
///
/// 문법 지원:
/// - 날짜: `오늘`, `내일`, `모레`, `글피`, `[이번주|다음주]? [월~일]요일`
/// - 시간 범위: `9시 30분 ~ 10시`, `9:30~10:00`, `9시 반 ~ 10시`, `9시부터 9시 반까지`
/// - 시작 시각 + 소요: `9시 시작 30분간`, `9시 30분간`, `오후 2시 1시간`
/// - 특정 시각만: `9시 30분`, `14:00`, `오후 3시`
/// - 소요 시간만: `30분간`, `1시간 동안`, `90분` (기본 시작시각 오전 9시)
///
/// **`now` 를 주입받는다.** 자정·월말 경계에서 «내일» 이 어디로 가는지 검사할 수 있어야
/// 하기 때문이다(CLAUDE.md R9).
enum TodoComposerPolicy {
    /// 해석 결과. 저장소는 이 값을 그대로 받아 적는다.
    struct Entry: Equatable, Sendable {
        let title: String
        let startDate: Date
        let deadline: Date?
        /// 명시적인 날짜/시간 접두어가 입력에서 파싱되었는지 여부.
        let hasExplicitSchedule: Bool
        /// UI 뱃지 칩에 표시할 요약 문자열 (예: "내일 09:30 ~ 10:00", "내일 09:00 (30분)").
        let scheduleSummary: String?
    }

    /// 접두어가 시각을 정하지 않을 때 하루의 시작 시각 (오전 9시).
    static let defaultHour = 9

    static func parse(_ text: String, now: Date, calendar: Calendar = .current) -> Entry {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            let defaultStart = calendar.date(bySettingHour: defaultHour, minute: 0, second: 0, of: now) ?? now
            return Entry(title: "", startDate: defaultStart, deadline: nil, hasExplicitSchedule: false, scheduleSummary: nil)
        }

        var rest = raw
        var parsedDayDate: Date?
        var parsedDayLabel: String?
        var hasExplicitDay = false

        // 1. 날짜 접두어 검사 (내일, 모레, 글피, 오늘, 요일)
        if let dayMatch = matchDay(in: rest, now: now, calendar: calendar) {
            let afterDay = rest.dropFirst(dayMatch.tokenLength)
            if afterDay.first?.isWhitespace == true {
                parsedDayDate = dayMatch.date
                parsedDayLabel = dayMatch.label
                hasExplicitDay = true
                rest = afterDay.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // 2. 시간 / 소요시간 접두어 검사
        var parsedStartHour: Int?
        var parsedStartMinute: Int?
        var parsedEndHour: Int?
        var parsedEndMinute: Int?
        var parsedDurationMinutes: Int?
        var hasExplicitTime = false

        if let timeMatch = matchTimeOrDuration(in: rest) {
            let matchedSubstring = rest.prefix(timeMatch.tokenLength)
            let afterTime = rest.dropFirst(timeMatch.tokenLength)
            let hasBoundary = matchedSubstring.last?.isWhitespace == true || afterTime.first?.isWhitespace == true
            if hasBoundary {
                parsedStartHour = timeMatch.startHour
                parsedStartMinute = timeMatch.startMinute
                parsedEndHour = timeMatch.endHour
                parsedEndMinute = timeMatch.endMinute
                parsedDurationMinutes = timeMatch.durationMinutes
                hasExplicitTime = true
                rest = afterTime.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // 3. 제목 유효성 검사: 접두어를 떼고 남은 텍스트가 있어야 접두어로 인정
        let finalTitle = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        if finalTitle.isEmpty {
            let defaultStart = calendar.date(bySettingHour: defaultHour, minute: 0, second: 0, of: now) ?? now
            return Entry(title: raw, startDate: defaultStart, deadline: nil, hasExplicitSchedule: false, scheduleSummary: nil)
        }

        let hasExplicitSchedule = hasExplicitDay || hasExplicitTime
        guard hasExplicitSchedule else {
            let defaultStart = calendar.date(bySettingHour: defaultHour, minute: 0, second: 0, of: now) ?? now
            return Entry(title: finalTitle, startDate: defaultStart, deadline: nil, hasExplicitSchedule: false, scheduleSummary: nil)
        }

        // 4. 날짜 및 시간 조립
        let baseDay = parsedDayDate ?? now
        let startHour = parsedStartHour ?? defaultHour
        let startMinute = parsedStartMinute ?? 0

        let start = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: baseDay) ?? baseDay

        var deadline: Date?
        if let endHour = parsedEndHour, let endMinute = parsedEndMinute {
            var end = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: baseDay) ?? baseDay
            if end <= start {
                end = calendar.date(byAdding: .day, value: 1, to: end) ?? end
            }
            deadline = end
        } else if let duration = parsedDurationMinutes {
            deadline = start.addingTimeInterval(TimeInterval(duration * 60))
        }

        // 5. scheduleSummary 생성
        let summary = formatScheduleSummary(
            dayLabel: parsedDayLabel ?? (hasExplicitTime ? "오늘" : nil),
            startHour: parsedStartHour,
            startMinute: parsedStartMinute,
            endHour: parsedEndHour,
            endMinute: parsedEndMinute,
            durationMinutes: parsedDurationMinutes
        )

        return Entry(
            title: finalTitle,
            startDate: start,
            deadline: deadline,
            hasExplicitSchedule: true,
            scheduleSummary: summary
        )
    }

    // MARK: - 날짜 파싱

    private struct DayMatch {
        let tokenLength: Int
        let label: String
        let date: Date
    }

    private static func matchDay(in text: String, now: Date, calendar: Calendar) -> DayMatch? {
        if text.hasPrefix("오늘") {
            return DayMatch(tokenLength: 2, label: "오늘", date: now)
        }
        if text.hasPrefix("내일") {
            let d = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return DayMatch(tokenLength: 2, label: "내일", date: d)
        }
        if text.hasPrefix("모레") {
            let d = calendar.date(byAdding: .day, value: 2, to: now) ?? now
            return DayMatch(tokenLength: 2, label: "모레", date: d)
        }
        if text.hasPrefix("글피") {
            let d = calendar.date(byAdding: .day, value: 3, to: now) ?? now
            return DayMatch(tokenLength: 2, label: "글피", date: d)
        }

        // 요일 파싱: (이번주|다음주)?\s*([월화수목금토일])요일
        if let match = weekdayRegex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) {
            if match.range.location == 0 {
                let matchedString = (text as NSString).substring(with: match.range)
                let prefixRange = match.range(at: 1)
                let weekdayRange = match.range(at: 2)

                let isNextWeek = prefixRange.location != NSNotFound && (text as NSString).substring(with: prefixRange) == "다음주"
                let weekdayChar = (text as NSString).substring(with: weekdayRange)

                let weekdayMap: [String: Int] = ["일": 1, "월": 2, "화": 3, "수": 4, "목": 5, "금": 6, "토": 7]
                if let targetWeekday = weekdayMap[weekdayChar] {
                    let currentWeekday = calendar.component(.weekday, from: now)
                    var dayDiff = targetWeekday - currentWeekday
                    if isNextWeek {
                        dayDiff += 7
                    } else if dayDiff <= 0 {
                        dayDiff += 7
                    }
                    let targetDate = calendar.date(byAdding: .day, value: dayDiff, to: now) ?? now
                    let label = isNextWeek ? "다음주 \(weekdayChar)요일" : "\(weekdayChar)요일"
                    return DayMatch(tokenLength: matchedString.count, label: label, date: targetDate)
                }
            }
        }

        return nil
    }

    // MARK: - 시간 및 소요시간 파싱

    private struct TimeMatch {
        let tokenLength: Int
        let startHour: Int?
        let startMinute: Int?
        let endHour: Int?
        let endMinute: Int?
        let durationMinutes: Int?
    }

    private static func matchTimeOrDuration(in text: String) -> TimeMatch? {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        // 1. 시간 범위: 시작 ~ 종료 또는 시작부터 종료까지
        if let match = rangeRegex.firstMatch(in: text, options: [], range: fullRange), match.range.location == 0 {
            let startPeriod = string(from: nsText, range: match.range(at: 1))
            let startHStr = string(from: nsText, range: match.range(at: 2))
            let startMStr = string(from: nsText, range: match.range(at: 3))
            let startColonMStr = string(from: nsText, range: match.range(at: 4))
            let start = parseTime(period: startPeriod, hourStr: startHStr, minuteStr: startMStr, colonMinStr: startColonMStr)

            let endPeriod = string(from: nsText, range: match.range(at: 5))
            let endHStr = string(from: nsText, range: match.range(at: 6))
            let endMStr = string(from: nsText, range: match.range(at: 7))
            let endColonMStr = string(from: nsText, range: match.range(at: 8))

            var resolvedEndPeriod = endPeriod
            if resolvedEndPeriod.isEmpty {
                if (startPeriod == "오후" || start.hour >= 12) && (Int(endHStr) ?? 0) < 12 {
                    resolvedEndPeriod = "오후"
                }
            }
            let end = parseTime(period: resolvedEndPeriod, hourStr: endHStr, minuteStr: endMStr, colonMinStr: endColonMStr)

            return TimeMatch(
                tokenLength: match.range.length,
                startHour: start.hour,
                startMinute: start.minute,
                endHour: end.hour,
                endMinute: end.minute,
                durationMinutes: nil
            )
        }

        // 2. 시작 시각 + "시작" + 소요시간: "9시 시작 30분간", "9시 30분 시작 1시간"
        if let match = regexTimeDurA.firstMatch(in: text, options: [], range: fullRange), match.range.location == 0 {
            let startPeriod = string(from: nsText, range: match.range(at: 1))
            let startHStr = string(from: nsText, range: match.range(at: 2))
            let startMStr = string(from: nsText, range: match.range(at: 3))
            let startColonMStr = string(from: nsText, range: match.range(at: 4))
            let start = parseTime(period: startPeriod, hourStr: startHStr, minuteStr: startMStr, colonMinStr: startColonMStr)

            let durNum = Int(string(from: nsText, range: match.range(at: 5))) ?? 0
            let durUnit = string(from: nsText, range: match.range(at: 6))
            let durationMinutes = durUnit == "시간" ? durNum * 60 : durNum

            guard durationMinutes > 0, durNum <= 1000 else { return nil }

            return TimeMatch(
                tokenLength: match.range.length,
                startHour: start.hour,
                startMinute: start.minute,
                endHour: nil,
                endMinute: nil,
                durationMinutes: durationMinutes
            )
        }

        // 3. 시작 시각(정각 시) + 소요시간: "9시 30분간", "오후 2시 1시간"
        if let match = regexTimeDurB.firstMatch(in: text, options: [], range: fullRange), match.range.location == 0 {
            let startPeriod = string(from: nsText, range: match.range(at: 1))
            let startHStr = string(from: nsText, range: match.range(at: 2))
            let start = parseTime(period: startPeriod, hourStr: startHStr, minuteStr: "", colonMinStr: "")

            let durNum = Int(string(from: nsText, range: match.range(at: 3))) ?? 0
            let durUnit = string(from: nsText, range: match.range(at: 4))
            let durationMinutes = durUnit == "시간" ? durNum * 60 : durNum

            guard durationMinutes > 0, durNum <= 1000 else { return nil }

            return TimeMatch(
                tokenLength: match.range.length,
                startHour: start.hour,
                startMinute: start.minute,
                endHour: nil,
                endMinute: nil,
                durationMinutes: durationMinutes
            )
        }

        // 4. 단독 소요 시간만: "30분간", "30분", "2시간 동안", "90분"
        if let match = singleDurRegex.firstMatch(in: text, options: [], range: fullRange), match.range.location == 0 {
            let durNum = Int(string(from: nsText, range: match.range(at: 1))) ?? 0
            let durUnit = string(from: nsText, range: match.range(at: 2))
            let durationMinutes = durUnit == "시간" ? durNum * 60 : durNum

            guard durationMinutes > 0, durNum <= 1000 else { return nil }

            return TimeMatch(
                tokenLength: match.range.length,
                startHour: nil,
                startMinute: nil,
                endHour: nil,
                endMinute: nil,
                durationMinutes: durationMinutes
            )
        }

        // 5. 특정 시작 시각만: "9시 30분", "14:00", "오후 3시"
        if let match = singleTimeRegex.firstMatch(in: text, options: [], range: fullRange), match.range.location == 0 {
            let startPeriod = string(from: nsText, range: match.range(at: 1))
            let startHStr = string(from: nsText, range: match.range(at: 2))
            let startMStr = string(from: nsText, range: match.range(at: 3))
            let startColonMStr = string(from: nsText, range: match.range(at: 4))
            let start = parseTime(period: startPeriod, hourStr: startHStr, minuteStr: startMStr, colonMinStr: startColonMStr)

            guard (0...23).contains(start.hour), (0...59).contains(start.minute) else { return nil }

            return TimeMatch(
                tokenLength: match.range.length,
                startHour: start.hour,
                startMinute: start.minute,
                endHour: nil,
                endMinute: nil,
                durationMinutes: nil
            )
        }

        return nil
    }

    // MARK: - 정규식 (AGENTS.md R7: static 캐싱)

    private static let weekdayRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: "^(이번주|다음주)?\\s*([월화수목금토일])요일")
    }()

    private static let timePattern = "(?:(오전|오후|아침|저녁|밤)\\s*)?(\\d{1,2})(?:시(?:\\s*(\\d{1,2}|반)분?)?|:(\\d{2}))"

    private static let rangeRegex: NSRegularExpression = {
        let pattern = "^\(timePattern)\\s*(?:부터)?\\s*(?:~|-|부터)\\s*\(timePattern)(?:\\s*까지)?"
        return try! NSRegularExpression(pattern: pattern)
    }()

    private static let regexTimeDurA: NSRegularExpression = {
        let pattern = "^\(timePattern)\\s*시작\\s*(\\d{1,4})\\s*(분|시간)(?:\\s*(?:간|동안))?"
        return try! NSRegularExpression(pattern: pattern)
    }()

    private static let regexTimeDurB: NSRegularExpression = {
        let pattern = "^(?:(오전|오후|아침|저녁|밤)\\s*)?(\\d{1,2})시\\s*(\\d{1,4})\\s*(분|시간)(?:\\s*(?:간|동안))?"
        return try! NSRegularExpression(pattern: pattern)
    }()

    private static let singleDurRegex: NSRegularExpression = {
        let pattern = "^(\\d{1,4})\\s*(분|시간)(?:\\s*(?:간|동안))?"
        return try! NSRegularExpression(pattern: pattern)
    }()

    private static let singleTimeRegex: NSRegularExpression = {
        let pattern = "^\(timePattern)"
        return try! NSRegularExpression(pattern: pattern)
    }()

    // MARK: - 보조 함수

    private static func string(from text: NSString, range: NSRange) -> String {
        guard range.location != NSNotFound else { return "" }
        return text.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseTime(period: String, hourStr: String, minuteStr: String, colonMinStr: String) -> (hour: Int, minute: Int) {
        let rawHour = Int(hourStr) ?? 0
        var minute = 0
        if !colonMinStr.isEmpty {
            minute = Int(colonMinStr) ?? 0
        } else if minuteStr == "반" {
            minute = 30
        } else if !minuteStr.isEmpty {
            minute = Int(minuteStr) ?? 0
        }
        let hour = adjustHour(rawHour, period: period)
        return (hour, minute)
    }

    private static func adjustHour(_ hour: Int, period: String) -> Int {
        var h = hour
        if period == "오후" || period == "저녁" || period == "밤" {
            if h < 12 { h += 12 }
        } else if period == "오전" || period == "아침" {
            if h == 12 { h = 0 }
        }
        return h
    }

    private static func formatScheduleSummary(
        dayLabel: String?,
        startHour: Int?,
        startMinute: Int?,
        endHour: Int?,
        endMinute: Int?,
        durationMinutes: Int?
    ) -> String {
        var parts: [String] = []
        if let day = dayLabel {
            parts.append(day)
        }

        if let sH = startHour {
            let sM = startMinute ?? 0
            let startFormatted = String(format: "%02d:%02d", sH, sM)

            if let eH = endHour {
                let eM = endMinute ?? 0
                let endFormatted = String(format: "%02d:%02d", eH, eM)
                parts.append("\(startFormatted) ~ \(endFormatted)")
            } else if let dur = durationMinutes {
                let durText = dur >= 60 && dur % 60 == 0 ? "\(dur / 60)시간" : "\(dur)분"
                parts.append("\(startFormatted) (\(durText))")
            } else {
                parts.append(startFormatted)
            }
        } else if let dur = durationMinutes {
            let durText = dur >= 60 && dur % 60 == 0 ? "\(dur / 60)시간" : "\(dur)분"
            parts.append("09:00 (\(durText))")
        } else if dayLabel != nil {
            parts.append("09:00")
        }

        return parts.joined(separator: " ")
    }
}

