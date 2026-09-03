import Foundation

/// 마감까지 남은 날을 «3일 지남»·«내일» 같은 **화면 문구**로 만든다.
///
/// `Domain/Policies/` 로 보내지 않은 이유: 결과가 사람이 읽는 한국어 문자열과 색조(tone)라
/// 표현 계층의 관심사다. 판정 규칙 자체는 `TodoBucket` 이 가진다.
struct TodoDueChip: Equatable {
    enum Tone: Equatable {
        case over
        case today
        case soon
        case later
    }

    let label: String
    let tone: Tone

    static func of(
        startDate: Date?,
        deadline: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> TodoDueChip? {
        guard let basis = deadline ?? startDate else { return nil }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: basis)
        ).day ?? 0
        if days < 0 {
            return TodoDueChip(label: "\(-days)일 지남", tone: .over)
        }
        if days == 0 {
            return TodoDueChip(label: "오늘", tone: .today)
        }
        if days == 1 {
            return TodoDueChip(label: "내일", tone: .soon)
        }
        if days <= 6 {
            return TodoDueChip(label: "\(days)일 뒤", tone: .soon)
        }
        let month = calendar.component(.month, from: basis)
        let day = calendar.component(.day, from: basis)
        return TodoDueChip(label: "\(month)월 \(day)일", tone: .later)
    }
}
