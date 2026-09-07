import XCTest
@testable import 호롱호롱

/// 시간축 알약의 길이 규칙.
///
/// 화면 없이 검사할 수 있어야 하는 이유: 예전에는 길이를 줄 높이에 맡겨서, 미리알림 배지가
/// 한 줄 더 붙었다는 이유만으로 같은 상태의 할 일끼리 모양이 달라졌다. 길이를 정하는 것이
/// **걸리는 시간뿐**임을 여기서 못 박는다.
@MainActor
final class TodoTimelineCapsuleTests: XCTestCase {
    func testNoDurationUsesMinimumHeight() {
        XCTAssertEqual(TodoTimelineCapsule.height(durationMinutes: nil), TodoTimelineCapsule.minimumHeight)
        XCTAssertEqual(TodoTimelineCapsule.height(durationMinutes: 0), TodoTimelineCapsule.minimumHeight)
    }

    /// 뒤집힌 일정이 흘러들어와도 화면이 깨지지 않아야 한다.
    func testNegativeDurationUsesMinimumHeight() {
        XCTAssertEqual(TodoTimelineCapsule.height(durationMinutes: -30), TodoTimelineCapsule.minimumHeight)
    }

    func testLongerTasksGetTallerCapsules() {
        let short = TodoTimelineCapsule.height(durationMinutes: 15)
        let medium = TodoTimelineCapsule.height(durationMinutes: 60)
        let long = TodoTimelineCapsule.height(durationMinutes: 150)

        XCTAssertLessThan(short, medium)
        XCTAssertLessThan(medium, long)
        XCTAssertGreaterThan(short, TodoTimelineCapsule.minimumHeight)
    }

    /// 세 시간짜리나 하루짜리나 «길다» 로 충분하다 — 넘치면 한 화면에 몇 개 못 들어간다.
    func testHeightSaturatesAtCap() {
        let atCap = TodoTimelineCapsule.height(durationMinutes: TodoTimelineCapsule.saturationMinutes)
        let beyond = TodoTimelineCapsule.height(durationMinutes: 60 * 24)

        XCTAssertEqual(atCap, TodoTimelineCapsule.maximumHeight)
        XCTAssertEqual(beyond, TodoTimelineCapsule.maximumHeight)
    }

    func testHeightStaysWithinBounds() {
        for minutes in [1, 5, 30, 90, 179, 180, 1_000] {
            let height = TodoTimelineCapsule.height(durationMinutes: minutes)
            XCTAssertGreaterThanOrEqual(height, TodoTimelineCapsule.minimumHeight, "\(minutes)분")
            XCTAssertLessThanOrEqual(height, TodoTimelineCapsule.maximumHeight, "\(minutes)분")
        }
    }
}
