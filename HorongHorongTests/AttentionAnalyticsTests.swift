import XCTest
@testable import 호롱호롱

final class AttentionAnalyticsTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testFocusSessionCommunicationSegmentCountsAsSelectiveDistraction() {
        let start = date(hour: 9)
        let session = focusSession(start: start, endedAt: start.addingTimeInterval(25 * 60), completed: true)
        let segments = [
            segment("Xcode", "개발", start, start.addingTimeInterval(5 * 60)),
            segment("KakaoTalk", "소통", start.addingTimeInterval(5 * 60), start.addingTimeInterval(7 * 60)),
            segment("Xcode", "개발", start.addingTimeInterval(7 * 60), start.addingTimeInterval(25 * 60)),
        ]

        let summary = AttentionAnalytics.summary(
            for: start,
            segments: segments,
            timerSessions: [session],
            thresholds: .standard,
            isAllowedSwitch: { _, _ in false }
        )

        XCTAssertTrue(summary.events.contains { $0.type == .selectiveDistraction })
        XCTAssertEqual(summary.primaryEvent?.type, .selectiveDistraction)
    }

    func testCompletedFocusSessionWithLateReturnCountsAsDelayedReturn() {
        let start = date(hour: 9)
        let focusEnd = start.addingTimeInterval(25 * 60)
        let expectedReturn = focusEnd.addingTimeInterval(5 * 60)
        let session = focusSession(start: start, endedAt: focusEnd, completed: true)
        let segments = [
            segment("YouTube", "엔터", expectedReturn, expectedReturn.addingTimeInterval(15 * 60)),
            segment("Xcode", "개발", expectedReturn.addingTimeInterval(15 * 60), expectedReturn.addingTimeInterval(30 * 60)),
        ]

        let summary = AttentionAnalytics.summary(
            for: start,
            segments: segments,
            timerSessions: [session],
            thresholds: .standard,
            isAllowedSwitch: { _, _ in false }
        )

        let delayedReturn = summary.events.first { $0.type == .delayedReturn }
        XCTAssertNotNil(delayedReturn)
        XCTAssertEqual(delayedReturn?.durationSeconds, 15 * 60)
    }

    func testEarlyStoppedSessionCountsAsSustainedDrop() {
        let start = date(hour: 9)
        let endedAt = start.addingTimeInterval(5 * 60)
        let session = focusSession(start: start, endedAt: endedAt, completed: false)

        let summary = AttentionAnalytics.summary(
            for: start,
            segments: [],
            timerSessions: [session],
            thresholds: .standard,
            isAllowedSwitch: { _, _ in false }
        )

        let sustainedDrop = summary.events.first { $0.type == .sustainedDrop }
        XCTAssertNotNil(sustainedDrop)
        XCTAssertEqual(sustainedDrop?.durationSeconds, 20 * 60)
    }

    func testCustomDistractionCategoryControlsSelectiveDistraction() {
        let start = date(hour: 9)
        let session = focusSession(start: start, endedAt: start.addingTimeInterval(25 * 60), completed: true)
        let segments = [
            segment("Browser", "조사", start.addingTimeInterval(2 * 60), start.addingTimeInterval(8 * 60)),
        ]

        let allowedResearch = AttentionAnalytics.summary(
            for: start,
            segments: segments,
            timerSessions: [session],
            thresholds: .standard,
            isAllowedSwitch: { _, _ in false },
            isDistractionCategory: { _ in false }
        )
        let blockedResearch = AttentionAnalytics.summary(
            for: start,
            segments: segments,
            timerSessions: [session],
            thresholds: .standard,
            isAllowedSwitch: { _, _ in false },
            isDistractionCategory: { $0 == "조사" }
        )

        XCTAssertFalse(allowedResearch.events.contains { $0.type == .selectiveDistraction })
        XCTAssertTrue(blockedResearch.events.contains { $0.type == .selectiveDistraction })
    }

    func testNotDistractionCorrectionRemovesEventFromSummary() {
        let start = date(hour: 9)
        let session = focusSession(start: start, endedAt: start.addingTimeInterval(25 * 60), completed: true)
        let segments = [
            segment("KakaoTalk", "소통", start.addingTimeInterval(5 * 60), start.addingTimeInterval(7 * 60)),
        ]

        let original = AttentionAnalytics.summary(
            for: start,
            segments: segments,
            timerSessions: [session],
            thresholds: .standard,
            isAllowedSwitch: { _, _ in false }
        )
        let fingerprint = original.events.first { $0.type == .selectiveDistraction }?.fingerprint

        let corrected = AttentionAnalytics.summary(
            for: start,
            segments: segments,
            timerSessions: [session],
            thresholds: .standard,
            isAllowedSwitch: { _, _ in false },
            corrections: [
                AttentionEventCorrection(fingerprint: fingerprint ?? "", verdict: .notDistraction)
            ]
        )

        XCTAssertNotNil(fingerprint)
        XCTAssertFalse(corrected.events.contains { $0.type == .selectiveDistraction })
        XCTAssertFalse(corrected.hasSignals)
    }

    func testDailyAttentionReportFindsBestAndWorstWindows() {
        let start = date(hour: 9)
        let afternoon = date(hour: 15)
        let buckets = [
            TimelineBucket(
                startTime: start,
                endTime: start.addingTimeInterval(30 * 60),
                categoryDurations: ["개발": 30 * 60],
                switches: 0
            ),
            TimelineBucket(
                startTime: afternoon,
                endTime: afternoon.addingTimeInterval(30 * 60),
                categoryDurations: ["개발": 10 * 60, "소통": 10 * 60, "엔터": 10 * 60],
                switches: 5
            ),
        ]

        let report = DailyAttentionReportBuilder.build(
            day: start,
            buckets: buckets,
            segments: [],
            timerSessions: [],
            attentionSummary: .empty,
            thresholds: .standard,
            isFinalized: true
        )

        XCTAssertEqual(report.bestWindow?.start, start)
        XCTAssertEqual(report.worstWindow?.start, afternoon)
        XCTAssertEqual(report.flowState, .steady)
    }

    func testFinalizedDailyAttentionReportUsesFullDayLongestRun() {
        let start = date(hour: 9)
        let longRunEnd = start.addingTimeInterval(75 * 60)
        let segments = [
            segment("Xcode", "개발", start, start.addingTimeInterval(35 * 60)),
            segment("Xcode", "개발", start.addingTimeInterval(36 * 60), longRunEnd),
            segment("KakaoTalk", "소통", date(hour: 13), date(hour: 13).addingTimeInterval(10 * 60)),
        ]
        let buckets = TimelineAnalytics.buckets(for: start, segments: segments)

        let report = DailyAttentionReportBuilder.build(
            day: start,
            buckets: buckets,
            segments: segments,
            timerSessions: [],
            attentionSummary: .empty,
            thresholds: .standard,
            isFinalized: true
        )

        XCTAssertEqual(report.bestWindow?.start, start)
        XCTAssertEqual(report.bestWindow?.end, longRunEnd)
        XCTAssertEqual(report.bestWindow?.durationSeconds, 75 * 60)
        XCTAssertTrue(report.bestWindow?.reason.contains("75분") == true || report.bestWindow?.reason.contains("1시간") == true)
    }

    func testDailyAttentionReportUsesDelayedReturnForGuidance() {
        let start = date(hour: 9)
        let delayedAt = date(hour: 10)
        let event = AttentionEventCandidate(
            type: .delayedReturn,
            occurredAt: delayedAt,
            sourceApp: "YouTube",
            sourceCategory: "엔터",
            targetCategory: "개발",
            durationSeconds: 20 * 60,
            confidence: 0.72
        )
        let summary = AttentionSummary(
            selectiveScore: 1,
            sustainedScore: 1,
            returnScore: 0.5,
            overallScore: 0.6,
            events: [event]
        )

        let report = DailyAttentionReportBuilder.build(
            day: start,
            buckets: [
                TimelineBucket(
                    startTime: start,
                    endTime: start.addingTimeInterval(30 * 60),
                    categoryDurations: ["개발": 30 * 60],
                    switches: 0
                ),
            ],
            segments: [],
            timerSessions: [],
            attentionSummary: summary,
            thresholds: .standard,
            isFinalized: true
        )

        XCTAssertEqual(report.difficultRecovery?.durationSeconds, 20 * 60)
        XCTAssertTrue(report.guidanceMessage.contains("휴식"))
    }

    func testWeeklyAttentionTrendReportComparesCurrentAndPreviousWeek() {
        let weekStart = date(day: 18, hour: 0)
        let previousStart = date(day: 11, hour: 0)
        let summaries = [
            daySummary(day: previousStart, score: 0.55, selective: 2, sustained: 1, delayedReturn: 2),
            daySummary(day: previousStart.addingTimeInterval(24 * 60 * 60), score: 0.60, selective: 2, sustained: 1, delayedReturn: 1),
            daySummary(day: weekStart, score: 0.80, selective: 0, sustained: 0, delayedReturn: 0),
            daySummary(day: weekStart.addingTimeInterval(24 * 60 * 60), score: 0.78, selective: 1, sustained: 0, delayedReturn: 0),
        ]

        let report = WeeklyAttentionTrendReportBuilder.build(
            weekStart: weekStart,
            summaries: summaries
        )

        XCTAssertTrue(report.hasComparableData)
        XCTAssertEqual(report.currentDayCount, 2)
        XCTAssertEqual(report.previousDayCount, 2)
        XCTAssertTrue(report.metrics.contains { $0.title == "평균 흐름 점수" && $0.direction == .improved })
        XCTAssertTrue(report.metrics.contains { $0.title == "복귀 지연" && $0.direction == .improved })
    }

    func testMonthlyAttentionPatternReportFindsWeekdayAndDominantSignal() {
        let monthStart = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let previousStart = calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))!
        let summaries = [
            daySummary(day: previousStart, score: 0.52, selective: 1, sustained: 0, delayedReturn: 0),
            daySummary(day: previousStart.addingTimeInterval(24 * 60 * 60), score: 0.50, selective: 1, sustained: 0, delayedReturn: 1),
            daySummary(day: date(day: 4, hour: 0), score: 0.90, selective: 0, sustained: 0, delayedReturn: 0),
            daySummary(day: date(day: 11, hour: 0), score: 0.86, selective: 0, sustained: 0, delayedReturn: 0),
            daySummary(day: date(day: 5, hour: 0), score: 0.35, selective: 0, sustained: 0, delayedReturn: 3),
        ]

        let report = MonthlyAttentionPatternReportBuilder.build(
            monthStart: monthStart,
            summaries: summaries
        )

        XCTAssertTrue(report.hasCurrentData)
        XCTAssertEqual(report.currentDayCount, 3)
        XCTAssertEqual(report.previousDayCount, 2)
        XCTAssertEqual(report.scoreTrend?.direction, .improved)
        XCTAssertTrue(report.patterns.contains { $0.title == "강한 요일" && $0.value.contains("월요일") })
        XCTAssertTrue(report.patterns.contains { $0.title == "반복 신호" && $0.value.contains("복귀 지연") })
        XCTAssertTrue(report.guidanceMessage.contains("휴식"))
    }

    private func focusSession(start: Date, endedAt: Date, completed: Bool) -> FocusSession {
        let session = FocusSession(focusMinutes: 25, breakMinutes: 5, category: "개발")
        session.startedAt = start
        session.endedAt = endedAt
        session.completed = completed
        return session
    }

    private func segment(_ appName: String, _ category: String, _ start: Date, _ end: Date) -> AppUsageSegment {
        AppUsageSegment(
            appName: appName,
            bundleIdentifier: "test.\(appName)",
            category: category,
            startTime: start,
            endTime: end
        )
    }

    private func date(hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 5, day: 29, hour: hour))!
    }

    private func date(day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 5, day: day, hour: hour))!
    }

    private func daySummary(
        day: Date,
        score: Double,
        selective: Int,
        sustained: Int,
        delayedReturn: Int
    ) -> AttentionDaySummary {
        AttentionDaySummary(
            day: day,
            dayKey: "test-\(Int(day.timeIntervalSince1970))",
            flowState: .steady,
            overallScore: score,
            selectiveEventCount: selective,
            sustainedEventCount: sustained,
            returnEventCount: delayedReturn,
            representativeReason: nil
        )
    }
}
