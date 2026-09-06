import XCTest
@testable import 호롱호롱

/// 걸리는 시간 네 칸이 어떻게 흐르고 어떻게 고정되는지 못 박는다.
///
/// 저장소 없이 검사한다 — «다섯 번 쓰면 무엇이 남는가» 는 순수 계산이어야 한다.
final class TodoDurationSlotsTests: XCTestCase {

    private func minutes(recent: [Int], pinned: [Int]) -> [Int] {
        TodoDurationSlots.slots(recent: recent, pinned: pinned).map(\.minutes)
    }

    // MARK: - 기본 배치

    func testDefaultsFillFourSlots() {
        let slots = TodoDurationSlots.slots(recent: [], pinned: [])
        XCTAssertEqual(slots.map(\.minutes), [15, 30, 60, 120])
        XCTAssertEqual(slots.map(\.isPinned), [false, false, true, true], "왼쪽 둘만 흘러간다")
    }

    // MARK: - 최근 값 흘리기

    /// 직접 입력한 5분이 왼쪽 맨 앞으로 오고, 왼쪽에서 가장 오래된 30분이 밀려난다.
    /// 오른쪽 고정(1시간·2시간)은 건드리지 않는다.
    func testCustomDurationPushesOutTheOldestDynamicSlot() {
        let recent = TodoDurationSlots.remembering(5, recent: [15, 30], pinned: [60, 120])
        XCTAssertEqual(recent, [5, 15])
        XCTAssertEqual(minutes(recent: recent, pinned: [60, 120]), [5, 15, 60, 120])
    }

    func testUsingAValueAgainMovesItToTheFront() {
        let recent = TodoDurationSlots.remembering(15, recent: [5, 15], pinned: [60, 120])
        XCTAssertEqual(recent, [15, 5], "이미 있던 값은 밀어내지 않고 앞으로만 온다")
    }

    /// 고정 칸에 있는 값을 다시 써도 왼쪽으로 내려오면 안 된다 —
    /// 같은 값이 두 칸을 차지하면 고를 수 있는 길이가 셋으로 줄어든다.
    func testPinnedValueNeverEntersTheDynamicSlots() {
        let recent = TodoDurationSlots.remembering(60, recent: [15, 30], pinned: [60, 120])
        XCTAssertEqual(recent, [15, 30])
        XCTAssertEqual(Set(minutes(recent: recent, pinned: [60, 120])).count, 4, "네 칸은 늘 서로 달라야 한다")
    }

    func testGarbageInputIsIgnored() {
        XCTAssertEqual(TodoDurationSlots.remembering(0, recent: [15, 30], pinned: [60, 120]), [15, 30])
        XCTAssertEqual(TodoDurationSlots.remembering(-5, recent: [15, 30], pinned: [60, 120]), [15, 30])
    }

    // MARK: - 고정하기

    func testPinningMovesAValueRightAndDemotesTheEvictedOne() {
        let next = TodoDurationSlots.pinning(5, recent: [5, 15], pinned: [60, 120])
        XCTAssertEqual(next.pinned, [5, 60], "새로 고정한 값이 앞에 선다")
        XCTAssertTrue(next.recent.contains(120), "밀려난 고정 값은 버리지 않고 왼쪽으로 내려간다")
        XCTAssertFalse(next.recent.contains(5), "고정한 값이 왼쪽에도 남으면 안 된다")
        XCTAssertEqual(next.recent.count, 2)
    }

    func testPinningAnAlreadyPinnedValueChangesNothing() {
        let before = TodoDurationSlots.normalized(recent: [15, 30], pinned: [60, 120])
        let after = TodoDurationSlots.pinning(60, recent: [15, 30], pinned: [60, 120])
        XCTAssertEqual(after.pinned, before.pinned)
        XCTAssertEqual(after.recent, before.recent)
    }

    // MARK: - 고정 풀기

    func testUnpinningKeepsFourSlotsFilled() {
        let next = TodoDurationSlots.unpinning(120, recent: [5, 15], pinned: [60, 120])
        XCTAssertEqual(next.pinned.count, 2, "오른쪽 칸이 비면 안 된다")
        XCTAssertEqual(next.recent.count, 2)
        XCTAssertTrue(next.recent.contains(120), "푼 값은 왼쪽으로 내려온다")
        XCTAssertEqual(Set(next.recent + next.pinned).count, 4)
    }

    func testUnpinningSomethingNotPinnedChangesNothing() {
        let after = TodoDurationSlots.unpinning(15, recent: [15, 30], pinned: [60, 120])
        XCTAssertEqual(after.pinned, [60, 120])
        XCTAssertEqual(after.recent, [15, 30])
    }

    // MARK: - 망가진 저장값

    func testNormalizedAlwaysProducesFourDistinctSlots() {
        let cases: [(recent: [Int], pinned: [Int])] = [
            ([], []),
            ([0, -3], [0]),
            ([60], [60]),                 // 겹침
            ([15, 15, 15], [60, 60]),     // 중복
            ([1, 2, 3, 4, 5], [6, 7, 8])  // 넘침
        ]
        for (recent, pinned) in cases {
            let slots = minutes(recent: recent, pinned: pinned)
            XCTAssertEqual(slots.count, 4, "\(recent)/\(pinned)")
            XCTAssertEqual(Set(slots).count, 4, "\(recent)/\(pinned) — 서로 달라야 한다")
            XCTAssertTrue(slots.allSatisfy { $0 > 0 }, "\(recent)/\(pinned)")
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
