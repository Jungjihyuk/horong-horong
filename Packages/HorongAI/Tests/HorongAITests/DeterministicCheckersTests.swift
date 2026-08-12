import XCTest
@testable import HorongAI

/// `DeterministicCheckers` 의 **현재 동작**을 못 박는 특성화 테스트.
///
/// 이 검사들은 평가(채점)와 런타임(가드레일) **양쪽**이 쓰게 될 규칙이라,
/// 옮기거나 고칠 때 여기가 먼저 깨져야 한다.
final class DeterministicCheckersTests: XCTestCase {

    // MARK: - 존댓말 비율

    func testHonorificEmptyIsZero() {
        XCTAssertEqual(DeterministicCheckers.checkHonorific(""), 0.0)
        XCTAssertEqual(DeterministicCheckers.checkHonorific("   \n "), 0.0)
    }

    func testHonorificAllPolite() {
        XCTAssertEqual(DeterministicCheckers.checkHonorific("설정에서 바꿀 수 있어요."), 1.0)
        XCTAssertEqual(DeterministicCheckers.checkHonorific("가능합니다. 확인했어요."), 1.0)
    }

    func testHonorificMixedIsRatio() {
        // "밥 먹어" 는 반말, "감사합니다" 는 존댓말 → 1/2
        XCTAssertEqual(DeterministicCheckers.checkHonorific("밥 먹어. 감사합니다."), 0.5)
    }

    /// **목표 추천 출력이 항상 0.0 인 이유.**
    /// 결과가 "주간 보고서 마무리" 같은 명사구 제목이라 존댓말 어미로 끝나지 않는다.
    /// 이 스위트에 존댓말 검사를 붙인 것 자체가 맞지 않는다는 증거다 — 채점자를
    /// 스위트별로 고르게 되면(아키텍처 문서 E-2) 해소된다.
    func testHonorificIsZeroForNounPhraseTitles() {
        let goalTitles = "- 주간 보고서 마무리\n- 운동 루틴 만들기"
        XCTAssertEqual(DeterministicCheckers.checkHonorific(goalTitles), 0.0)
    }

    /// 줄바꿈도 문장 구분자다.
    func testHonorificSplitsOnNewline() {
        XCTAssertEqual(DeterministicCheckers.checkHonorific("좋아요\n싫어"), 0.5)
    }

    // MARK: - 문장 수 제한

    func testSentenceCountEmptyIsZero() {
        XCTAssertEqual(DeterministicCheckers.checkSentenceCount(""), 0.0)
    }

    func testSentenceCountWithinLimitIsOne() {
        XCTAssertEqual(DeterministicCheckers.checkSentenceCount("하나. 둘. 셋."), 1.0)
    }

    /// 한 문장 넘을 때마다 0.5씩 깎는다 — 4문장이면 0.5, 5문장이면 0.
    func testSentenceCountPenaltyIsHalfPerExtra() {
        XCTAssertEqual(DeterministicCheckers.checkSentenceCount("하나. 둘. 셋. 넷."), 0.5)
        XCTAssertEqual(DeterministicCheckers.checkSentenceCount("하나. 둘. 셋. 넷. 다섯."), 0.0)
        XCTAssertEqual(DeterministicCheckers.checkSentenceCount("하나. 둘. 셋. 넷. 다섯. 여섯."), 0.0)
    }

    func testSentenceCountRespectsCustomLimit() {
        XCTAssertEqual(DeterministicCheckers.checkSentenceCount("하나. 둘.", maxCount: 1), 0.5)
    }

    // MARK: - 마크다운 기호

    func testMarkdownEmptyIsOne() {
        XCTAssertEqual(DeterministicCheckers.checkMarkdownSymbols(""), 1.0)
    }

    func testMarkdownCleanTextIsOne() {
        XCTAssertEqual(DeterministicCheckers.checkMarkdownSymbols("설정에서 바꿀 수 있어요."), 1.0)
    }

    /// 기호 하나당 0.2씩 깎는다. `**볼드**` 는 기호 4개라 0.2.
    func testMarkdownPenaltyIsPointTwoPerSymbol() {
        XCTAssertEqual(DeterministicCheckers.checkMarkdownSymbols("*"), 0.8, accuracy: 1e-9)
        XCTAssertEqual(DeterministicCheckers.checkMarkdownSymbols("**볼드**"), 0.2, accuracy: 1e-9)
        XCTAssertEqual(DeterministicCheckers.checkMarkdownSymbols("#####"), 0.0, accuracy: 1e-9)
    }

    /// **주석과 코드가 다르다.** 주석은 "(*, #, - 등)" 이라고 하지만
    /// 실제 검사 집합은 `*#\`` 뿐이라 **하이픈 목록은 감점되지 않는다.**
    /// 지금 동작을 그대로 기록해 둔다 — 고칠 때 의도적으로 고치게 하려는 것이다.
    func testMarkdownDoesNotPenalizeHyphenBullets() {
        XCTAssertEqual(DeterministicCheckers.checkMarkdownSymbols("- 항목1\n- 항목2"), 1.0)
    }

    /// 백틱은 감점 대상이다.
    func testMarkdownPenalizesBacktick() {
        XCTAssertEqual(DeterministicCheckers.checkMarkdownSymbols("`코드`"), 0.6, accuracy: 1e-9)
    }
}
