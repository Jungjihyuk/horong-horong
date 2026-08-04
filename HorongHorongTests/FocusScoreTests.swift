import XCTest
@testable import 호롱호롱

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

final class FocusScoreThresholdTests: XCTestCase {
    func testDefaultWithoutHistoryIsFallback() {
        XCTAssertEqual(FocusScoreThreshold.percentileDefault([]), FocusScoreThreshold.fallback)
    }

    /// 하위 25% 지점(nearest-rank). 8개면 두 번째로 낮은 값.
    func testPercentileDefaultPicksLowerQuartile() {
        let scores = [0.90, 0.30, 0.75, 0.55, 0.80, 0.40, 0.65, 0.70]

        XCTAssertEqual(FocusScoreThreshold.percentileDefault(scores), 0.40, accuracy: 0.0001)
    }

    func testPercentileDefaultWithSingleSampleUsesThatSample() {
        XCTAssertEqual(FocusScoreThreshold.percentileDefault([0.42]), 0.42, accuracy: 0.0001)
    }

    /// 선이 그래프 밖으로 나가면 다시 잡을 수 없다.
    func testClampedKeepsLineGrabbable() {
        XCTAssertEqual(FocusScoreThreshold.clamped(-1), 0.05, accuracy: 0.0001)
        XCTAssertEqual(FocusScoreThreshold.clamped(2), 0.95, accuracy: 0.0001)
        XCTAssertEqual(FocusScoreThreshold.clamped(0.5), 0.5, accuracy: 0.0001)
    }

    func testPercentileDefaultIsClamped() {
        XCTAssertEqual(FocusScoreThreshold.percentileDefault([0.0, 0.0, 0.0]), 0.05, accuracy: 0.0001)
    }

    /// 선 위에 정확히 걸친 세션은 걸린 것으로 세지 않는다.
    func testBelowCountIsStrict() {
        let scores = [0.50, 0.60, 0.70]

        XCTAssertEqual(FocusScoreThreshold.belowCount(scores, threshold: 0.60), 1)
        XCTAssertEqual(FocusScoreThreshold.belowCount(scores, threshold: 0.71), 3)
        XCTAssertEqual(FocusScoreThreshold.belowCount(scores, threshold: 0.50), 0)
    }
}

final class FocusScoreDetectorTests: XCTestCase {
    private func makeInput(
        isFocusing: Bool = true,
        elapsedSeconds: TimeInterval = 10 * 60,
        score: Double = 0.30,
        threshold: Double = 0.60,
        hasNudgedThisSession: Bool = false
    ) -> FocusScoreNudgeInput {
        FocusScoreNudgeInput(
            isFocusing: isFocusing,
            elapsedSeconds: elapsedSeconds,
            score: score,
            threshold: threshold,
            hasNudgedThisSession: hasNudgedThisSession
        )
    }

    func testNudgesWhenScoreFallsBelowThresholdAfterWarmUp() {
        XCTAssertTrue(FocusScoreDetector.shouldNudge(makeInput()))
    }

    /// 세션 초반에는 분모가 작아 앱 하나만 잘못 잡아도 0% 라 무조건 튀어나온다.
    func testDoesNotNudgeDuringWarmUp() {
        XCTAssertFalse(FocusScoreDetector.shouldNudge(makeInput(elapsedSeconds: 4 * 60)))
        XCTAssertTrue(FocusScoreDetector.shouldNudge(makeInput(elapsedSeconds: 5 * 60)))
    }

    func testDoesNotNudgeAtOrAboveThreshold() {
        XCTAssertFalse(FocusScoreDetector.shouldNudge(makeInput(score: 0.60)))
        XCTAssertFalse(FocusScoreDetector.shouldNudge(makeInput(score: 0.85)))
    }

    func testDoesNotNudgeTwiceInOneSession() {
        XCTAssertFalse(FocusScoreDetector.shouldNudge(makeInput(hasNudgedThisSession: true)))
    }

    func testDoesNotNudgeWhenNotFocusing() {
        XCTAssertFalse(FocusScoreDetector.shouldNudge(makeInput(isFocusing: false)))
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

/// 기준선 저장소는 UserDefaults 를 직접 쓴다. 테스트 전용 카테고리 이름을 써서
/// 실제 설정과 겹치지 않게 하고, 끝나면 반드시 지운다.
final class FocusThresholdStoreTests: XCTestCase {
    private let category = "테스트-몰입기준-카테고리"
    private var savedOverall: Any?

    override func setUp() {
        super.setUp()
        savedOverall = UserDefaults.standard.object(
            forKey: Constants.AppStorageKey.companionFocusScoreThreshold
        )
    }

    override func tearDown() {
        FocusThresholdStore.shared.removeCategory(category)
        if let savedOverall {
            UserDefaults.standard.set(
                savedOverall, forKey: Constants.AppStorageKey.companionFocusScoreThreshold
            )
        } else {
            UserDefaults.standard.removeObject(
                forKey: Constants.AppStorageKey.companionFocusScoreThreshold
            )
        }
        super.tearDown()
    }

    /// 처음 쓰는 카테고리에도 무언가는 적용돼야 한다.
    func testFallsBackToOverallWhenCategoryHasNoValue() {
        FocusThresholdStore.shared.overall = 0.42

        XCTAssertFalse(FocusThresholdStore.shared.hasCustomThreshold(for: category))
        XCTAssertEqual(FocusThresholdStore.shared.threshold(for: category), 0.42, accuracy: 0.0001)
        XCTAssertEqual(FocusThresholdStore.shared.threshold(for: nil), 0.42, accuracy: 0.0001)
    }

    func testCategoryValueOverridesOverall() {
        FocusThresholdStore.shared.overall = 0.60
        FocusThresholdStore.shared.setThreshold(0.25, for: category)

        XCTAssertTrue(FocusThresholdStore.shared.hasCustomThreshold(for: category))
        XCTAssertEqual(FocusThresholdStore.shared.threshold(for: category), 0.25, accuracy: 0.0001)
        XCTAssertEqual(FocusThresholdStore.shared.threshold(for: nil), 0.60, accuracy: 0.0001)
    }

    func testResetReturnsToOverall() {
        FocusThresholdStore.shared.overall = 0.60
        FocusThresholdStore.shared.setThreshold(0.25, for: category)
        FocusThresholdStore.shared.resetThreshold(for: category)

        XCTAssertEqual(FocusThresholdStore.shared.threshold(for: category), 0.60, accuracy: 0.0001)
    }

    func testStoredValueIsClamped() {
        FocusThresholdStore.shared.setThreshold(5, for: category)

        XCTAssertEqual(FocusThresholdStore.shared.threshold(for: category), 0.95, accuracy: 0.0001)
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
            score: FocusScore(focusSeconds: Int(1_500 * score), totalSeconds: 1_500),
            categorySeconds: categorySeconds
        )
    }

    /// 실제 사용자 데이터에서 나온 상황 — 공부로 포모도로를 걸고 에디터로 공부한다.
    /// 딴짓이 아니므로 기준선을 낮출 게 아니라 짝으로 묶어야 한다.
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
            score: FocusScore(focusSeconds: Int(1_500 * score), totalSeconds: 1_500),
            categorySeconds: [:]
        )
    }

    func testWeeklyOnTargetRatioUsesPerCategoryThreshold() {
        let samples = [
            makeSample(category: "개발", score: 0.80, at: weekOne),
            makeSample(category: "개발", score: 0.40, at: weekOne),
            // 공부 기준선은 0.20 이라 0.30 은 지킨 것으로 센다.
            makeSample(category: "공부", score: 0.30, at: weekOne),
        ]

        let weeks = FocusTrendBuilder.weeks(
            samples: samples,
            nudges: [],
            threshold: { $0 == "공부" ? 0.20 : 0.60 },
            calendar: calendar
        )

        XCTAssertEqual(weeks.count, 1)
        XCTAssertEqual(weeks[0].sessionCount, 3)
        XCTAssertEqual(weeks[0].onTargetRatio, 2.0 / 3.0, accuracy: 0.0001)
    }

    /// 기준선에 정확히 걸친 세션은 지킨 것으로 본다(잔소리가 안 나가는 쪽과 같은 기준).
    func testScoreExactlyAtThresholdCountsAsOnTarget() {
        let weeks = FocusTrendBuilder.weeks(
            samples: [makeSample(category: "개발", score: 0.60, at: weekOne)],
            nudges: [],
            threshold: { _ in 0.60 },
            calendar: calendar
        )

        XCTAssertEqual(weeks[0].onTargetRatio, 1.0, accuracy: 0.0001)
    }

    func testCountsNudgesIntoTheirWeek() {
        let nextWeek = weekOne.addingTimeInterval(8 * 86_400)
        let weeks = FocusTrendBuilder.weeks(
            samples: [
                makeSample(category: "개발", score: 0.9, at: weekOne),
                makeSample(category: "개발", score: 0.9, at: nextWeek),
            ],
            nudges: [
                FocusNudgeRecord(firedAt: weekOne, category: "개발"),
                FocusNudgeRecord(firedAt: weekOne, category: "개발"),
                FocusNudgeRecord(firedAt: nextWeek, category: "개발"),
            ],
            threshold: { _ in 0.60 },
            calendar: calendar
        )

        XCTAssertEqual(weeks.count, 2)
        XCTAssertEqual(weeks[0].nudgeCount, 2)
        XCTAssertEqual(weeks[1].nudgeCount, 1)
    }

    /// 쉰 주까지 0% 로 찍으면 추세가 왜곡된다.
    func testSkipsWeeksWithoutSessions() {
        let threeWeeksLater = weekOne.addingTimeInterval(21 * 86_400)
        let weeks = FocusTrendBuilder.weeks(
            samples: [
                makeSample(category: "개발", score: 0.9, at: weekOne),
                makeSample(category: "개발", score: 0.9, at: threeWeeksLater),
            ],
            nudges: [],
            threshold: { _ in 0.60 },
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
        XCTAssertEqual(dev?.sessionCount, 2)
    }
}

/// 과거 그래프와 실시간 판정이 같은 숫자를 내야 사용자가 기준선을 믿고 그을 수 있다.
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
