import XCTest
@testable import 호롱호롱

/// 실행 전략을 고르는 규칙을 못 박는다.
///
/// 이 값은 **기록(`RunRecord.variant`)에 그대로 남아 비교의 축이 된다.** 규칙이 조용히 바뀌면
/// 어제 잰 숫자와 오늘 잰 숫자가 다른 조건에서 나온 것이 되는데, 그건 알아채기 어렵다.
final class SuggestionExecutionStrategyTests: XCTestCase {

    private func resolved(
        _ provider: Constants.AchievementSuggestionProviderKind,
        override: String? = nil
    ) -> SuggestionExecutionStrategy {
        SuggestionExecutionStrategy.resolved(provider: provider, override: override)
    }

    // MARK: - 기본값은 공급자가 정한다

    /// 로컬 모델은 요청을 하나씩만 처리한다. 동시에 보내면 뒤엣것이 큐에서 60초를 다 쓰고 죽는다.
    func testLocalProvidersDefaultToSequential() {
        XCTAssertEqual(resolved(.ollama), .sequential)
        XCTAssertEqual(resolved(.mlx), .sequential)
    }

    /// AFM 은 앱 밖에서 겹쳐 돌아 타임아웃이 안 난다. 순차로 만들면 얻는 것 없이 느려진다.
    func testAppleFoundationDefaultsToParallel() {
        XCTAssertEqual(resolved(.appleFoundation), .parallel)
    }

    // MARK: - 덮어쓰기

    func testOverrideWins() {
        XCTAssertEqual(resolved(.ollama, override: "parallel"), .parallel)
        XCTAssertEqual(resolved(.appleFoundation, override: "sequential"), .sequential)
    }

    /// **알아볼 수 없는 값은 무시한다.** 오타 하나로 추천이 멈추면 안 된다 —
    /// 이건 개발용 손잡이지 기능 스위치가 아니다.
    func testUnknownOverrideFallsBackToDefault() {
        XCTAssertEqual(resolved(.ollama, override: "Parallel"), .sequential)
        XCTAssertEqual(resolved(.ollama, override: "batched"), .sequential)
        XCTAssertEqual(resolved(.appleFoundation, override: ""), .parallel)
    }
}
