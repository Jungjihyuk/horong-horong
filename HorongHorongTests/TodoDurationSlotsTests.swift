import XCTest
@testable import 호롱호롱

/// 걸리는 시간 세 칸이 어떻게 흐르고, 고정되고, **어떤 순서로 놓이는지** 못 박는다.
/// (네 번째 자리는 «직접 입력» 버튼이 쓰므로 프리셋은 셋이다.)
///
/// 저장소 없이 검사한다 — «다섯 번 쓰면 무엇이 남는가» 는 순수 계산이어야 한다.
final class TodoDurationSlotsTests: XCTestCase {

    private func minutes(recent: [Int], pinned: [Int]) -> [Int] {
        TodoDurationSlots.slots(recent: recent, pinned: pinned).map(\.minutes)
    }

    // MARK: - 기본 배치

    func testDefaultsFillThreeSlots() {
        let slots = TodoDurationSlots.slots(recent: [], pinned: [])
        XCTAssertEqual(slots.map(\.minutes), [30, 60, 120])
        XCTAssertEqual(slots.map(\.isPinned), [false, true, true], "흘러가는 칸은 하나뿐이다")
    }

    /// **자리는 길이 순으로 고정한다.** 최근 것을 왼쪽에 두면 같은 칸의 값이 매번 달라져
    /// 손이 위치를 기억하지 못한다.
    func testSlotsAreSortedByLengthNotByRecency() {
        XCTAssertEqual(minutes(recent: [90], pinned: [60, 120]), [60, 90, 120])
        XCTAssertEqual(minutes(recent: [5], pinned: [60, 120]), [5, 60, 120])
        XCTAssertEqual(minutes(recent: [180], pinned: [60, 120]), [60, 120, 180])
    }

    // MARK: - 최근 값 흘리기

    /// 직접 입력한 5분이 왼쪽 맨 앞으로 오고, 왼쪽에서 가장 오래된 30분이 밀려난다.
    /// 오른쪽 고정(1시간·2시간)은 건드리지 않는다.
    func testCustomDurationPushesOutTheOldestDynamicSlot() {
        let recent = TodoDurationSlots.remembering(5, recent: [30], pinned: [60, 120])
        XCTAssertEqual(recent, [5], "흘러가는 칸이 하나라 방금 쓴 값만 남는다")
        XCTAssertEqual(minutes(recent: recent, pinned: [60, 120]), [5, 60, 120])
    }

    /// 최근 목록의 순서는 «무엇을 남길지» 를 정할 뿐, 화면 순서와는 무관하다.
    func testUsingAValueAgainKeepsItInTheRecentList() {
        let recent = TodoDurationSlots.remembering(15, recent: [15], pinned: [60, 120])
        XCTAssertEqual(recent, [15], "이미 있던 값은 밀어내지 않는다")
    }

    /// 고정 칸에 있는 값을 다시 써도 왼쪽으로 내려오면 안 된다 —
    /// 같은 값이 두 칸을 차지하면 고를 수 있는 길이가 셋으로 줄어든다.
    func testPinnedValueNeverEntersTheDynamicSlots() {
        let recent = TodoDurationSlots.remembering(60, recent: [30], pinned: [60, 120])
        XCTAssertEqual(recent, [30])
        XCTAssertEqual(Set(minutes(recent: recent, pinned: [60, 120])).count, 3, "세 칸은 늘 서로 달라야 한다")
    }

    func testGarbageInputIsIgnored() {
        XCTAssertEqual(TodoDurationSlots.remembering(0, recent: [30], pinned: [60, 120]), [30])
        XCTAssertEqual(TodoDurationSlots.remembering(-5, recent: [30], pinned: [60, 120]), [30])
    }

    // MARK: - 고정하기

    func testPinningMovesAValueRightAndDemotesTheEvictedOne() {
        let next = TodoDurationSlots.pinning(5, recent: [5], pinned: [60, 120])
        XCTAssertEqual(next.pinned, [5, 60], "새로 고정한 값이 앞에 선다")
        XCTAssertTrue(next.recent.contains(120), "밀려난 고정 값은 버리지 않고 흐르는 칸으로 내려간다")
        XCTAssertFalse(next.recent.contains(5), "고정한 값이 흐르는 칸에도 남으면 안 된다")
        XCTAssertEqual(next.recent.count, 1)
    }

    func testPinningAnAlreadyPinnedValueChangesNothing() {
        let before = TodoDurationSlots.normalized(recent: [30], pinned: [60, 120])
        let after = TodoDurationSlots.pinning(60, recent: [30], pinned: [60, 120])
        XCTAssertEqual(after.pinned, before.pinned)
        XCTAssertEqual(after.recent, before.recent)
    }

    // MARK: - 고정 풀기

    func testUnpinningKeepsEverySlotFilled() {
        let next = TodoDurationSlots.unpinning(120, recent: [5], pinned: [60, 120])
        XCTAssertEqual(next.pinned.count, 2, "고정 칸이 비면 안 된다")
        XCTAssertEqual(next.recent.count, 1)
        XCTAssertTrue(next.recent.contains(120), "푼 값은 흐르는 칸으로 내려온다")
        XCTAssertEqual(Set(next.recent + next.pinned).count, 3)
    }

    func testUnpinningSomethingNotPinnedChangesNothing() {
        let after = TodoDurationSlots.unpinning(15, recent: [30], pinned: [60, 120])
        XCTAssertEqual(after.pinned, [60, 120])
        XCTAssertEqual(after.recent, [30])
    }

    // MARK: - 망가진 저장값

    func testNormalizedAlwaysProducesThreeDistinctSlots() {
        let cases: [(recent: [Int], pinned: [Int])] = [
            ([], []),
            ([0, -3], [0]),
            ([60], [60]),                 // 겹침
            ([15, 15, 15], [60, 60]),     // 중복
            ([1, 2, 3, 4, 5], [6, 7, 8])  // 넘침
        ]
        for (recent, pinned) in cases {
            let slots = minutes(recent: recent, pinned: pinned)
            XCTAssertEqual(slots.count, 3, "\(recent)/\(pinned)")
            XCTAssertEqual(Set(slots).count, 3, "\(recent)/\(pinned) — 서로 달라야 한다")
            XCTAssertTrue(slots.allSatisfy { $0 > 0 }, "\(recent)/\(pinned)")
            XCTAssertEqual(slots, slots.sorted(), "\(recent)/\(pinned) — 늘 오름차순이어야 한다")
        }
    }

    // MARK: - 저장 형식

    func testEncodeDecodeRoundTrip() {
        XCTAssertEqual(TodoDurationSlots.decode(TodoDurationSlots.encode([5, 15])), [5, 15])
        XCTAssertEqual(TodoDurationSlots.decode(""), [])
        XCTAssertEqual(TodoDurationSlots.decode("5, 15 ,abc"), [5, 15], "망가진 조각은 건너뛴다")
    }

    // MARK: - 문구

    func testDurationTitles() {
        XCTAssertEqual(TodoDurationText.title(minutes: 5), "5분")
        XCTAssertEqual(TodoDurationText.title(minutes: 60), "1시간")
        XCTAssertEqual(TodoDurationText.title(minutes: 90), "1시간 30분")
    }
}
