import Foundation

/// 하루치 일기.
///
/// **값 타입이다.** 저장은 `Diary`(`@Model`)가 하지만 그건 Data 계층에 남는다.
///
/// `id` 가 `day` 인 이유: **하루에 한 장**이라 날짜가 곧 신원이다. 저장 쪽 `UUID` 를
/// 그대로 쓰면 중복 행이 생겼을 때 화면이 둘을 다른 날로 취급한다.
struct DiaryDay: Identifiable, Equatable, Sendable {
    let day: Date
    let body: String
    /// 오전·오후·하루 중 적은 것만. 슬롯 순으로 정렬돼 있고 비어 있을 수 있다.
    let moodRecords: [DiaryMoodRecord]
    let stress: Int?
    let sleepHours: Double?
    let sleepSource: DiarySleepSource?
    /// 취침·기상 시각. 옛 기록은 길이(`sleepHours`)만 있어 둘 다 `nil` 이다.
    let sleepStart: Date?
    let sleepEnd: Date?

    var id: Date { day }

    func record(_ slot: DiaryMoodSlot) -> DiaryMoodRecord? {
        moodRecords.first { $0.slot == slot }
    }

    /// 달력 한 칸이 대표로 보여 줄 감정. 좁은 범위부터가 아니라 **넓은 범위부터** 고른다 —
    /// 그날 전체를 한마디로 적었다면 그것이 그날의 얼굴이다.
    var representativeMood: DiaryMood? {
        record(.wholeDay)?.mood ?? record(.afternoon)?.mood ?? record(.morning)?.mood
    }

    /// 달력 칸에 찍는 점의 색 근거. 적은 순서대로.
    var recordedGroups: [DiaryMoodGroup] {
        moodRecords.map(\.mood.group)
    }

    /// 취침·기상이 모두 있을 때의 구간. 길이만 남은 옛 기록에는 없다.
    var sleepWindow: DiarySleepWindow? {
        guard let sleepStart, let sleepEnd else { return nil }
        return DiarySleepWindow(start: sleepStart, end: sleepEnd)
    }

    init(
        day: Date,
        body: String,
        stress: Int?,
        sleepHours: Double?,
        sleepSource: DiarySleepSource?,
        moodRecords: [DiaryMoodRecord] = [],
        sleepStart: Date? = nil,
        sleepEnd: Date? = nil
    ) {
        self.day = day
        self.body = body
        // 슬롯 순서를 여기서 한 번 세워 두면 화면과 그래프가 저마다 정렬하지 않아도 된다.
        self.moodRecords = DiaryMoodSlot.allCases.compactMap { slot in
            moodRecords.first { $0.slot == slot }
        }
        self.stress = stress
        self.sleepHours = sleepHours
        self.sleepSource = sleepSource
        self.sleepStart = sleepStart
        self.sleepEnd = sleepEnd
    }
}
