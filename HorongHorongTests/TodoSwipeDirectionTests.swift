import XCTest
@testable import 호롱호롱

/// 스와이프 삭제가 손가락을 따라오는지 못 박는다.
///
/// 회귀: 카드를 왼쪽으로 밀어야 삭제 배경이 나와야 하는데 오른쪽으로 밀어야 나왔다.
/// AppKit 이 «자연스러운 스크롤» 설정에 맞춰 이미 뒤집어 준 부호를 한 번 더 뒤집은 탓이다.
final class TodoSwipeDirectionTests: XCTestCase {

    private func translation(deltaX: CGFloat, naturalScrolling: Bool) -> CGFloat {
        TodoSwipeDirection.fingerTranslation(
            scrollingDeltaX: deltaX,
            isDirectionInvertedFromDevice: naturalScrolling
        )
    }

    // MARK: - 자연스러운 스크롤 켜짐 (macOS 기본값)

    /// 켜져 있으면 델타가 손가락 방향과 같게 온다. 그대로 써야 한다.
    func testNaturalScrollingFollowsFingers() {
        XCTAssertLessThan(translation(deltaX: -12, naturalScrolling: true), 0, "왼쪽으로 밀면 카드도 왼쪽")
        XCTAssertGreaterThan(translation(deltaX: 12, naturalScrolling: true), 0, "오른쪽으로 밀면 카드도 오른쪽")
        XCTAssertEqual(translation(deltaX: -12, naturalScrolling: true), -12)
    }

    // MARK: - 자연스러운 스크롤 꺼짐

    /// 꺼져 있으면 델타가 손가락과 반대로 오므로 되돌려야 한다.
    func testInvertedPreferenceStillFollowsFingers() {
        XCTAssertLessThan(translation(deltaX: 12, naturalScrolling: false), 0)
        XCTAssertGreaterThan(translation(deltaX: -12, naturalScrolling: false), 0)
        XCTAssertEqual(translation(deltaX: 12, naturalScrolling: false), -12)
    }

    // MARK: - 세로 스크롤

    func testNoHorizontalMovementYieldsZero() {
        XCTAssertEqual(translation(deltaX: 0, naturalScrolling: true), 0)
        XCTAssertEqual(translation(deltaX: 0, naturalScrolling: false), 0)
    }
}
