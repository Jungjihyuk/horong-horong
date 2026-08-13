import XCTest
@testable import HorongAI

/// `PairEvaluator` 의 **현재 동작**을 못 박는 특성화 테스트.
///
/// "이래야 한다"는 명세가 아니라 "지금 이렇게 동작한다"를 기록한다.
/// 옮기거나 고칠 때 여기가 깨지면 동작이 바뀐 것이다 — 의도한 변경이면 이 파일도 함께 고친다.
final class PairEvaluatorTests: XCTestCase {

    // MARK: - pairs(of:)

    func testPairsSortsAndJoinsWithBar() {
        XCTAssertEqual(PairEvaluator.pairs(of: ["b", "a"]), ["a|b"])
    }

    func testPairsMakesEveryCombination() {
        XCTAssertEqual(PairEvaluator.pairs(of: ["a", "b", "c"]), ["a|b", "a|c", "b|c"])
    }

    /// 2개 미만은 쌍이 만들어지지 않는다 — 혼자 있는 할일은 채점에 영향을 주지 않는다.
    func testPairsNeedsAtLeastTwo() {
        XCTAssertTrue(PairEvaluator.pairs(of: ["a"]).isEmpty)
        XCTAssertTrue(PairEvaluator.pairs(of: []).isEmpty)
    }

    func testPairsOfAllUnionsGroups() {
        XCTAssertEqual(PairEvaluator.pairs(ofAll: [["a", "b"], ["c", "d"]]), ["a|b", "c|d"])
    }

    // MARK: - score

    func testPerfectMatchScoresOne() {
        let s = PairEvaluator.score(expectedGroups: [["a", "b"]], predictedGroups: [["a", "b"]])
        XCTAssertEqual(s.f1, 1.0)
        XCTAssertEqual(s.precision, 1.0)
        XCTAssertEqual(s.recall, 1.0)
        XCTAssertEqual(s.hit, 1)
    }

    func testNoOverlapScoresZero() {
        let s = PairEvaluator.score(expectedGroups: [["a", "b"]], predictedGroups: [["c", "d"]])
        XCTAssertEqual(s.f1, 0.0)
        XCTAssertEqual(s.hit, 0)
    }

    /// 3개를 한 묶음으로 냈는데 정답은 2개짜리 — 맞춘 쌍 1개 / 낸 쌍 3개.
    func testPartialMatch() {
        let s = PairEvaluator.score(expectedGroups: [["a", "b"]], predictedGroups: [["a", "b", "c"]])
        XCTAssertEqual(s.expectedPairs, 1)
        XCTAssertEqual(s.predictedPairs, 3)
        XCTAssertEqual(s.hit, 1)
        XCTAssertEqual(s.precision, 1.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(s.recall, 1.0)
        XCTAssertEqual(s.f1, 0.5, accuracy: 1e-9)
    }

    /// **둘 다 비어 있으면 만점이다.** "묶을 것이 없는 입력" 골든 케이스가 이 경로를 탄다.
    func testBothEmptyScoresOne() {
        let s = PairEvaluator.score(expectedGroups: [], predictedGroups: [])
        XCTAssertEqual(s.f1, 1.0)
    }

    /// 묶을 게 없는데 묶어서 냈으면 0점.
    func testPredictedWhenNothingExpectedScoresZero() {
        let s = PairEvaluator.score(expectedGroups: [], predictedGroups: [["a", "b"]])
        XCTAssertEqual(s.f1, 0.0)
        XCTAssertEqual(s.precision, 0.0)
        XCTAssertEqual(s.recall, 0.0)
    }

    /// 묶어야 하는데 아무것도 안 냈으면 0점.
    func testNothingPredictedWhenExpectedScoresZero() {
        let s = PairEvaluator.score(expectedGroups: [["a", "b"]], predictedGroups: [])
        XCTAssertEqual(s.f1, 0.0)
    }

    /// `shouldNotGroup` 은 점수를 깎지 않고 **횟수만 센다**. 현재 동작이 그렇다.
    func testViolationsAreCountedButDoNotChangeF1() {
        let s = PairEvaluator.score(
            expectedGroups: [["a", "b"]],
            predictedGroups: [["a", "b"], ["x", "y"]],
            shouldNotGroup: [["x", "y"]]
        )
        XCTAssertEqual(s.violations, 1)
        XCTAssertEqual(s.hit, 1)
        XCTAssertEqual(s.precision, 0.5)
        XCTAssertEqual(s.f1, 2.0 / 3.0, accuracy: 1e-9)
    }
}
