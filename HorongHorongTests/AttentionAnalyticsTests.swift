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
}
