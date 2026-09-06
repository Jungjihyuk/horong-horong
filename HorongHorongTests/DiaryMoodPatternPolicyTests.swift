import XCTest
@testable import 호롱호롱

/// 감정 패턴(전이·지속) 계산을 시계 없이 검사한다.
final class DiaryMoodPatternPolicyTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return calendar
    }()

    private func day(_ offset: Int) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1)) ?? Date()
        return calendar.date(byAdding: .day, value: offset, to: base) ?? base
    }

    /// 관측 하나. 슬롯을 지정하지 않으면 «하루» 칸으로 본다.
    private func point(_ offset: Int, _ mood: DiaryMood, slot: DiaryMoodSlot = .wholeDay) -> DiaryMoodPoint {
        DiaryMoodPoint(
            day: day(offset),
            slot: slot,
            mood: mood,
            cause: nil,
            intensity: nil,
            timestamp: slot.timestamp(on: day(offset), calendar: calendar)
        )
    }

    // MARK: - 전이

    func testTransitionsCountEachDirectionSeparately() {
        // 걱정 → 지침 → 걱정. 방향이 다르므로 서로 다른 전이 둘이다.
        let points = [point(0, .anxious), point(1, .exhausted), point(2, .anxious)]

        let transitions = DiaryMoodTransitionPolicy.transitions(points)

        XCTAssertEqual(transitions.count, 2)
        XCTAssertEqual(transitions.first { $0.from == .worried && $0.to == .tired }?.count, 1)
        XCTAssertEqual(transitions.first { $0.from == .tired && $0.to == .worried }?.count, 1)
    }

    /// 같은 영역이 이어진 경우는 세지 않는다 — 그건 지속(streak)이 답하는 질문이다.
    func testSelfTransitionsAreNotCounted() {
        // 불안·조급함·예민은 모두 «걱정» 영역이다.
        let points = [point(0, .anxious), point(1, .rushed), point(2, .sensitive)]

        XCTAssertTrue(DiaryMoodTransitionPolicy.transitions(points).isEmpty)
    }

    func testTransitionsAreSortedByCount() {
        let points = [
            point(0, .anxious), point(1, .exhausted),
            point(2, .anxious), point(3, .exhausted),
            point(4, .happy)
        ]

        let transitions = DiaryMoodTransitionPolicy.transitions(points)

        XCTAssertEqual(transitions.first?.from, .worried)
        XCTAssertEqual(transitions.first?.to, .tired)
        XCTAssertEqual(transitions.first?.count, 2)
    }

    func testSingleObservationHasNoTransitions() {
        XCTAssertTrue(DiaryMoodTransitionPolicy.transitions([point(0, .happy)]).isEmpty)
        XCTAssertTrue(DiaryMoodTransitionPolicy.transitions([]).isEmpty)
    }

    /// 오전·오후 흐름과 하루 흐름은 각각 따로 계산된다.
    /// 섞으면 «오후 → 하루» 라는, 감정이 바뀌지 않았는데 바뀐 것처럼 보이는 전이가 생긴다.
    func testStreamsAreScoredSeparatelyThroughTheSnapshot() {
        let entry = DiaryDay(
            day: day(0), body: "", stress: nil, sleepHours: nil, sleepSource: nil,
            moodRecords: [
                DiaryMoodRecord(slot: .morning, mood: .happy),
                DiaryMoodRecord(slot: .afternoon, mood: .angry),
                DiaryMoodRecord(slot: .wholeDay, mood: .comfort)
            ]
        )

        let snapshot = DiaryInsightsBuilder.build(
            entries: [entry], start: day(0), end: day(1), calendar: calendar
        )

        XCTAssertEqual(snapshot.transitions(in: .daypart).count, 1)
        XCTAssertEqual(snapshot.transitions(in: .daypart).first?.from, .bright)
        XCTAssertEqual(snapshot.transitions(in: .daypart).first?.to, .angry)
        XCTAssertTrue(snapshot.transitions(in: .wholeDay).isEmpty)
    }

    // MARK: - 지속

    func testStreakGroupsConsecutiveRuns() {
        // 걱정 3칸 → 밝음 1칸 → 걱정 1칸.
        let points = [
            point(0, .anxious), point(1, .rushed), point(2, .sensitive),
            point(3, .happy),
            point(4, .fear)
        ]

        let summaries = DiaryMoodStreakPolicy.summarize(points)
        let worried = try? XCTUnwrap(summaries.first { $0.group == .worried })

        XCTAssertEqual(worried?.runCount, 2, "두 번 찾아왔다")
        XCTAssertEqual(worried?.longestLength, 3)
        XCTAssertEqual(worried?.totalCount, 4)
        XCTAssertEqual(worried?.averageLength ?? 0, 2, accuracy: 0.0001)
    }

    func testStreakSortsLongestAverageFirst() {
        let points = [
            point(0, .anxious), point(1, .rushed), point(2, .sensitive),
            point(3, .happy)
        ]

        XCTAssertEqual(DiaryMoodStreakPolicy.summarize(points).first?.group, .worried)
    }

    func testSingleObservationIsAStreakOfOne() {
        let summaries = DiaryMoodStreakPolicy.summarize([point(0, .happy)])

        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries.first?.runCount, 1)
        XCTAssertEqual(summaries.first?.longestLength, 1)
    }

    func testEmptyInputProducesNoSummaries() {
        XCTAssertTrue(DiaryMoodStreakPolicy.summarize([]).isEmpty)
    }

    /// 정책은 **관측 개수**로만 센다. 오전·오후 관측 하나가 반나절이라는 사실은 화면이 옮긴다 —
    /// 정책이 흐름마다 다른 단위를 들고 있으면 같은 계산이 두 벌이 된다.
    func testStreakCountsObservationsNotDays() {
        let daypart = [
            point(0, .anxious, slot: .morning),
            point(0, .rushed, slot: .afternoon),
            point(1, .fear, slot: .morning)
        ]

        let worried = DiaryMoodStreakPolicy.summarize(daypart).first { $0.group == .worried }

        XCTAssertEqual(worried?.longestLength, 3, "세 칸이 이어졌다 — 날짜로 환산하지 않는다")
        XCTAssertEqual(worried?.totalCount, 3)
    }

    /// **적지 않은 날은 흐름에 들어오지 않는다.** 빈 칸을 «같은 감정이 이어졌다» 로 읽으면
    /// 없는 사실을 지어내게 된다 — 기록이 있는 날만 이어 세는지 확인한다.
    func testGapsDoNotInflateStreaks() {
        let recorded = DiaryDay(
            day: day(0), body: "", stress: nil, sleepHours: nil, sleepSource: nil,
            moodRecords: [DiaryMoodRecord(slot: .wholeDay, mood: .anxious)]
        )
        let blank = DiaryDay(day: day(1), body: "빈 날", stress: nil, sleepHours: nil, sleepSource: nil)
        let later = DiaryDay(
            day: day(2), body: "", stress: nil, sleepHours: nil, sleepSource: nil,
            moodRecords: [DiaryMoodRecord(slot: .wholeDay, mood: .rushed)]
        )

        let snapshot = DiaryInsightsBuilder.build(
            entries: [recorded, blank, later], start: day(0), end: day(3), calendar: calendar
        )
        let worried = snapshot.streaks(in: .wholeDay).first { $0.group == .worried }

        XCTAssertEqual(snapshot.points(in: .wholeDay).count, 2, "빈 날은 관측이 아니다")
        XCTAssertEqual(worried?.totalCount, 2)
        XCTAssertEqual(worried?.runCount, 1, "기록된 둘은 이어진 것으로 본다")
    }
}
