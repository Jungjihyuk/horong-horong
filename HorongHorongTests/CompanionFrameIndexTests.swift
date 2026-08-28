import XCTest
@testable import 호롱호롱

/// 프레임 번호가 **항상 배열 범위 안**임을 못 박는다.
///
/// 왜 필요했나 — 2026-08-19 릴리스 빌드가 `CompanionView.swift:191` 에서 죽었다.
/// 맥이 깨어나며 시계가 뒤로 조정돼 틱 간격이 음수가 됐고, 경과 시간이 음수로 내려가면서
/// `rawIndex % frameCount` 가 음수를 냈다(Swift 의 `%` 는 피제수의 부호를 따른다).
/// 화면 쪽은 `min(frameIndex, count - 1)` 로 **위쪽만** 막고 있어 그대로 통과했다.
@MainActor
final class CompanionFrameIndexTests: XCTestCase {

    /// 프레임 길이를 `0.25` 로 둔 이유는 **이진수로 정확히 표현되는 값**이기 때문이다.
    /// `0.1` 을 쓰면 `0.6 / 0.1 == 5.999…` 처럼 나눗셈이 한 칸 모자라게 떨어져,
    /// 테스트가 부동소수점 오차를 검증하는 꼴이 된다(실제 동작에는 영향이 없다 —
    /// 한 프레임을 한 틱 더 붙잡고 있을 뿐이다).
    private func index(
        elapsed: TimeInterval,
        frameDuration: TimeInterval = 0.25,
        frameCount: Int = 5,
        loops: Bool = true
    ) -> Int {
        CompanionController.frameIndex(
            elapsed: elapsed, frameDuration: frameDuration, frameCount: frameCount, loops: loops
        )
    }

    // MARK: - 평범한 경우

    func testAdvancesOneFramePerDuration() {
        XCTAssertEqual(index(elapsed: 0.0), 0)
        XCTAssertEqual(index(elapsed: 0.25), 1)
        XCTAssertEqual(index(elapsed: 0.75), 3)
    }

    func testLoopsBackToStart() {
        XCTAssertEqual(index(elapsed: 1.25), 0)
        XCTAssertEqual(index(elapsed: 1.5), 1)
    }

    /// 되감지 않는 애니메이션은 마지막 프레임에서 멈춘다.
    func testNonLoopingStopsAtLastFrame() {
        XCTAssertEqual(index(elapsed: 25.0, loops: false), 4)
    }

    // MARK: - 죽였던 경우들

    /// **음수 경과.** 시계가 뒤로 가면 여기까지 내려온다.
    func testNegativeElapsedStaysInRange() {
        for elapsed in [-0.05, -0.1, -1.0, -3600.0] {
            let i = index(elapsed: elapsed)
            XCTAssertTrue((0..<5).contains(i), "elapsed \(elapsed) → \(i)")
        }
    }

    /// 되감는 애니메이션에서 특히 위험했다 — `-1 % 5 == -1` 이라 그대로 음수가 나갔다.
    func testNegativeElapsedWhileLooping() {
        XCTAssertEqual(index(elapsed: -0.25, loops: true), 0)
        XCTAssertEqual(index(elapsed: -0.25, loops: false), 0)
    }

    /// **거대한 경과.** 잠들었다 깨면 몇 시간이 한 번에 들어온다.
    /// `Int(_:)` 변환이 터지지 않아야 하고 값도 범위 안이어야 한다.
    func testHugeElapsedStaysInRange() {
        for elapsed in [86_400.0, 1e12, 1e30, .greatestFiniteMagnitude] {
            let i = index(elapsed: elapsed)
            XCTAssertTrue((0..<5).contains(i), "elapsed \(elapsed) → \(i)")
        }
    }

    /// 스프라이트를 못 읽었을 때. 0 으로 나누거나 빈 배열을 인덱싱하면 안 된다.
    func testDegenerateInputsReturnZero() {
        XCTAssertEqual(index(elapsed: 1.0, frameCount: 0), 0)
        XCTAssertEqual(index(elapsed: 1.0, frameDuration: 0), 0)
        XCTAssertEqual(index(elapsed: .nan), 0)
    }
}
