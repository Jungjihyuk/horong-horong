import Foundation

/// 하루 단위 그래프의 공통 점.
struct DiaryTimeSeriesPoint: Identifiable, Equatable, Sendable {
    let day: Date
    let value: Double

    var id: Date { day }
}

/// 하루의 수면을 타임라인 축 위에 놓은 구간.
///
/// 비율로 들고 있는 이유: 차트가 «몇 시»를 그리려면 날짜가 다른 시각들을 같은 가로축에 올려야 하는데,
/// 절대 시각을 그대로 쓰면 날짜만큼 흩어진다. 축 기준 비율이면 모든 날이 같은 자리에 겹친다.
struct DiarySleepWindowPoint: Identifiable, Equatable, Sendable {
    let day: Date
    let startFraction: Double
    let endFraction: Double
    let hours: Double

    var id: Date { day }
}

/// 그래프에 찍는 감정 한 점.
///
/// **점수가 없다.** 예전에는 감정마다 −3…+3 의 등급을 매겨 y축으로 썼지만, 그건 기록이 아니라
/// 평가였다. y축은 이제 «얼마나 강했나»(`intensity`)이고, «무엇이었나» 는 이모지와 색이 말한다.
struct DiaryMoodPoint: Identifiable, Equatable, Sendable {
    let day: Date
    let slot: DiaryMoodSlot
    let mood: DiaryMood
    let cause: DiaryCause?
    let intensity: Int?
    /// 타임라인 x축 좌표. 슬롯의 기준 시각을 날짜에 얹은 값이다.
    let timestamp: Date

    var id: Date { timestamp }
}

/// Diary 화면에서 사용하는 통계 읽기 모델.
/// 저장 모델을 늘리지 않고 이 읽기 모델에 시계열을 추가하면 새 지표를 차트에 연결할 수 있다.
struct DiaryInsightsSnapshot: Equatable, Sendable {
    let start: Date
    let end: Date
    let moodPoints: [DiaryMoodPoint]
    let sleepPoints: [DiaryTimeSeriesPoint]
    let sleepWindowPoints: [DiarySleepWindowPoint]
    let moodDistribution: [String: Int]
    let causeDistribution: [String: Int]

    /// 한 흐름의 관측만. 이미 시간 순이다.
    func points(in stream: DiaryMoodStream) -> [DiaryMoodPoint] {
        moodPoints.filter { $0.slot.stream == stream }
    }

    func transitions(in stream: DiaryMoodStream) -> [DiaryMoodTransition] {
        DiaryMoodTransitionPolicy.transitions(points(in: stream))
    }

    func streaks(in stream: DiaryMoodStream) -> [DiaryMoodStreakSummary] {
        DiaryMoodStreakPolicy.summarize(points(in: stream))
    }

    /// 강도를 적지 않아 타임라인에 그릴 수 없는 기록 수. 화면이 «왜 점이 적지» 에 답하는 근거다.
    func missingIntensityCount(in stream: DiaryMoodStream) -> Int {
        points(in: stream).count { $0.intensity == nil }
    }
}

enum DiaryInsightsBuilder {
    /// `calendar` 를 받는 이유: 수면 구간을 축 위 비율로 바꾸고 슬롯을 시각에 얹는 계산이
    /// 달력에 기댄다. 안에서 `.current` 를 부르면 테스트가 실행 환경의 표준시에 매인다.
    static func build(
        entries: [DiaryDay],
        start: Date,
        end: Date,
        axis: DiarySleepAxis = .default,
        calendar: Calendar = .current
    ) -> DiaryInsightsSnapshot {
        let sorted = entries
            .filter { $0.day >= start && $0.day < end }
            .sorted { $0.day < $1.day }

        // 하루 안에서도 오전 → 오후 → 하루 순으로 세운다. `DiaryDay` 가 이미 슬롯 순으로
        // 정렬해 두므로 날짜 순 정렬만 지키면 전체가 시간 순이 된다.
        let moodPoints = sorted.flatMap { day in
            day.moodRecords.map { record in
                DiaryMoodPoint(
                    day: day.day,
                    slot: record.slot,
                    mood: record.mood,
                    cause: record.cause,
                    intensity: record.intensity,
                    timestamp: record.slot.timestamp(on: day.day, calendar: calendar)
                )
            }
        }
        let sleepPoints = sorted.compactMap { day -> DiaryTimeSeriesPoint? in
            guard let hours = day.sleepHours else { return nil }
            return DiaryTimeSeriesPoint(day: day.day, value: hours)
        }
        // 시각이 없는 옛 기록은 길이만으로 축 위에 세운다. 그러지 않으면 그 날만 막대가 비어
        // «기록이 없는 날» 처럼 보인다.
        let sleepWindowPoints = sorted.compactMap { day -> DiarySleepWindowPoint? in
            let window: DiarySleepWindow
            if let recorded = day.sleepWindow {
                window = recorded
            } else if let hours = day.sleepHours {
                window = DiarySleepWindowPolicy.window(hours: hours, day: day.day, calendar: calendar)
            } else {
                return nil
            }
            return DiarySleepWindowPoint(
                day: day.day,
                startFraction: DiarySleepWindowPolicy.fraction(of: window.start, day: day.day, axis: axis, calendar: calendar),
                endFraction: DiarySleepWindowPolicy.fraction(of: window.end, day: day.day, axis: axis, calendar: calendar),
                hours: window.hours
            )
        }
        let moodDistribution = Dictionary(grouping: moodPoints, by: { $0.mood.group.title })
            .mapValues(\.count)
        let causeDistribution = Dictionary(grouping: moodPoints.compactMap { $0.cause?.rawValue }, by: { $0 })
            .mapValues(\.count)

        return DiaryInsightsSnapshot(
            start: start,
            end: end,
            moodPoints: moodPoints,
            sleepPoints: sleepPoints,
            sleepWindowPoints: sleepWindowPoints,
            moodDistribution: moodDistribution,
            causeDistribution: causeDistribution
        )
    }
}

extension DiaryInsightsSnapshot {
    static let empty = DiaryInsightsSnapshot(
        start: .distantPast,
        end: .distantPast,
        moodPoints: [],
        sleepPoints: [],
        sleepWindowPoints: [],
        moodDistribution: [:],
        causeDistribution: [:]
    )
}
