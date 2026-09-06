import XCTest
@testable import 호롱호롱

/// 손잡이로 정한 상세 폼 너비가 창 크기에 따라 어떻게 잘리는지 못 박는다.
///
/// 저장값은 창 크기와 무관하게 남아 있으므로, 창을 줄인 다음 다시 켰을 때
/// 목록이 사라지거나 폼이 화면을 넘어가지 않아야 한다.
final class PaneWidthPolicyTests: XCTestCase {

    private let leadingMinimum: CGFloat = 320
    private let trailingMinimum: CGFloat = 240
    private let trailingMaximum: CGFloat = 560

    private func resolve(_ proposed: CGFloat, totalWidth: CGFloat) -> CGFloat {
        PaneWidthPolicy.resolveTrailing(
            proposed: proposed,
            totalWidth: totalWidth,
            leadingMinimum: leadingMinimum,
            trailingMinimum: trailingMinimum,
            trailingMaximum: trailingMaximum
        )
    }

    // MARK: - 여유로운 창

    func testKeepsProposedWidthWhenItFits() {
        XCTAssertEqual(resolve(300, totalWidth: 900), 300)
        XCTAssertEqual(resolve(420, totalWidth: 900), 420)
    }

    func testClampsToMinimumAndMaximum() {
        XCTAssertEqual(resolve(80, totalWidth: 1_200), trailingMinimum)
        XCTAssertEqual(resolve(5_000, totalWidth: 1_200), trailingMaximum)
    }

    // MARK: - 목록 자리 지키기

    func testLeavesRoomForTheList() {
        // 700 - 320 = 380 까지만 내줄 수 있다. 최대치(560)보다 창 사정이 먼저다.
        XCTAssertEqual(resolve(560, totalWidth: 700), 380)
    }

    func testStoredWidthShrinksWithTheWindow() {
        let stored: CGFloat = 500
        XCTAssertEqual(resolve(stored, totalWidth: 1_000), 500)
        XCTAssertEqual(resolve(stored, totalWidth: 800), 480)
        XCTAssertEqual(resolve(stored, totalWidth: 620), 300)
    }

    // MARK: - 둘 다 최소를 지킬 수 없는 창

    func testSplitsProportionallyWhenTooNarrow() {
        // 320 + 240 = 560 이 안 나오는 창. 한쪽을 0 으로 만들지 않고 최소 너비 비율로 나눈다.
        let resolved = resolve(300, totalWidth: 400)
        XCTAssertEqual(resolved, CGFloat(400.0 * (240.0 / 560.0)), accuracy: 0.001)
        XCTAssertGreaterThan(resolved, 0)
        XCTAssertLessThan(resolved, 400)
    }

    func testZeroWidthYieldsZero() {
        XCTAssertEqual(resolve(300, totalWidth: 0), 0)
    }

    // MARK: - 머리말이 접히지 않는 한계

    /// 목록 머리말의 «미리알림에 N개 연동 중» 은 두 줄로 접히면 안 된다.
    /// 그래서 화면은 «머리말 고정 폭 + 실제 글자 폭» 을 목록 최소 너비로 넘긴다.
    /// 여기서는 그 값이 최대 너비(560)보다 먼저 걸리는지 확인한다.
    func testHeaderMinimumWinsOverTrailingMaximum() {
        let headerMinimum: CGFloat = 288 + 105  // 고정 폭 + 잰 글자 폭
        let resolved = PaneWidthPolicy.resolveTrailing(
            proposed: trailingMaximum,
            totalWidth: 916,
            leadingMinimum: headerMinimum,
            trailingMinimum: trailingMinimum,
            trailingMaximum: trailingMaximum
        )
        XCTAssertEqual(resolved, 916 - headerMinimum)
        XCTAssertLessThan(resolved, trailingMaximum)
    }

    /// 상세 쪽도 마찬가지다 — «7. 6. 월요일 01:37 61일 지남» 이 접히지 않을 만큼은 남겨야 한다.
    /// 화면은 그 줄을 한 줄로 편 너비를 재서 `trailingMinimum` 으로 넘긴다.
    func testDetailMinimumWinsOverAUserDraggedWidth() {
        let detailMinimum: CGFloat = 296  // 잰 날짜 줄 + 카드·패널 여백
        let resolved = PaneWidthPolicy.resolveTrailing(
            proposed: 240,                // 사용자가 손잡이를 끝까지 왼쪽으로 당긴 값
            totalWidth: 916,
            leadingMinimum: leadingMinimum,
            trailingMinimum: detailMinimum,
            trailingMaximum: trailingMaximum
        )
        XCTAssertEqual(resolved, detailMinimum)
        XCTAssertGreaterThan(resolved, 240, "저장값보다 최소 너비가 우선한다")
    }

    // MARK: - 망가진 값

    func testIgnoresNonFiniteInput() {
        XCTAssertEqual(resolve(.nan, totalWidth: 900), trailingMinimum)
        XCTAssertEqual(resolve(300, totalWidth: .nan), 0)
    }
}
