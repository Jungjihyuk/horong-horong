import XCTest
@testable import HorongAI

/// 함정(`traps`) 채점 규칙을 못 박는다.
///
/// 예전 이름은 `shouldNotGroup` 이었고 **점수에 아무 영향이 없었다** — 세기만 하고 버렸다.
/// README 에는 «감점한다» 고 적혀 있었으니 문서와 코드가 어긋나 있었다(2026-08-21).
///
/// 그리고 «묶이면 안 되는 모든 쌍» 을 적으려 하면 조합이 폭발한다. 3개짜리 묶음 둘이
/// 합쳐지는 걸 막으려면 9쌍인데, 실제 파일에는 2쌍만 적혀 있어 **왜 그 둘인지 알 수 없었다.**
final class TrapScoringTests: XCTestCase {

    private typealias Trap = PairEvaluator.Trap

    // MARK: - 함정이 금지하는 쌍

    /// 묶음이 **하나**면 그 안의 항목들이 서로 묶이면 안 된다.
    /// (예: 같은 앱을 쓸 뿐인 할일 셋)
    func testSingleGroupForbidsPairsWithin() {
        let trap = Trap(groups: [["m1", "m2", "m3"]])
        XCTAssertEqual(PairEvaluator.pairs(ofTrap: trap), ["m1|m2", "m1|m3", "m2|m3"])
    }

    /// 묶음이 **둘**이면 묶음 **사이**만 금지한다 — 묶음 안은 오히려 정답일 수 있다.
    func testTwoGroupsForbidOnlyCrossPairs() {
        let trap = Trap(groups: [["m1", "m2"], ["m3", "m4"]])
        let forbidden = PairEvaluator.pairs(ofTrap: trap)
        XCTAssertEqual(forbidden, ["m1|m3", "m1|m4", "m2|m3", "m2|m4"])
        XCTAssertFalse(forbidden.contains("m1|m2"), "묶음 안은 금지가 아니다")
        XCTAssertFalse(forbidden.contains("m3|m4"), "묶음 안은 금지가 아니다")
    }

    /// 3×3 이면 9쌍. 이 조합 폭발이 «쌍을 손으로 나열하지 않는» 이유다.
    func testCrossPairsGrowFast() {
        let trap = Trap(groups: [["m1", "m2", "m3"], ["m4", "m5", "m6"]])
        XCTAssertEqual(PairEvaluator.pairs(ofTrap: trap).count, 9)
    }

    func testEmptyGroupsAreIgnored() {
        XCTAssertTrue(PairEvaluator.pairs(ofTrap: Trap(groups: [])).isEmpty)
        XCTAssertTrue(PairEvaluator.pairs(ofTrap: Trap(groups: [[]])).isEmpty)
        XCTAssertTrue(PairEvaluator.pairs(ofTrap: Trap(groups: [["m1"]])).isEmpty, "혼자면 쌍이 없다")
    }

    // MARK: - 감점

    /// 함정을 **전부 밟으면** 묶음을 아무리 잘해도 0 이다.
    /// 그 케이스가 존재하는 이유가 그 함정이기 때문이다.
    func testSteppingOnEveryTrapZeroesTheScore() {
        let score = PairEvaluator.score(
            expectedGroups: [["m1", "m2", "m3"], ["m4", "m5", "m6"]],
            predictedGroups: [["m1", "m2", "m3", "m4", "m5", "m6"]],   // 둘을 뭉쳤다
            traps: [Trap(why: "뭉치기 쉽다", groups: [["m1", "m2", "m3"], ["m4", "m5", "m6"]])]
        )
        XCTAssertEqual(score.violations, 9)
        XCTAssertEqual(score.trapPairs, 9)
        XCTAssertEqual(score.trapAvoidance, 0, accuracy: 0.001)
        XCTAssertGreaterThan(score.f1, 0.5, "묶음 자체는 절반 넘게 맞았다")
        XCTAssertEqual(score.groupingScore, 0, accuracy: 0.001, "그래도 최종은 0")
    }

    /// 함정을 하나도 안 밟으면 F1 이 그대로 최종 점수다.
    func testAvoidingTrapsKeepsF1() {
        let score = PairEvaluator.score(
            expectedGroups: [["m1", "m2", "m3"], ["m4", "m5", "m6"]],
            predictedGroups: [["m1", "m2", "m3"], ["m4", "m5", "m6"]],
            traps: [Trap(groups: [["m1", "m2", "m3"], ["m4", "m5", "m6"]])]
        )
        XCTAssertEqual(score.violations, 0)
        XCTAssertEqual(score.trapAvoidance, 1.0, accuracy: 0.001)
        XCTAssertEqual(score.groupingScore, score.f1, accuracy: 0.001)
        XCTAssertEqual(score.groupingScore, 1.0, accuracy: 0.001)
    }

    /// 절반만 밟으면 절반만 깎인다.
    func testPartialViolationScalesTheScore() {
        let score = PairEvaluator.score(
            expectedGroups: [["m1", "m2"]],
            predictedGroups: [["m1", "m2", "m3"]],           // m3 를 잘못 넣었다
            traps: [Trap(groups: [["m3", "m4"]])]            // m3|m4 만 함정인데 안 밟았다
        )
        XCTAssertEqual(score.violations, 0)
        XCTAssertEqual(score.groupingScore, score.f1, accuracy: 0.001)
    }

    /// **함정을 안 적은 케이스는 예전과 똑같이 채점된다.** 회피율이 1 이라 곱해도 그대로다.
    func testCasesWithoutTrapsAreUnchanged() {
        let withTraps = PairEvaluator.score(
            expectedGroups: [["m1", "m2", "m3"]],
            predictedGroups: [["m1", "m2"]],
            traps: []
        )
        XCTAssertEqual(withTraps.trapPairs, 0)
        XCTAssertEqual(withTraps.trapAvoidance, 1.0, accuracy: 0.001)
        XCTAssertEqual(withTraps.groupingScore, withTraps.f1, accuracy: 0.001)
    }

    /// `f1` 은 **감점 전** 값으로 남는다 — 옛 기록과 그대로 비교하기 위해서다.
    func testF1StaysUnpenalized() {
        let score = PairEvaluator.score(
            expectedGroups: [["m1", "m2"], ["m3", "m4"]],
            predictedGroups: [["m1", "m2", "m3", "m4"]],
            traps: [Trap(groups: [["m1", "m2"], ["m3", "m4"]])]
        )
        XCTAssertGreaterThan(score.f1, 0, "F1 자체는 깎이지 않는다")
        XCTAssertEqual(score.groupingScore, 0, accuracy: 0.001)
    }
}
