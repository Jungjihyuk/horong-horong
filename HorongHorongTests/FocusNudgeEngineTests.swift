import XCTest
import SwiftData
@testable import 호롱호롱

final class FocusNudgeEngineTests: XCTestCase {
    private let day = Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 3, day: 10, hour: 0)
    )!

    func testColdStartWithTodayTaskSuggestsThatTask() {
        let context = makeContext(nextTask: .init(title: "보고서 초안", at: day.addingTimeInterval(15 * 3600), isOverdue: false))

        let nudge = FocusNudgeEngine.resolve(context)

        XCTAssertEqual(nudge.ruleID, "coldStart.withTask")
        XCTAssertEqual(nudge.tier, .coldStart)
        XCTAssertTrue(nudge.message.contains("보고서 초안"), nudge.message)
    }

    func testColdStartWithoutTaskFallsBackToFirstStepPool() {
        let nudge = FocusNudgeEngine.resolve(makeContext())

        XCTAssertEqual(nudge.ruleID, "coldStart.firstStep")
        XCTAssertFalse(nudge.message.isEmpty)
    }

    /// SwiftUI body 는 자주 다시 계산되므로 같은 날에는 같은 문구가 나와야 한다.
    func testMessageSelectionIsStableWithinSameDay() {
        let morning = makeContext(now: day.addingTimeInterval(9 * 3600))
        let evening = makeContext(now: day.addingTimeInterval(20 * 3600))

        XCTAssertEqual(
            FocusNudgeEngine.resolve(morning).message,
            FocusNudgeEngine.resolve(evening).message
        )
    }

    func testBehindYesterdayWinsOverFallback() {
        let context = makeContext(
            todayCompletedCount: 1,
            todayFocusSeconds: 25 * 60,
            yesterdayCountBySameTime: 3,
            yesterdayCompletedCount: 5,
            recordedDayCount: 6
        )

        let nudge = FocusNudgeEngine.resolve(context)

        XCTAssertEqual(nudge.ruleID, "today.behindYesterday")
        XCTAssertTrue(nudge.message.contains("2회"), nudge.message)
    }

    func testRepeatedIncompleteReasonOutranksTodayProgressRules() {
        let context = makeContext(
            todayCompletedCount: 1,
            yesterdayCountBySameTime: 3,
            yesterdayCompletedCount: 5,
            topIncompleteReason: .underestimatedScope,
            topIncompleteReasonCount: 4,
            recordedDayCount: 9
        )

        let nudge = FocusNudgeEngine.resolve(context)

        XCTAssertEqual(nudge.ruleID, "personalized.repeatedIncompleteReason")
        XCTAssertTrue(nudge.message.contains("4번"), nudge.message)
    }

    func testLowCoverageNeedsAtLeastThirtyMinutesOfRecording() {
        let short = makeContext(
            todayCompletedCount: 2,
            observedSeconds: 20 * 60,
            coveredSeconds: 0,
            recordedDayCount: 4
        )
        XCTAssertNil(short.coverageRatio)
        XCTAssertNotEqual(FocusNudgeEngine.resolve(short).ruleID, "today.lowCoverage")

        let long = makeContext(
            todayCompletedCount: 2,
            observedSeconds: 4 * 3600,
            coveredSeconds: 30 * 60,
            recordedDayCount: 4
        )
        XCTAssertEqual(long.coverageRatio, 0.125)
        XCTAssertEqual(FocusNudgeEngine.resolve(long).ruleID, "today.lowCoverage")
    }

    func testFocusedResponseDeltaUsesComparableCounts() {
        let context = makeContext(
            todayCompletedCount: 2,
            recentReflection: FocusReflectionSummary(
                focusedResponseCount: 5,
                validResponseCount: 7
            ),
            previousReflection: FocusReflectionSummary(
                focusedResponseCount: 2,
                validResponseCount: 6
            ),
            observedSeconds: 2 * 3600,
            coveredSeconds: 2 * 3600,
            recordedDayCount: 10
        )

        XCTAssertEqual(context.focusedResponseDelta, 3)
        let nudge = FocusNudgeEngine.resolve(context)
        XCTAssertEqual(nudge.ruleID, "personalized.deepFocusRise")
        XCTAssertTrue(nudge.message.contains("3회"), nudge.message)
    }

    func testFocusedResponseComparisonWaitsWhenSampleCountsDifferTooMuch() {
        let context = makeContext(
            todayCompletedCount: 2,
            recentReflection: FocusReflectionSummary(
                focusedResponseCount: 5,
                validResponseCount: 8
            ),
            previousReflection: FocusReflectionSummary(
                focusedResponseCount: 2,
                validResponseCount: 3
            ),
            observedSeconds: 2 * 3600,
            coveredSeconds: 2 * 3600,
            recordedDayCount: 10
        )

        XCTAssertNil(context.focusedResponseDelta)
        XCTAssertEqual(FocusNudgeEngine.resolve(context).ruleID, "fallback")
    }

    @MainActor
    func testPersonalizedContextUsesTwoExactSevenDayWindows() throws {
        let schema = Schema([
            FocusSession.self,
            PomodoroReflection.self,
            AppUsageSegment.self,
            Memo.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let modelContext = container.mainContext
        let calendar = Calendar(identifier: .gregorian)

        func insertSession(
            daysFromSelectedDay: Int,
            experience: PomodoroFocusExperience
        ) {
            let startedAt = calendar.date(
                byAdding: .day,
                value: daysFromSelectedDay,
                to: day
            )!.addingTimeInterval(12 * 60 * 60)
            let session = FocusSession(
                focusMinutes: 25,
                breakMinutes: 5,
                category: "개발"
            )
            session.startedAt = startedAt
            session.endedAt = startedAt.addingTimeInterval(25 * 60)
            session.completed = true
            modelContext.insert(session)
            modelContext.insert(
                PomodoroReflection(
                    focusSessionID: session.id,
                    focusExperience: experience,
                    progressResult: .completedAsPlanned
                )
            )
        }

        [-6, -5, -4].forEach {
            insertSession(daysFromSelectedDay: $0, experience: .deeplyFocused)
        }
        [-13, -12, -7].forEach {
            insertSession(daysFromSelectedDay: $0, experience: .difficultToFocus)
        }
        try modelContext.save()

        let context = FocusNudgeSnapshotLoader.context(
            day: day,
            now: day.addingTimeInterval(14 * 60 * 60),
            modelContext: modelContext
        )

        XCTAssertEqual(
            context.recentReflection,
            FocusReflectionSummary(
                focusedResponseCount: 3,
                validResponseCount: 3
            )
        )
        XCTAssertEqual(
            context.previousReflection,
            FocusReflectionSummary(
                focusedResponseCount: 0,
                validResponseCount: 3
            )
        )
    }

    /// 기록이 하나라도 있으면 콜드스타트 문구는 나오지 않아야 한다.
    func testExistingHistoryNeverShowsColdStartMessages() {
        let context = makeContext(recordedDayCount: 1)

        XCTAssertFalse(context.isColdStart)
        XCTAssertEqual(FocusNudgeEngine.resolve(context).ruleID, "fallback")
    }

    func testHistoricalTrendPeriodUsesTwoSevenDayWindowsWithoutFutureData() {
        let calendar = Calendar(identifier: .gregorian)
        let period = HistoricalFocusTrendPeriod.ending(
            on: day,
            calendar: calendar
        )

        XCTAssertEqual(period.selectedDay, day)
        XCTAssertEqual(
            period.recentEnd,
            calendar.date(byAdding: .day, value: 1, to: day)
        )
        XCTAssertEqual(
            calendar.dateComponents(
                [.day],
                from: period.recentStart,
                to: period.recentEnd
            ).day,
            7
        )
        XCTAssertEqual(period.previousEnd, period.recentStart)
        XCTAssertEqual(
            calendar.dateComponents(
                [.day],
                from: period.previousStart,
                to: period.previousEnd
            ).day,
            7
        )
    }

    func testHistoricalTrendStateUsesReflectionDelta() {
        let period = HistoricalFocusTrendPeriod.ending(on: day)

        XCTAssertEqual(
            HistoricalFocusTrendSnapshot(
                period: period,
                recent: makeHistoricalWindow(
                    focusedResponseCount: 5,
                    validResponseCount: 7
                ),
                previous: makeHistoricalWindow(
                    focusedResponseCount: 2,
                    validResponseCount: 6
                )
            ).state,
            .deepening
        )
        XCTAssertEqual(
            HistoricalFocusTrendSnapshot(
                period: period,
                recent: makeHistoricalWindow(
                    focusedResponseCount: 4,
                    validResponseCount: 7
                ),
                previous: makeHistoricalWindow(
                    focusedResponseCount: 3,
                    validResponseCount: 7
                )
            ).state,
            .steady
        )
        XCTAssertEqual(
            HistoricalFocusTrendSnapshot(
                period: period,
                recent: makeHistoricalWindow(
                    focusedResponseCount: 2,
                    validResponseCount: 6
                ),
                previous: makeHistoricalWindow(
                    focusedResponseCount: 5,
                    validResponseCount: 7
                )
            ).state,
            .softening
        )
        XCTAssertEqual(
            HistoricalFocusTrendSnapshot(
                period: period,
                recent: makeHistoricalWindow(
                    focusedResponseCount: 1,
                    validResponseCount: 2
                ),
                previous: makeHistoricalWindow(
                    focusedResponseCount: 2,
                    validResponseCount: 3
                )
            ).state,
            .collecting
        )
        XCTAssertEqual(
            HistoricalFocusTrendSnapshot(
                period: period,
                recent: makeHistoricalWindow(
                    focusedResponseCount: 5,
                    validResponseCount: 8
                ),
                previous: makeHistoricalWindow(
                    focusedResponseCount: 2,
                    validResponseCount: 3
                )
            ).state,
            .collecting
        )
    }

    func testHistoricalActivityMetricsAreNormalizedByRecordedTime() {
        let enough = makeHistoricalWindow(
            observedSeconds: 60 * 60,
            timerCoveredSeconds: 30 * 60,
            categorySwitchCount: 6
        )
        XCTAssertEqual(enough.timerCoverageRatio, 0.5)
        XCTAssertEqual(enough.categorySwitchesPerRecordedTenMinutes, 1.0)

        let short = makeHistoricalWindow(
            observedSeconds: 29 * 60,
            timerCoveredSeconds: 29 * 60,
            categorySwitchCount: 3
        )
        XCTAssertNil(short.timerCoverageRatio)
        XCTAssertNil(short.categorySwitchesPerRecordedTenMinutes)
    }

    // MARK: - Helpers

    private func makeHistoricalWindow(
        completedPomodoroCount: Int = 0,
        pomodoroFocusSeconds: Int = 0,
        focusedResponseCount: Int = 0,
        validResponseCount: Int = 0,
        observedSeconds: Int = 0,
        timerCoveredSeconds: Int = 0,
        categorySwitchCount: Int = 0
    ) -> HistoricalFocusTrendWindow {
        HistoricalFocusTrendWindow(
            completedPomodoroCount: completedPomodoroCount,
            pomodoroFocusSeconds: pomodoroFocusSeconds,
            reflection: FocusReflectionSummary(
                focusedResponseCount: focusedResponseCount,
                validResponseCount: validResponseCount
            ),
            observedSeconds: observedSeconds,
            timerCoveredSeconds: timerCoveredSeconds,
            categorySwitchCount: categorySwitchCount
        )
    }

    private func makeContext(
        now: Date? = nil,
        todayCompletedCount: Int = 0,
        todayFocusSeconds: Int = 0,
        yesterdayCountBySameTime: Int = 0,
        yesterdayCompletedCount: Int = 0,
        recentReflection: FocusReflectionSummary = .empty,
        previousReflection: FocusReflectionSummary = .empty,
        topCategory: String? = nil,
        topIncompleteReason: PomodoroIncompleteReason? = nil,
        topIncompleteReasonCount: Int = 0,
        observedSeconds: Int = 0,
        coveredSeconds: Int = 0,
        openTaskCount: Int = 0,
        totalTaskCount: Int = 0,
        overdueTaskCount: Int = 0,
        nextTask: FocusNudgeContext.TaskCandidate? = nil,
        recordedDayCount: Int = 0
    ) -> FocusNudgeContext {
        FocusNudgeContext(
            day: day,
            now: now ?? day.addingTimeInterval(14 * 3600),
            todayCompletedCount: todayCompletedCount,
            todayFocusSeconds: todayFocusSeconds,
            yesterdayCountBySameTime: yesterdayCountBySameTime,
            yesterdayCompletedCount: yesterdayCompletedCount,
            recentReflection: recentReflection,
            previousReflection: previousReflection,
            topCategory: topCategory,
            topIncompleteReason: topIncompleteReason,
            topIncompleteReasonCount: topIncompleteReasonCount,
            observedSeconds: observedSeconds,
            coveredSeconds: coveredSeconds,
            openTaskCount: openTaskCount,
            totalTaskCount: totalTaskCount,
            overdueTaskCount: overdueTaskCount,
            nextTask: nextTask,
            recordedDayCount: recordedDayCount
        )
    }
}
