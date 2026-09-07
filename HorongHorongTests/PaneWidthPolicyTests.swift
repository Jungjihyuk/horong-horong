import XCTest
import AppKit
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

    /// 호출자가 넘긴 최소 너비가 최대 너비(560)보다 먼저 걸리는지 확인한다.
    ///
    /// **화면은 더 이상 글자 폭을 재서 넘기지 않는다** — 그 되먹임이 앱을 멈춰 세웠다
    /// (2026-09-07). 지금은 상수를 넘기고 좁아질 때의 표현은 `ViewThatFits` 가 맡는다.
    /// 정책 자체는 어떤 최소 너비를 받든 같게 동작해야 하므로 이 검사는 남긴다.
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

    /// 상세 쪽도 마찬가지로, 저장된 폭보다 `trailingMinimum` 이 우선한다.
    /// (위와 같이 화면은 이제 잰 값이 아니라 상수를 넘긴다.)
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

    // MARK: - 최소 너비가 머리말을 담는가

    /// **「Todo」 가 «To / do» 로 접힌 회귀(2026-09-07)를 막는다.**
    ///
    /// 예전에는 머리말 글자 폭을 `GeometryReader` 로 재서 최소 너비에 더했지만, 그 값이 다시
    /// 두 칸의 폭을 정하는 되먹임 고리라 앱이 멈췄다. 측정을 걷어낸 대신 **상수끼리의 관계**를
    /// 여기서 못 박는다 — 검색창이 줄어들 수 있어야 이 관계가 성립한다.
    @MainActor
    private func headerRequirement(title: String, searchField: CGFloat) -> CGFloat {
        let titleWidth = (title as NSString)
            .size(withAttributes: [.font: BrowserHeaderMetrics.titleNSFont])
            .width
        return BrowserHeaderMetrics.fixedChromeWidth + titleWidth + searchField
    }

    @MainActor
    func testListPaneMinimumWidthFitsTheHeader() {
        // 머리말을 공유하는 두 화면 모두 검사한다.
        for (title, minimum) in [("Todo", Constants.todoListPaneMinWidth),
                                 ("Quick Note", Constants.quickNoteListPaneMinWidth)] {
            let required = headerRequirement(
                title: title,
                searchField: BrowserHeaderMetrics.searchFieldMinimumWidth
            )
            XCTAssertGreaterThanOrEqual(
                minimum, required,
                "«\(title)» 목록 최소 너비가 머리말보다 좁으면 제목이 두 줄로 접힌다"
            )
        }
    }

    /// 검색창이 고정 폭이면 위 관계가 깨진다. 유연해야 하는 이유를 숫자로 남긴다.
    @MainActor
    func testFixedSearchFieldWouldNotFit() {
        let ifFixed = headerRequirement(
            title: "Todo",
            searchField: BrowserHeaderMetrics.searchFieldWidth
        )
        XCTAssertGreaterThan(
            ifFixed,
            Constants.todoListPaneMinWidth,
            "이 단언이 깨지면 검색창을 고정 폭으로 되돌려도 안전하다는 뜻이다"
        )
    }
}
