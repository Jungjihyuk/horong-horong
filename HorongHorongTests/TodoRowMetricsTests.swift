import XCTest
import SwiftUI
@testable import 호롱호롱

/// 할 일 카드 높이를 눈이 아니라 숫자로 못 박는다.
///
/// «Things 3 처럼 낮게» 라는 요구를 65pt → 58pt 로 옮겨 놓은 것이라,
/// 여백이나 글자 크기를 손대다 슬그머니 다시 부풀면 여기서 걸린다.
@MainActor
final class TodoRowMetricsTests: XCTestCase {

    /// 날짜 칩이 붙은 가장 흔한 한 줄. 목록 높이를 사실상 이 모양이 정한다.
    private func rowHeight() -> CGFloat {
        let row = HStack(alignment: .top, spacing: 11) {
            TodoCheckbox(isCompleted: false)
            TodoCardBody(
                title: "책에서 인상 깊었던 문장 351",
                isCompleted: false,
                chip: TodoDueChip(label: "오늘", tone: .today),
                list: nil,
                swatch: nil,
                isLinked: false
            )
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TodoRowMetrics.horizontalPadding)
        .padding(.vertical, TodoRowMetrics.verticalPadding)
        .frame(width: 380)

        let host = NSHostingView(rootView: row.fixedSize(horizontal: false, vertical: true))
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    // MARK: - 높이

    func testRowStaysAroundFiftyEightPoints() {
        XCTAssertEqual(rowHeight(), 58, accuracy: 1.5)
    }

    /// 예전 높이는 65pt 였다. 10% 가까이 줄인 상태를 유지해야 한다.
    func testRowIsAtLeastTenPercentShorterThanBefore() {
        XCTAssertLessThanOrEqual(rowHeight(), 65 * 0.9)
    }

    // MARK: - 체크박스

    func testCheckboxIsSmallerThanTheTitleLine() {
        // 제목 한 줄(13.5pt 글자 ≈ 16.5pt)보다 커지면 다시 눈에 띄게 커 보인다.
        XCTAssertLessThanOrEqual(TodoRowMetrics.checkboxSize, 15)

        // `fittingSize` 는 정수 포인트로 올림해서 준다. 실제 뷰는 소수점 크기 그대로다.
        let host = NSHostingView(rootView: TodoCheckbox(isCompleted: false).fixedSize())
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.width, TodoRowMetrics.checkboxSize.rounded(.up))
        XCTAssertEqual(host.fittingSize.height, TodoRowMetrics.checkboxSize.rounded(.up))
    }

    // MARK: - 스와이프 거리

    /// 세 값이 함께 움직이지 않으면 삭제에 닿지 못하거나 휴지통이 안 보인다.
    func testSwipeThresholdStaysReachable() {
        XCTAssertLessThan(TodoSwipeMetrics.deleteThreshold, TodoSwipeMetrics.maximumOffset)
        XCTAssertLessThan(TodoSwipeMetrics.trashRevealOffset, TodoSwipeMetrics.deleteThreshold)
        XCTAssertGreaterThan(TodoSwipeMetrics.trashRevealOffset, 0)
    }

    /// 예전 최대 거리는 120pt 였다. 40% 줄인 상태를 유지해야 한다.
    func testSwipeDistanceIsFortyPercentShorterThanBefore() {
        XCTAssertEqual(TodoSwipeMetrics.maximumOffset, 120 * 0.6, accuracy: 0.001)
    }
}
