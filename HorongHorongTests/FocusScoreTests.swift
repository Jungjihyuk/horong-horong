import SwiftData
import XCTest
@testable import 호롱호롱

final class FocusSessionActivityIntervalsTests: XCTestCase {
    func testExcludesPauseAndKeepsResumedTime() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let intervals = FocusSessionActivityIntervals.make(
            startedAt: start,
            endedAt: start.addingTimeInterval(50 * 60),
            excluding: [
                FocusSessionPauseInterval(
                    startedAt: start.addingTimeInterval(10 * 60),
                    endedAt: start.addingTimeInterval(30 * 60)
                ),
            ],
            maximumActiveSeconds: 30 * 60
        )

        XCTAssertEqual(intervals.count, 2)
        XCTAssertEqual(intervals[0].start, start)
        XCTAssertEqual(intervals[0].duration, 10 * 60, accuracy: 0.001)
        XCTAssertEqual(intervals[1].start, start.addingTimeInterval(30 * 60))
        XCTAssertEqual(intervals[1].duration, 20 * 60, accuracy: 0.001)
    }
}

final class FocusScoreCalculatorTests: XCTestCase {
    private func makeObservation(
        sessionSeconds: Int,
        recordedSeconds: Int? = nil,
        ambiguousOverlapSeconds: Int = 0,
        categories: [(String, Int)]
    ) -> PomodoroSessionObservation {
        let entries = categories.map {
            PomodoroCategoryUsageEntry(category: $0.0, durationSeconds: $0.1)
        }
        return PomodoroSessionObservation(
            sessionSeconds: sessionSeconds,
            recordedSeconds: recordedSeconds ?? entries.reduce(0) { $0 + $1.durationSeconds },
            unrecordedSeconds: 0,
            ambiguousOverlapSeconds: ambiguousOverlapSeconds,
            userModifiedRecordedSeconds: 0,
            appSwitchCount: 0,
            appUsageRunCount: 0,
            categorySwitchCount: 0,
            categoryTransitions: [],
            longestContinuousAppUsage: nil,
            apps: [],
            categories: entries
        )
    }

    /// 짝 없음 — 어떤 조합도 짝이 아니다.
    private func noPairs(_ lhs: String, _ rhs: String) -> Bool { false }

    func testFullyOnFocusCategoryScoresOne() {
        let score = FocusScoreCalculator.score(
            observation: makeObservation(sessionSeconds: 1_500, categories: [("개발", 1_500)]),
            focusCategory: "개발",
            isPaired: noPairs
        )

        XCTAssertEqual(score.value, 1.0, accuracy: 0.0001)
    }

    /// "개발 중 조사" 처럼 짝으로 묶어둔 카테고리도 하기로 한 일로 친다.
    func testPairedCategoryCountsTowardFocus() {
        let observation = makeObservation(
            sessionSeconds: 1_500,
            categories: [("개발", 900), ("조사", 600)]
        )

        let score = FocusScoreCalculator.score(
            observation: observation,
            focusCategory: "개발",
            isPaired: { $0 == "개발" && $1 == "조사" }
        )

        XCTAssertEqual(score.focusSeconds, 1_500)
        XCTAssertEqual(score.value, 1.0, accuracy: 0.0001)
    }

    func testUnpairedCategoryIsExcludedFromNumerator() {
        let observation = makeObservation(
            sessionSeconds: 1_500,
            categories: [("개발", 900), ("엔터", 600)]
        )

        let score = FocusScoreCalculator.score(
            observation: observation,
            focusCategory: "개발",
            isPaired: noPairs
        )

        XCTAssertEqual(score.focusSeconds, 900)
        XCTAssertEqual(score.value, 0.6, accuracy: 0.0001)
    }

    /// 자리 비움·미기록 시간은 분모에 남아 몰입도를 깎는다. 이 설계의 핵심 약속이다.
    func testUnrecordedTimeStaysInDenominator() {
        let observation = makeObservation(
            sessionSeconds: 1_500,
            recordedSeconds: 1_200,
            categories: [("개발", 1_200)]
        )

        let score = FocusScoreCalculator.score(
            observation: observation,
            focusCategory: "개발",
            isPaired: noPairs
        )

        XCTAssertEqual(score.totalSeconds, 1_500)
        XCTAssertEqual(score.value, 0.8, accuracy: 0.0001)
    }

    /// 겹쳐서 어느 앱인지 가릴 수 없는 시간은 카테고리 목록에 없으므로 분자에서 빠지고 분모에는 남는다.
    func testAmbiguousOverlapIsNotCountedAsFocus() {
        let observation = makeObservation(
            sessionSeconds: 1_000,
            recordedSeconds: 1_000,
            ambiguousOverlapSeconds: 200,
            categories: [("개발", 800)]
        )

        let score = FocusScoreCalculator.score(
            observation: observation,
            focusCategory: "개발",
            isPaired: noPairs
        )

        XCTAssertEqual(score.value, 0.8, accuracy: 0.0001)
    }

    func testZeroLengthSessionScoresZeroWithoutCrashing() {
        let score = FocusScoreCalculator.score(
            observation: makeObservation(sessionSeconds: 0, categories: []),
            focusCategory: "개발",
            isPaired: noPairs
        )

        XCTAssertEqual(score.value, 0)
    }

    /// 사용자가 제기한 상황 — 업무 포모도로 중 매핑 안 된 엑셀로 25분 내리 일했다.
    /// 딴짓이 아니라 아직 모르는 것이므로 판정 대상에서 빠져야 한다.
    func testUnclassifiedAppMakesSessionUnmeasurable() {
        let score = FocusScoreCalculator.score(
            observation: makeObservation(
                sessionSeconds: 1_500,
                categories: [(Constants.unclassifiedAppCategory, 1_500)]
            ),
            focusCategory: "업무",
            isPaired: noPairs
        )

        XCTAssertEqual(score.measuredSeconds, 0)
        XCTAssertFalse(score.isMeasurable)
    }

    /// 미분류 시간은 분자와 분모 양쪽에서 빠진다.
    func testUnclassifiedTimeIsRemovedFromBothSides() {
        let score = FocusScoreCalculator.score(
            observation: makeObservation(
                sessionSeconds: 1_500,
                categories: [
                    ("개발", 600),
                    ("엔터", 600),
                    (Constants.unclassifiedAppCategory, 300),
                ]
            ),
            focusCategory: "개발",
            isPaired: noPairs
        )

        XCTAssertEqual(score.measuredSeconds, 1_200)
        XCTAssertTrue(score.isMeasurable)
        XCTAssertEqual(score.value, 0.5, accuracy: 0.0001)
    }

    /// 절반 이상을 알 수 있으면 판정한다. 경계값을 못 박는다.
    func testMeasurableAtExactlyHalf() {
        let score = FocusScoreCalculator.score(
            observation: makeObservation(
                sessionSeconds: 1_000,
                categories: [("개발", 500), (Constants.unclassifiedAppCategory, 500)]
            ),
            focusCategory: "개발",
            isPaired: noPairs
        )

        XCTAssertEqual(score.measuredSeconds, 500)
        XCTAssertTrue(score.isMeasurable)
    }

    /// 미기록 시간이 많아도 미분류 비율을 희석하면 안 된다. 앱으로 기록된 시간끼리만 비교한다.
    func testUnrecordedTimeDoesNotHideInsufficientAppClassification() {
        let score = FocusScoreCalculator.score(
            observation: makeObservation(
                sessionSeconds: 1_500,
                recordedSeconds: 600,
                categories: [
                    ("개발", 200),
                    (Constants.unclassifiedAppCategory, 400),
                ]
            ),
            focusCategory: "개발",
            isPaired: noPairs
        )

        XCTAssertEqual(score.classifiedAppSeconds, 200)
        XCTAssertEqual(score.recordedAppSeconds, 600)
        XCTAssertFalse(score.isMeasurable)
    }

    /// 짝 판정은 (집중 카테고리, 지금 카테고리) 순서로 넘어온다.
    func testIsPairedReceivesFocusCategoryFirst() {
        var seen: [(String, String)] = []
        _ = FocusScoreCalculator.score(
            observation: makeObservation(sessionSeconds: 600, categories: [("엔터", 600)]),
            focusCategory: "개발",
            isPaired: { lhs, rhs in
                seen.append((lhs, rhs))
                return false
            }
        )

        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen.first?.0, "개발")
        XCTAssertEqual(seen.first?.1, "엔터")
    }
}

@MainActor
final class FocusScoreHistoryTests: XCTestCase {
    func testCompletedSessionExcludesPauseAndIncludesResumedUsage() throws {
        let schema = Schema([FocusSession.self, AppUsageSegment.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let focusCategory = "일시정지-집중-\(UUID().uuidString)"
        let pausedCategory = "일시정지-제외-\(UUID().uuidString)"

        let session = FocusSession(focusMinutes: 30, breakMinutes: 5, category: focusCategory)
        session.startedAt = start
        session.recordPauseStarted(at: start.addingTimeInterval(10 * 60))
        session.recordPauseEnded(at: start.addingTimeInterval(30 * 60))
        session.endedAt = start.addingTimeInterval(50 * 60)
        session.actualFocusSeconds = 30 * 60
        session.completed = true
        context.insert(session)
        context.insert(
            AppUsageSegment(
                appName: "집중 전반",
                bundleIdentifier: "test.focus.before-pause",
                category: focusCategory,
                startTime: start,
                endTime: start.addingTimeInterval(10 * 60)
            )
        )
        context.insert(
            AppUsageSegment(
                appName: "정지 중 앱",
                bundleIdentifier: "test.pause.excluded",
                category: pausedCategory,
                startTime: start.addingTimeInterval(10 * 60),
                endTime: start.addingTimeInterval(30 * 60)
            )
        )
        context.insert(
            AppUsageSegment(
                appName: "집중 재개",
                bundleIdentifier: "test.focus.after-pause",
                category: focusCategory,
                startTime: start.addingTimeInterval(30 * 60),
                endTime: start.addingTimeInterval(50 * 60)
            )
        )
        try context.save()

        let sample = try XCTUnwrap(
            FocusScoreHistory.samples(
                days: 1,
                now: start.addingTimeInterval(60 * 60),
                modelContext: context
            ).first
        )

        XCTAssertEqual(sample.score.totalSeconds, 30 * 60)
        XCTAssertEqual(sample.score.focusSeconds, 30 * 60)
        XCTAssertEqual(sample.score.value, 1, accuracy: 0.0001)
        XCTAssertNil(sample.categorySeconds[pausedCategory])
    }

    func testLiveWindowWaitsUntilTenActiveMinutes() throws {
        let schema = Schema([FocusSession.self, AppUsageSegment.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let start = Date(timeIntervalSince1970: 1_800_100_000)

        let metrics = FocusScoreHistory.liveWindowMetrics(
            activeIntervals: [
                DateInterval(start: start, end: start.addingTimeInterval(9 * 60 + 59)),
            ],
            focusCategory: "공부",
            modelContext: container.mainContext
        )

        XCTAssertNil(metrics)
    }

    func testLiveWindowUsesOnlyTrailingTenActiveMinutes() throws {
        let schema = Schema([FocusSession.self, AppUsageSegment.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let start = Date(timeIntervalSince1970: 1_800_200_000)
        context.insert(
            AppUsageSegment(
                appName: "처음 딴짓",
                bundleIdentifier: "test.trailing.distraction",
                category: "오락",
                startTime: start,
                endTime: start.addingTimeInterval(10 * 60)
            )
        )
        context.insert(
            AppUsageSegment(
                appName: "최근 집중",
                bundleIdentifier: "test.trailing.focus",
                category: "공부",
                startTime: start.addingTimeInterval(10 * 60),
                endTime: start.addingTimeInterval(20 * 60)
            )
        )
        try context.save()

        let metrics = try XCTUnwrap(
            FocusScoreHistory.liveWindowMetrics(
                activeIntervals: [
                    DateInterval(start: start, end: start.addingTimeInterval(20 * 60)),
                ],
                focusCategory: "공부",
                modelContext: context
            )
        )

        XCTAssertEqual(metrics.score.value, 1, accuracy: 0.0001)
        XCTAssertEqual(metrics.appSwitchCount, 0)
    }

    func testLiveWindowCountsAppSwitchesInsideTheWindow() throws {
        let schema = Schema([FocusSession.self, AppUsageSegment.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let start = Date(timeIntervalSince1970: 1_800_300_000)
        let segments = [
            AppUsageSegment(
                appName: "교재",
                bundleIdentifier: "test.switch.book",
                category: "공부",
                startTime: start,
                endTime: start.addingTimeInterval(3 * 60)
            ),
            AppUsageSegment(
                appName: "검색",
                bundleIdentifier: "test.switch.search",
                category: "공부",
                startTime: start.addingTimeInterval(3 * 60),
                endTime: start.addingTimeInterval(6 * 60)
            ),
            AppUsageSegment(
                appName: "교재",
                bundleIdentifier: "test.switch.book",
                category: "공부",
                startTime: start.addingTimeInterval(6 * 60),
                endTime: start.addingTimeInterval(10 * 60)
            ),
        ]
        segments.forEach(context.insert)
        try context.save()

        let metrics = try XCTUnwrap(
            FocusScoreHistory.liveWindowMetrics(
                activeIntervals: [
                    DateInterval(start: start, end: start.addingTimeInterval(10 * 60)),
                ],
                focusCategory: "공부",
                modelContext: context
            )
        )

        XCTAssertEqual(metrics.score.value, 1, accuracy: 0.0001)
        XCTAssertEqual(metrics.appSwitchCount, 2)
    }
}

final class FocusNudgeDetectorTests: XCTestCase {
    private let rule = FocusNudgeDetectionRule(minimumFocusRatio: 0.60, maximumAppSwitches: 5)

    func testDetectsFocusRatioAndAppSwitchReasonsIndependently() {
        let focusOnly = FocusNudgeDetector.violation(
            metrics: metrics(focusRatio: 0.40, appSwitches: 2),
            rule: rule
        )
        XCTAssertNotNil(focusOnly.focusRatio)
        XCTAssertNil(focusOnly.appSwitches)

        let switchesOnly = FocusNudgeDetector.violation(
            metrics: metrics(focusRatio: 0.80, appSwitches: 6),
            rule: rule
        )
        XCTAssertNil(switchesOnly.focusRatio)
        XCTAssertNotNil(switchesOnly.appSwitches)
    }

    func testAppSwitchRuleStillWorksWhenFocusRatioIsNotMeasurable() {
        let violation = FocusNudgeDetector.violation(
            metrics: FocusNudgeWindowMetrics(
                score: FocusScore(focusSeconds: 0, measuredSeconds: 0, totalSeconds: 600),
                appSwitchCount: 7
            ),
            rule: rule
        )

        XCTAssertNil(violation.focusRatio)
        XCTAssertNotNil(violation.appSwitches)
    }

    func testContinuingViolationDoesNotRepeatUntilRecovery() {
        let violation = FocusNudgeDetector.violation(
            metrics: metrics(focusRatio: 0.30, appSwitches: 2),
            rule: rule
        )

        XCTAssertTrue(
            FocusNudgeDetector.shouldNudge(
                isFocusing: true,
                violation: violation,
                isViolationLatched: false,
                nudgeCount: 1,
                maximumNudgesPerSession: 2
            )
        )
        XCTAssertFalse(
            FocusNudgeDetector.shouldNudge(
                isFocusing: true,
                violation: violation,
                isViolationLatched: true,
                nudgeCount: 1,
                maximumNudgesPerSession: 2
            )
        )
    }

    func testLimitedAndUnlimitedFrequencyPolicies() {
        let violation = FocusNudgeDetector.violation(
            metrics: metrics(focusRatio: 0.30, appSwitches: 2),
            rule: rule
        )
        XCTAssertFalse(
            FocusNudgeDetector.shouldNudge(
                isFocusing: true,
                violation: violation,
                isViolationLatched: false,
                nudgeCount: 2,
                maximumNudgesPerSession: 2
            )
        )
        XCTAssertTrue(
            FocusNudgeDetector.shouldNudge(
                isFocusing: true,
                violation: violation,
                isViolationLatched: false,
                nudgeCount: 20,
                maximumNudgesPerSession: nil
            )
        )
    }

    private func metrics(focusRatio: Double, appSwitches: Int) -> FocusNudgeWindowMetrics {
        FocusNudgeWindowMetrics(
            score: FocusScore(
                focusSeconds: Int(600 * focusRatio),
                measuredSeconds: 600,
                totalSeconds: 600
            ),
            appSwitchCount: appSwitches
        )
    }
}

@MainActor
final class FocusScoreMonitorTests: XCTestCase {
    private let settingKeys = [
        Constants.AppStorageKey.companionFocusNudgeEnabled,
        Constants.AppStorageKey.companionFocusNudgeDetectionMode,
        Constants.AppStorageKey.companionFocusNudgeManualFocusPercent,
        Constants.AppStorageKey.companionFocusNudgeManualMaxAppSwitches,
        Constants.AppStorageKey.companionFocusNudgeFrequencyMode,
        Constants.AppStorageKey.companionFocusNudgeMaximumPerSession,
        Constants.AppStorageKey.companionFocusNudgePendingEvents,
        Constants.AppStorageKey.companionFocusNudgeSessionState,
    ]
    private nonisolated(unsafe) var savedSettings: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        savedSettings = Dictionary(uniqueKeysWithValues: settingKeys.compactMap { key in
            defaults.object(forKey: key).map { (key, $0) }
        })
        defaults.set(true, forKey: Constants.AppStorageKey.companionFocusNudgeEnabled)
        defaults.set(
            FocusNudgeDetectionMode.ruleBased.rawValue,
            forKey: Constants.AppStorageKey.companionFocusNudgeDetectionMode
        )
        defaults.set(60, forKey: Constants.AppStorageKey.companionFocusNudgeManualFocusPercent)
        defaults.set(100, forKey: Constants.AppStorageKey.companionFocusNudgeManualMaxAppSwitches)
        defaults.set(
            FocusNudgeFrequencyMode.limited.rawValue,
            forKey: Constants.AppStorageKey.companionFocusNudgeFrequencyMode
        )
        defaults.set(2, forKey: Constants.AppStorageKey.companionFocusNudgeMaximumPerSession)
        defaults.removeObject(forKey: Constants.AppStorageKey.companionFocusNudgePendingEvents)
        defaults.removeObject(forKey: Constants.AppStorageKey.companionFocusNudgeSessionState)
    }

    override func tearDown() {
        let defaults = UserDefaults.standard
        for key in settingKeys {
            if let value = savedSettings[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        super.tearDown()
    }

    func testWaitsForFullTenMinuteWindowAndRecordsExplainedNudge() throws {
        let (container, context, appState, monitor, messages) = try makeMonitor()
        let start = Date(timeIntervalSince1970: 1_810_000_000)
        let session = FocusSession(focusMinutes: 30, breakMinutes: 5, category: "공부")
        session.startedAt = start
        context.insert(session)
        context.insert(segment("딴짓", "오락", start, start.addingTimeInterval(10 * 60)))
        try context.save()

        appState.remainingSeconds = 21 * 60
        monitor.poll(at: start.addingTimeInterval(9 * 60))
        XCTAssertTrue(messages().isEmpty)

        appState.remainingSeconds = 20 * 60
        monitor.poll(at: start.addingTimeInterval(10 * 60))

        XCTAssertEqual(messages().count, 1)
        XCTAssertTrue(messages()[0].contains("최근 10분 몰입 시간이 0%"))
        XCTAssertTrue(messages()[0].contains("설정 기준 60%"))
        let event = try XCTUnwrap(context.fetch(FetchDescriptor<FocusNudgeEvent>()).first)
        XCTAssertEqual(event.focusSessionID, session.id)
        XCTAssertEqual(event.observedFocusRatio, 0)
        XCTAssertEqual(event.minimumFocusRatio, 0.60)
        _ = container
    }

    func testSameViolationDoesNotRepeatButRecoveryRearmsUpToLimit() throws {
        let (_, context, appState, monitor, messages) = try makeMonitor()
        let start = Date(timeIntervalSince1970: 1_810_100_000)
        let session = FocusSession(focusMinutes: 50, breakMinutes: 5, category: "공부")
        session.startedAt = start
        context.insert(session)
        context.insert(segment("딴짓1", "오락", start, start.addingTimeInterval(10 * 60)))
        context.insert(segment("집중", "공부", start.addingTimeInterval(10 * 60), start.addingTimeInterval(20 * 60)))
        context.insert(segment("딴짓2", "오락", start.addingTimeInterval(20 * 60), start.addingTimeInterval(30 * 60)))
        context.insert(segment("다시 집중", "공부", start.addingTimeInterval(30 * 60), start.addingTimeInterval(40 * 60)))
        context.insert(segment("딴짓3", "오락", start.addingTimeInterval(40 * 60), start.addingTimeInterval(50 * 60)))
        try context.save()

        appState.remainingSeconds = 40 * 60
        monitor.poll(at: start.addingTimeInterval(10 * 60))
        appState.remainingSeconds = 39 * 60
        monitor.poll(at: start.addingTimeInterval(11 * 60))
        XCTAssertEqual(messages().count, 1)

        appState.remainingSeconds = 30 * 60
        monitor.poll(at: start.addingTimeInterval(20 * 60))
        appState.remainingSeconds = 20 * 60
        monitor.poll(at: start.addingTimeInterval(30 * 60))
        XCTAssertEqual(messages().count, 2)

        // 정상 창을 다시 확인해도 세션 상한 2회에 도달했으므로 세 번째는 나오지 않는다.
        appState.remainingSeconds = 10 * 60
        monitor.poll(at: start.addingTimeInterval(40 * 60))
        appState.remainingSeconds = 0
        monitor.poll(at: start.addingTimeInterval(50 * 60))
        XCTAssertEqual(messages().count, 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FocusNudgeEvent>()), 2)
    }

    func testPauseDoesNotFillRecentTenMinuteWindow() throws {
        let (_, context, appState, monitor, messages) = try makeMonitor()
        let start = Date(timeIntervalSince1970: 1_810_200_000)
        let now = start.addingTimeInterval(20 * 60)
        let session = FocusSession(focusMinutes: 30, breakMinutes: 5, category: "공부")
        session.startedAt = start
        session.recordPauseStarted(at: start.addingTimeInterval(5 * 60))
        session.recordPauseEnded(at: now)
        context.insert(session)
        context.insert(segment("딴짓", "오락", start, start.addingTimeInterval(5 * 60)))
        try context.save()

        appState.remainingSeconds = 25 * 60
        monitor.poll(at: now)

        XCTAssertTrue(messages().isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FocusNudgeEvent>()), 0)
    }

    func testRecoveryBeforeMonitorRestartAllowsTheNextViolation() throws {
        let (container, context, appState, firstMonitor, messages) = try makeMonitor()
        let start = Date(timeIntervalSince1970: 1_810_300_000)
        let session = FocusSession(focusMinutes: 30, breakMinutes: 5, category: "공부")
        session.startedAt = start
        context.insert(session)
        context.insert(segment("딴짓1", "오락", start, start.addingTimeInterval(10 * 60)))
        context.insert(segment("집중", "공부", start.addingTimeInterval(10 * 60), start.addingTimeInterval(20 * 60)))
        context.insert(segment("딴짓2", "오락", start.addingTimeInterval(20 * 60), start.addingTimeInterval(30 * 60)))
        try context.save()

        appState.remainingSeconds = 20 * 60
        firstMonitor.poll(at: start.addingTimeInterval(10 * 60))
        appState.remainingSeconds = 10 * 60
        firstMonitor.poll(at: start.addingTimeInterval(20 * 60))

        let restartedMonitor = FocusScoreMonitor(
            appState: appState,
            modelContainer: container
        ) { message in
            _ = message
            return true
        }
        appState.remainingSeconds = 0
        restartedMonitor.poll(at: start.addingTimeInterval(30 * 60))

        XCTAssertEqual(messages().count, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FocusNudgeEvent>()), 2)
    }

    func testMonitorRestartDoesNotRepeatAnOngoingViolation() throws {
        let (container, context, appState, firstMonitor, _) = try makeMonitor()
        let start = Date(timeIntervalSince1970: 1_810_400_000)
        let session = FocusSession(focusMinutes: 30, breakMinutes: 5, category: "공부")
        session.startedAt = start
        context.insert(session)
        context.insert(segment("계속 딴짓", "오락", start, start.addingTimeInterval(11 * 60)))
        try context.save()

        appState.remainingSeconds = 20 * 60
        firstMonitor.poll(at: start.addingTimeInterval(10 * 60))

        let restartedMonitor = FocusScoreMonitor(
            appState: appState,
            modelContainer: container
        ) { _ in true }
        appState.remainingSeconds = 19 * 60
        restartedMonitor.poll(at: start.addingTimeInterval(11 * 60))

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FocusNudgeEvent>()), 1)
    }

    private func makeMonitor() throws -> (
        ModelContainer,
        ModelContext,
        AppState,
        FocusScoreMonitor,
        () -> [String]
    ) {
        let schema = Schema([FocusSession.self, AppUsageSegment.self, FocusNudgeEvent.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let appState = AppState()
        appState.timerState = .focusing
        var deliveredMessages: [String] = []
        let monitor = FocusScoreMonitor(appState: appState, modelContainer: container) { message in
            deliveredMessages.append(message)
            return true
        }
        return (container, context, appState, monitor, { deliveredMessages })
    }

    private func segment(
        _ app: String,
        _ category: String,
        _ start: Date,
        _ end: Date
    ) -> AppUsageSegment {
        AppUsageSegment(
            appName: app,
            bundleIdentifier: "test.\(app)",
            category: category,
            startTime: start,
            endTime: end
        )
    }

}

final class FocusScoreMessagesTests: XCTestCase {
    func testParseDropsBlankLinesAndTrims() {
        let parsed = FocusScoreMessages.parse("  정신 차리자  \n\n\t\n지금 이거 할 때야?\n   ")

        XCTAssertEqual(parsed, ["정신 차리자", "지금 이거 할 때야?"])
    }

    func testFallsBackToDefaultMessagesWhenNothingRegistered() {
        XCTAssertEqual(
            FocusScoreMessages.next(from: [], previous: nil),
            FocusScoreMessages.fallback[0]
        )
    }

    /// 같은 말이 연달아 나오면 잔소리로 들린다.
    func testRotatesPastThePreviousMessage() {
        let messages = ["첫째", "둘째", "셋째"]

        XCTAssertEqual(FocusScoreMessages.next(from: messages, previous: "첫째"), "둘째")
        XCTAssertEqual(FocusScoreMessages.next(from: messages, previous: "셋째"), "첫째")
    }

    func testRepeatsWhenOnlyOneMessageRegistered() {
        XCTAssertEqual(FocusScoreMessages.next(from: ["하나뿐"], previous: "하나뿐"), "하나뿐")
    }

    /// 설정을 고쳐 직전 문구가 목록에서 사라져도 멈추지 않는다.
    func testStartsOverWhenPreviousMessageIsGone() {
        XCTAssertEqual(
            FocusScoreMessages.next(from: ["첫째", "둘째"], previous: "지워진 문구"),
            "첫째"
        )
    }
}

final class FocusNudgeSettingsStoreTests: XCTestCase {
    func testSnapshotUsesManualRuleAndFrequencySettings() {
        let suite = "FocusNudgeSettingsStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(75, forKey: Constants.AppStorageKey.companionFocusNudgeManualFocusPercent)
        defaults.set(9, forKey: Constants.AppStorageKey.companionFocusNudgeManualMaxAppSwitches)
        defaults.set(
            FocusNudgeFrequencyMode.unlimited.rawValue,
            forKey: Constants.AppStorageKey.companionFocusNudgeFrequencyMode
        )

        let settings = FocusNudgeSettingsStore.snapshot(defaults: defaults)

        XCTAssertEqual(settings.manualRule.minimumFocusRatio, 0.75, accuracy: 0.0001)
        XCTAssertEqual(settings.manualRule.maximumAppSwitches, 9)
        XCTAssertNil(settings.configuredMaximumNudges)
    }

    func testReadyPersonalizationIsUsedAutomatically() {
        let personalizedRule = FocusNudgeDetectionRule(
            minimumFocusRatio: 0.70,
            maximumAppSwitches: 4
        )
        let ready = FocusPersonalizationAnalysis(
            requiredFeedbackCount: 20,
            focusedFeedbackCount: 20,
            distractedFeedbackCount: 20,
            suggestedRule: personalizedRule,
            evidence: FocusPersonalizationEvidence(
                focusedAverageFocusRatio: 0.80,
                distractedAverageFocusRatio: 0.30,
                focusedAverageAppSwitches: 2,
                distractedAverageAppSwitches: 8,
                maximumObservedAppSwitches: 8
            )
        )
        let settings = FocusNudgeSettingsSnapshot(
            detectionMode: .personalized,
            requiredFeedbackCount: 20,
            manualRule: FocusNudgeDetectionRule(
                minimumFocusRatio: 0.60,
                maximumAppSwitches: 6
            ),
            frequencyMode: .limited,
            maximumNudgesPerSession: 2
        )

        let policy = FocusNudgePolicyResolver.resolve(
            settings: settings,
            personalization: ready
        )

        XCTAssertEqual(policy.source, .personalized)
        XCTAssertEqual(policy.rule, personalizedRule)
    }

    func testPersonalizedModeUsesManualRuleUntilFeedbackIsReady() {
        let manualRule = FocusNudgeDetectionRule(
            minimumFocusRatio: 0.55,
            maximumAppSwitches: 7
        )
        let settings = FocusNudgeSettingsSnapshot(
            detectionMode: .personalized,
            requiredFeedbackCount: 20,
            manualRule: manualRule,
            frequencyMode: .limited,
            maximumNudgesPerSession: 2
        )
        let learning = FocusPersonalizationAnalysis(
            requiredFeedbackCount: 20,
            focusedFeedbackCount: 7,
            distractedFeedbackCount: 5,
            suggestedRule: nil,
            evidence: FocusPersonalizationEvidence(
                focusedAverageFocusRatio: 0.80,
                distractedAverageFocusRatio: 0.45,
                focusedAverageAppSwitches: 2,
                distractedAverageAppSwitches: 7,
                maximumObservedAppSwitches: 7
            )
        )

        let policy = FocusNudgePolicyResolver.resolve(
            settings: settings,
            personalization: learning
        )

        XCTAssertEqual(policy.source, .ruleBased)
        XCTAssertEqual(policy.rule, manualRule)
    }
}

final class FocusPersonalizationLearnerTests: XCTestCase {
    func testWaitsForRequiredCountAndBothFeedbackGroups() {
        let tooFew = FocusPersonalizationLearner.analyze(
            samples: Array(repeating: sample(.focused, 0.8, 2), count: 9)
                + Array(repeating: sample(.distracted, 0.3, 8), count: 10),
            requiredFeedbackCount: 10
        )
        XCTAssertFalse(tooFew.isReady)
        XCTAssertEqual(tooFew.focusedFeedbackCount, 9)
        XCTAssertEqual(tooFew.distractedFeedbackCount, 10)

        let oneSided = FocusPersonalizationLearner.analyze(
            samples: Array(repeating: sample(.focused, 0.8, 2), count: 10),
            requiredFeedbackCount: 10
        )
        XCTAssertFalse(oneSided.isReady)
        XCTAssertFalse(oneSided.hasEnoughFeedback)
    }

    func testFindsExplainableFocusAndSwitchBoundaries() throws {
        let focused = Array(repeating: sample(.focused, 0.80, 2), count: 10)
        let distracted = Array(repeating: sample(.distracted, 0.30, 8), count: 10)

        let analysis = FocusPersonalizationLearner.analyze(
            samples: focused + distracted,
            requiredFeedbackCount: 10
        )

        let rule = try XCTUnwrap(analysis.suggestedRule)
        XCTAssertTrue(analysis.isReady)
        XCTAssertEqual(analysis.focusedFeedbackCount, 10)
        XCTAssertEqual(analysis.distractedFeedbackCount, 10)
        XCTAssertGreaterThan(rule.minimumFocusRatio, 0.30)
        XCTAssertLessThanOrEqual(rule.minimumFocusRatio, 0.80)
        XCTAssertGreaterThanOrEqual(rule.maximumAppSwitches, 2)
        XCTAssertLessThan(rule.maximumAppSwitches, 8)
    }

    func testSelectsTheRecentLimitIndependentlyForEachFeedbackGroup() throws {
        let recentFocused = Array(repeating: sample(.focused, 0.80, 2), count: 10)
        let olderDistracted = Array(repeating: sample(.distracted, 0.30, 8), count: 10)
        let oldestFocused = Array(repeating: sample(.focused, 0.10, 20), count: 4)

        let analysis = FocusPersonalizationLearner.analyze(
            samples: recentFocused + olderDistracted + oldestFocused,
            requiredFeedbackCount: 10
        )

        XCTAssertTrue(analysis.isReady)
        XCTAssertEqual(analysis.focusedFeedbackCount, 10)
        XCTAssertEqual(analysis.distractedFeedbackCount, 10)
        XCTAssertEqual(
            try XCTUnwrap(analysis.evidence.focusedAverageFocusRatio),
            0.80,
            accuracy: 0.0001
        )
    }

    private func sample(
        _ label: FocusPersonalizationLabel,
        _ focusRatio: Double,
        _ appSwitches: Int
    ) -> FocusPersonalizationSample {
        FocusPersonalizationSample(
            label: label,
            minimumFocusRatio: focusRatio,
            maximumAppSwitches: appSwitches
        )
    }
}

@MainActor
final class FocusPersonalizationTrainerTests: XCTestCase {
    func testBuildsRuleFromRecentCompletedReflectionsAndTenMinuteWindows() throws {
        let schema = Schema([
            FocusSession.self,
            AppUsageSegment.self,
            PomodoroReflection.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let base = Date(timeIntervalSince1970: 1_811_000_000)

        for index in 0..<20 {
            let start = base.addingTimeInterval(TimeInterval(index * 20 * 60))
            let session = FocusSession(focusMinutes: 10, breakMinutes: 5, category: "공부")
            session.startedAt = start
            session.endedAt = start.addingTimeInterval(10 * 60)
            session.actualFocusSeconds = 10 * 60
            session.completed = true
            context.insert(session)

            // 최근 10개가 모두 집중 잘함이어도 더 과거의 흐트러짐 10개를 따로 가져와야 한다.
            let isFocused = index >= 10
            if isFocused {
                context.insert(
                    AppUsageSegment(
                        appName: "교재",
                        bundleIdentifier: "test.personalization.book",
                        category: "공부",
                        startTime: start,
                        endTime: start.addingTimeInterval(10 * 60)
                    )
                )
            } else {
                for minute in 0..<10 {
                    context.insert(
                        AppUsageSegment(
                            appName: "딴짓\(minute % 2)",
                            bundleIdentifier: "test.personalization.distraction.\(minute % 2)",
                            category: "오락",
                            startTime: start.addingTimeInterval(TimeInterval(minute * 60)),
                            endTime: start.addingTimeInterval(TimeInterval((minute + 1) * 60))
                        )
                    )
                }
            }
            context.insert(
                PomodoroReflection(
                    focusSessionID: session.id,
                    focusExperience: isFocused ? .mostlyFocused : .frequentlyDistracted,
                    progressResult: .completedAsPlanned,
                    answeredAt: session.endedAt ?? start
                )
            )
        }
        try context.save()

        let analysis = FocusPersonalizationTrainer.analyze(
            requiredFeedbackCount: 10,
            modelContext: context
        )

        XCTAssertTrue(analysis.isReady)
        XCTAssertEqual(analysis.focusedFeedbackCount, 10)
        XCTAssertEqual(analysis.distractedFeedbackCount, 10)
        XCTAssertNotNil(analysis.suggestedRule)
    }
}

final class FocusPairSuggesterTests: XCTestCase {
    private func makeSample(
        category: String,
        score: Double,
        categorySeconds: [String: Int],
        startedAt: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> FocusScoreSample {
        FocusScoreSample(
            id: UUID(),
            startedAt: startedAt,
            category: category,
            score: FocusScore(focusSeconds: Int(1_500 * score), measuredSeconds: 1_500, totalSeconds: 1_500),
            categorySeconds: categorySeconds
        )
    }

    /// 실제 사용자 데이터에서 나온 상황 — 공부로 포모도로를 걸고 에디터로 공부한다.
    /// 딴짓이 아니므로 판정 기준을 느슨하게 할 게 아니라 짝으로 묶어야 한다.
    func testSuggestsDominantOtherCategory() {
        let samples = [
            makeSample(category: "공부", score: 0, categorySeconds: ["개발": 1_260, "기록": 120]),
            makeSample(category: "공부", score: 0, categorySeconds: ["개발": 1_200, "기타": 100]),
        ]

        let suggestion = FocusPairSuggester.suggestion(
            category: "공부",
            samples: samples,
            isPaired: { _, _ in false }
        )

        XCTAssertEqual(suggestion?.partner, "개발")
        XCTAssertEqual(suggestion?.share ?? 0, 0.91, accuracy: 0.02)
    }

    func testDoesNotSuggestAlreadyPairedCategory() {
        let samples = [makeSample(category: "공부", score: 0, categorySeconds: ["개발": 1_400])]

        XCTAssertNil(
            FocusPairSuggester.suggestion(
                category: "공부",
                samples: samples,
                isPaired: { $0 == "공부" && $1 == "개발" }
            )
        )
    }

    /// 잠깐 스친 카테고리까지 짝으로 묶자고 하면 제안이 잔소리가 된다.
    func testDoesNotSuggestBelowMinimumShare() {
        let samples = [makeSample(category: "개발", score: 0.9, categorySeconds: ["개발": 1_400, "소통": 100])]

        XCTAssertNil(
            FocusPairSuggester.suggestion(
                category: "개발",
                samples: samples,
                isPaired: { _, _ in false }
            )
        )
    }

    func testIgnoresOtherCategoriesSessions() {
        let samples = [
            makeSample(category: "공부", score: 0, categorySeconds: ["개발": 1_400]),
            makeSample(category: "기록", score: 0, categorySeconds: ["소통": 1_400]),
        ]

        XCTAssertEqual(
            FocusPairSuggester.suggestion(
                category: "공부", samples: samples, isPaired: { _, _ in false }
            )?.partner,
            "개발"
        )
    }

    /// 미분류를 짝으로 묶으면 앞으로 매핑 안 된 앱이 전부 몰입으로 계산된다.
    /// 짝 편집 화면이 막는 것을 자동 제안이 우회하면 안 된다.
    func testNeverSuggestsReservedCategories() {
        let samples = [
            makeSample(
                category: "업무",
                score: 0,
                categorySeconds: [Constants.unclassifiedAppCategory: 1_400]
            ),
        ]

        XCTAssertNil(
            FocusPairSuggester.suggestion(
                category: "업무", samples: samples, isPaired: { _, _ in false }
            )
        )
    }

    func testReturnsNilWithoutSamples() {
        XCTAssertNil(
            FocusPairSuggester.suggestion(category: "개발", samples: [], isPaired: { _, _ in false })
        )
    }

    /// 전체 보기에서도 가장 크게 어긋난 카테고리를 짚어줘야 원인을 찾을 수 있다.
    func testStrongestSuggestionPicksMostMismatchedCategory() {
        let samples = [
            // 공부는 거의 전부 개발 앱 — 가장 크게 어긋났다.
            makeSample(category: "공부", score: 0, categorySeconds: ["개발": 1_500]),
            // 개발은 조금만 새고 있다.
            makeSample(category: "개발", score: 0.75, categorySeconds: ["개발": 1_125, "엔터": 375]),
        ]

        let suggestion = FocusPairSuggester.strongestSuggestion(
            samples: samples,
            isPaired: { _, _ in false }
        )

        XCTAssertEqual(suggestion?.category, "공부")
        XCTAssertEqual(suggestion?.partner, "개발")
    }

    func testStrongestSuggestionIsNilWhenNothingMismatches() {
        let samples = [makeSample(category: "개발", score: 1, categorySeconds: ["개발": 1_500])]

        XCTAssertNil(
            FocusPairSuggester.strongestSuggestion(samples: samples, isPaired: { _, _ in false })
        )
    }
}

final class FocusTrendBuilderTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }

    private let weekOne = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeSample(category: String, score: Double, at date: Date) -> FocusScoreSample {
        FocusScoreSample(
            id: UUID(),
            startedAt: date,
            category: category,
            score: FocusScore(focusSeconds: Int(1_500 * score), measuredSeconds: 1_500, totalSeconds: 1_500),
            categorySeconds: [:]
        )
    }

    func testCountsNudgesIntoTheirWeek() {
        let nextWeek = weekOne.addingTimeInterval(8 * 86_400)
        let weeks = FocusTrendBuilder.weeks(
            samples: [
                makeSample(category: "개발", score: 0.9, at: weekOne),
                makeSample(category: "개발", score: 0.9, at: nextWeek),
            ],
            nudgeDates: [weekOne, weekOne, nextWeek],
            calendar: calendar
        )

        XCTAssertEqual(weeks.count, 2)
        XCTAssertEqual(weeks[0].nudgeCount, 2)
        XCTAssertEqual(weeks[1].nudgeCount, 1)
    }

    func testIncludesAWeekThatOnlyHasAnActualNudge() {
        let nextWeek = weekOne.addingTimeInterval(8 * 86_400)
        let weeks = FocusTrendBuilder.weeks(
            samples: [makeSample(category: "개발", score: 0.9, at: weekOne)],
            nudgeDates: [nextWeek],
            calendar: calendar
        )

        XCTAssertEqual(weeks.count, 2)
        XCTAssertEqual(weeks[1].nudgeCount, 1)
    }

    /// 세션도 잔소리도 없었던 주는 추세에서 제외한다.
    func testSkipsWeeksWithoutActivity() {
        let threeWeeksLater = weekOne.addingTimeInterval(21 * 86_400)
        let weeks = FocusTrendBuilder.weeks(
            samples: [
                makeSample(category: "개발", score: 0.9, at: weekOne),
                makeSample(category: "개발", score: 0.9, at: threeWeeksLater),
            ],
            nudgeDates: [],
            calendar: calendar
        )

        XCTAssertEqual(weeks.count, 2)
    }

    func testCategoryWeeksAveragePerCategory() {
        let points = FocusTrendBuilder.categoryWeeks(
            samples: [
                makeSample(category: "개발", score: 0.80, at: weekOne),
                makeSample(category: "개발", score: 0.60, at: weekOne),
                makeSample(category: "공부", score: 0.20, at: weekOne),
            ],
            calendar: calendar
        )

        XCTAssertEqual(points.count, 2)
        let dev = points.first { $0.category == "개발" }
        XCTAssertEqual(dev?.meanScore ?? 0, 0.70, accuracy: 0.0001)
    }

    func testCategoryWeeksExcludeUnmeasurableSessionsFromAverage() {
        let measurable = makeSample(category: "개발", score: 0.80, at: weekOne)
        let unmeasurable = FocusScoreSample(
            id: UUID(),
            startedAt: weekOne.addingTimeInterval(60),
            category: "개발",
            score: FocusScore(
                focusSeconds: 0,
                measuredSeconds: 0,
                totalSeconds: 1_500,
                classifiedAppSeconds: 0,
                recordedAppSeconds: 1_500
            ),
            categorySeconds: [:]
        )

        let points = FocusTrendBuilder.categoryWeeks(
            samples: [measurable, unmeasurable],
            calendar: calendar
        )

        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].meanScore, 0.80, accuracy: 0.0001)
    }

    func testCategoryWeeksOmitAWeekWithOnlyUnmeasurableSessions() {
        let sample = FocusScoreSample(
            id: UUID(),
            startedAt: weekOne,
            category: "개발",
            score: FocusScore(
                focusSeconds: 0,
                measuredSeconds: 0,
                totalSeconds: 1_500,
                classifiedAppSeconds: 0,
                recordedAppSeconds: 1_500
            ),
            categorySeconds: [:]
        )

        XCTAssertTrue(
            FocusTrendBuilder.categoryWeeks(samples: [sample], calendar: calendar).isEmpty
        )
    }
}

@MainActor
final class UnclassifiedAppAssessmentTests: XCTestCase {
    func testRequiresFollowUpWhenMoreThanHalfOfRecordedAppTimeIsUnclassified() throws {
        let (container, context) = try makeContext()
        let start = Date(timeIntervalSince1970: 1_812_000_000)
        context.insert(segment("미분류 IDE", Constants.unclassifiedAppCategory, start, 6 * 60))
        context.insert(segment("교재", "공부", start.addingTimeInterval(6 * 60), 4 * 60))
        try context.save()

        let assessment = AppClassificationService.unclassifiedAssessment(
            activeIntervals: [DateInterval(start: start, end: start.addingTimeInterval(10 * 60))],
            modelContext: context
        )

        XCTAssertTrue(assessment.needsClassificationFollowUp)
        XCTAssertEqual(assessment.recordedAppSeconds, 10 * 60)
        XCTAssertEqual(assessment.unclassifiedAppSeconds, 6 * 60)
        XCTAssertEqual(assessment.unclassifiedRatio, 0.60, accuracy: 0.0001)
        XCTAssertEqual(assessment.apps.map(\.appName), ["미분류 IDE"])
        _ = container
    }

    func testDoesNotRequireFollowUpAtExactlyHalfUnclassified() throws {
        let (container, context) = try makeContext()
        let start = Date(timeIntervalSince1970: 1_812_100_000)
        context.insert(segment("미분류 IDE", Constants.unclassifiedAppCategory, start, 5 * 60))
        context.insert(segment("교재", "공부", start.addingTimeInterval(5 * 60), 5 * 60))
        try context.save()

        let assessment = AppClassificationService.unclassifiedAssessment(
            activeIntervals: [DateInterval(start: start, end: start.addingTimeInterval(10 * 60))],
            modelContext: context
        )

        XCTAssertFalse(assessment.needsClassificationFollowUp)
        _ = container
    }

    func testPauseUsageIsExcludedFromAssessment() throws {
        let (container, context) = try makeContext()
        let start = Date(timeIntervalSince1970: 1_812_200_000)
        context.insert(segment("집중 전", "공부", start, 5 * 60))
        context.insert(
            segment(
                "정지 중 미분류",
                Constants.unclassifiedAppCategory,
                start.addingTimeInterval(5 * 60),
                10 * 60
            )
        )
        context.insert(segment("집중 후", "공부", start.addingTimeInterval(15 * 60), 5 * 60))
        try context.save()

        let assessment = AppClassificationService.unclassifiedAssessment(
            activeIntervals: [
                DateInterval(start: start, end: start.addingTimeInterval(5 * 60)),
                DateInterval(
                    start: start.addingTimeInterval(15 * 60),
                    end: start.addingTimeInterval(20 * 60)
                ),
            ],
            modelContext: context
        )

        XCTAssertEqual(assessment.recordedAppSeconds, 10 * 60)
        XCTAssertEqual(assessment.unclassifiedAppSeconds, 0)
        XCTAssertFalse(assessment.needsClassificationFollowUp)
        XCTAssertTrue(assessment.apps.isEmpty)
        _ = container
    }

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([AppCategoryRule.self, AppUsageSegment.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return (container, container.mainContext)
    }

    private func segment(
        _ appName: String,
        _ category: String,
        _ start: Date,
        _ duration: TimeInterval
    ) -> AppUsageSegment {
        AppUsageSegment(
            appName: appName,
            bundleIdentifier: "test.assessment.\(appName)",
            category: category,
            startTime: start,
            endTime: start.addingTimeInterval(duration)
        )
    }
}

/// 기록 그래프와 실시간 10분 창이 같은 관측 규칙을 사용해야 결과를 비교할 수 있다.
/// 실제 세그먼트를 관측 빌더에 통과시켜 그 계약을 못 박는다.
final class FocusScoreParityTests: XCTestCase {
    func testSegmentsProduceSameScoreThroughObservationBuilder() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(1_500)   // 25분
        let segments = [
            AppUsageSegment(
                appName: "Xcode",
                bundleIdentifier: "com.apple.dt.Xcode",
                category: "개발",
                startTime: start,
                endTime: start.addingTimeInterval(900)
            ),
            AppUsageSegment(
                appName: "YouTube",
                bundleIdentifier: "com.google.Chrome.website.youtube.com",
                category: "엔터",
                startTime: start.addingTimeInterval(900),
                endTime: start.addingTimeInterval(1_200)
            ),
            // 마지막 5분은 기록이 없다 — 자리를 비운 시간으로 분모에만 남는다.
        ]

        let observation = PomodoroSessionObservationBuilder.observation(
            from: start,
            to: end,
            segments: segments
        )
        let score = FocusScoreCalculator.score(
            observation: observation,
            focusCategory: "개발",
            isPaired: { _, _ in false }
        )

        XCTAssertEqual(score.focusSeconds, 900)
        XCTAssertEqual(score.totalSeconds, 1_500)
        XCTAssertEqual(score.value, 0.6, accuracy: 0.0001)
    }
}
