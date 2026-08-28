import XCTest
@testable import HorongAI

/// S1 배선 확인. 이 테스트가 `swift test` 로 도는 것 자체가 검증이다 —
/// 앱 타깃(과 mlx)을 빌드하지 않고 패키지만으로 실행된다는 뜻이기 때문이다.
final class WiringTests: XCTestCase {
    func testPackageRunsWithoutAppTarget() {
        XCTAssertFalse(HorongAI.version.isEmpty)
    }
}
