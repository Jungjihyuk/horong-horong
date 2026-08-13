import XCTest
@testable import HorongAI

/// `GuideRetriever.evidence` — 섹션을 근거 조각으로 내보내는 새 출구.
///
/// `bestMatch` 와 같은 점수 계산을 쓰지만 **점수를 버리지 않는다.** 점수가 없으면
/// 답이 나빴을 때 "검색이 엉뚱한 걸 줬다"와 "모델이 근거를 못 썼다"를 가릴 수 없다.
final class GuideEvidenceTests: XCTestCase {

    private let sample = """
    ## 4. 타이머 탭

    기본 프리셋은 포모도로입니다.

    ## 5. 메모 탭

    퀵 메모 단축키는 ⌘⇧N 입니다.
    """

    private var sections: [GuideSection] { GuideRetriever.sections(from: sample) }

    func testEvidenceCarriesSourceAndStableID() {
        let evidence = GuideRetriever.evidence(for: "메모 탭이 뭐야?", in: sections)

        XCTAssertEqual(evidence?.source, "guide")
        XCTAssertEqual(evidence?.id, "guide.5. 메모 탭", "id 는 실행마다 같아야 채점에 쓸 수 있다")
        XCTAssertEqual(evidence?.text, "5. 메모 탭\n퀵 메모 단축키는 ⌘⇧N 입니다.")
    }

    /// 제목에 걸린 쪽이 본문에만 걸린 쪽보다 점수가 높다 — 같은 규칙을 `bestMatch` 와 공유한다.
    func testTitleHitScoresHigherThanBodyHit() {
        let titleHit = GuideRetriever.evidence(for: "메모 탭", in: sections)
        let bodyHit = GuideRetriever.evidence(for: "포모도로", in: sections)

        XCTAssertNotNil(titleHit?.score)
        XCTAssertNotNil(bodyHit?.score)
        XCTAssertGreaterThan(titleHit?.score ?? 0, bodyHit?.score ?? 0)
    }

    /// 근거가 없으면 nil. 빈 조각을 만들면 프롬프트에 빈 줄이 생긴다.
    func testNoMatchYieldsNoEvidence() {
        XCTAssertNil(GuideRetriever.evidence(for: "김치찌개 끓이는 법", in: sections))
    }

    /// 길이 제한이 `bestMatch` 쪽이 아니라 **여기서** 걸린다 — 호출부가 잊어도 프롬프트가 안 넘친다.
    func testLongSectionIsClippedInsideEvidence() {
        let long = GuideRetriever.sections(
            from: "## 긴 섹션\n" + String(repeating: "가", count: 900)
        )
        let evidence = GuideRetriever.evidence(for: "긴 섹션", in: long)

        XCTAssertTrue(evidence?.text.hasSuffix("(이하 생략)") == true)
        XCTAssertLessThan(evidence?.text.count ?? .max, 800)
    }
}
