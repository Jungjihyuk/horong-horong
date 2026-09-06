import Foundation

/// 시작 날짜를 «3일 지남»·«내일» 같은 **화면 문구**로 만든다.
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
        // 목록의 날짜 태그는 일정 카드의 시작 날짜와 같은 기준을 보여 준다.
        // 시작은 오늘이고 소요 시간이 길어 마감만 내일인 일정도 «오늘»로 읽혀야 한다.
        guard let basis = startDate ?? deadline else { return nil }
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
