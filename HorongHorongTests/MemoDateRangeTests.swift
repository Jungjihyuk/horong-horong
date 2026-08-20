import XCTest
@testable import 호롱호롱

/// 시작·마감이 **뒤집힌 채 저장되지 않는다**는 것을 못 박는다.
///
/// 왜 필요했나 — 실측(2026-08-20) 저장소에서 시작·마감이 둘 다 있는 완료 할일 68건 중
/// **6건이 마감 < 시작**이었다. 화면 바인딩이 고른 값을 그대로 넣기만 해서 막을 곳이 없었다.
///
/// 이 값으로 «얼마나 걸린 일인가» 를 재려는 계획이 있는데, 뒤집힌 값이 섞이면 소요 시간이
/// 음수가 되어 통계가 깨진다.
@MainActor
final class MemoDateRangeTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func offset(_ hours: Double) -> Date { base.addingTimeInterval(hours * 3600) }

    private func memo() -> Memo { Memo(content: "할일") }

    // MARK: - 정상

    func testKeepsValidRange() {
        let m = memo()
        m.setStartDate(offset(0))
        m.setDeadline(offset(2))
        XCTAssertEqual(m.startDate, offset(0))
        XCTAssertEqual(m.deadline, offset(2))
    }

    /// 한쪽만 있는 경우엔 상대가 없으니 그대로 둔다.
    func testAllowsEitherSideAlone() {
        let start = memo()
        start.setStartDate(offset(5))
        XCTAssertEqual(start.startDate, offset(5))
        XCTAssertNil(start.deadline)

        let due = memo()
        due.setDeadline(offset(5))
        XCTAssertEqual(due.deadline, offset(5))
        XCTAssertNil(due.startDate)
    }

    // MARK: - 뒤집기 시도

    /// 시작을 마감보다 뒤로 밀면 **마감이 따라온다.** 방금 고른 쪽을 살린다 —
    /// 되돌리면 사용자가 «왜 안 바뀌지» 로 받아들인다.
    func testMovingStartPastDeadlinePushesDeadline() {
        let m = memo()
        m.setStartDate(offset(0))
        m.setDeadline(offset(2))

        m.setStartDate(offset(5))
        XCTAssertEqual(m.startDate, offset(5))
        XCTAssertEqual(m.deadline, offset(5), "마감이 시작을 따라와야 한다")
    }

    /// 마감을 시작보다 앞으로 당기면 **시작이 따라온다.**
    func testMovingDeadlineBeforeStartPullsStart() {
        let m = memo()
        m.setStartDate(offset(3))
        m.setDeadline(offset(6))

        m.setDeadline(offset(1))
        XCTAssertEqual(m.deadline, offset(1))
        XCTAssertEqual(m.startDate, offset(1), "시작이 마감을 따라와야 한다")
    }

    /// 어느 쪽을 어떻게 움직여도 **마감 ≥ 시작**이 깨지지 않는다.
    func testRangeIsNeverInverted() {
        let m = memo()
        for hours in [0.0, 4, -3, 10, 2, -8, 7] {
            m.setStartDate(offset(hours))
            assertNotInverted(m)
            m.setDeadline(offset(-hours))
            assertNotInverted(m)
        }
    }

    private func assertNotInverted(_ m: Memo, line: UInt = #line) {
        guard let start = m.startDate, let deadline = m.deadline else { return }
        XCTAssertGreaterThanOrEqual(
            deadline, start, "마감이 시작보다 앞설 수 없다", line: line
        )
    }

    /// 같은 시각은 허용한다. 소요 0분은 «잘못된 값» 이 아니라 «아직 안 정한 값» 이라
    /// 통계 쪽에서 걸러낼 일이지 저장을 막을 일이 아니다.
    func testAllowsSameInstant() {
        let m = memo()
        m.setStartDate(offset(1))
        m.setDeadline(offset(1))
        XCTAssertEqual(m.startDate, m.deadline)
    }
}
