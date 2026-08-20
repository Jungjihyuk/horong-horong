import XCTest
@testable import 호롱호롱

/// 조사 선택 규칙을 못 박는다.
///
/// AI 실험실이 태스크에 따라 «할일»(주간)·«주간 목표»(월간) 를 바꿔 끼우는데,
/// 한쪽은 받침이 있고 한쪽은 없다. 문자열 보간만 쓰면 «할일가» 가 나온다.
final class KoreanParticleTests: XCTestCase {

    // MARK: - 실제로 쓰는 두 말

    func testTaskNouns() {
        XCTAssertEqual("할일".withParticle(.subject), "할일이")
        XCTAssertEqual("주간 목표".withParticle(.subject), "주간 목표가")
    }

    // MARK: - 받침 유무

    func testSubjectParticle() {
        XCTAssertEqual("목표".withParticle(.subject), "목표가")
        XCTAssertEqual("묶음".withParticle(.subject), "묶음이")
    }

    func testObjectParticle() {
        XCTAssertEqual("목표".withParticle(.object), "목표를")
        XCTAssertEqual("묶음".withParticle(.object), "묶음을")
    }

    func testTopicParticle() {
        XCTAssertEqual("목표".withParticle(.topic), "목표는")
        XCTAssertEqual("묶음".withParticle(.topic), "묶음은")
    }

    func testAndParticle() {
        XCTAssertEqual("목표".withParticle(.and), "목표와")
        XCTAssertEqual("묶음".withParticle(.and), "묶음과")
    }

    /// **ㄹ 받침은 예외다.** 받침이 있는데도 «으로» 가 아니라 «로» 를 쓴다.
    func testDirectionParticleTreatsRieulAsBare() {
        XCTAssertEqual("목표".withParticle(.direction), "목표로")
        XCTAssertEqual("규칙".withParticle(.direction), "규칙으로")
        XCTAssertEqual("모델".withParticle(.direction), "모델로")
        XCTAssertEqual("서울".withParticle(.direction), "서울로")
    }

    // MARK: - 한글이 아닌 경우

    /// 영문·숫자로 끝나면 **받침 없는 쪽**으로 붙인다 — «Ollama이» 보다 «Ollama가» 가 낫다.
    func testNonHangulUsesBareForm() {
        XCTAssertEqual("Ollama".withParticle(.subject), "Ollama가")
        XCTAssertEqual("MLX".withParticle(.subject), "MLX가")
        XCTAssertEqual("3".withParticle(.subject), "3가")
        XCTAssertEqual("".withParticle(.subject), "가")
    }

    /// 자모 낱글자(ㄱ)나 한자처럼 음절 영역 밖이면 마찬가지다.
    func testOutsideSyllableBlockUsesBareForm() {
        XCTAssertEqual("ㄱ".withParticle(.object), "ㄱ를")
        XCTAssertEqual("目標".withParticle(.object), "目標를")
    }
}
