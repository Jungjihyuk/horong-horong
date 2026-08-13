import XCTest
@testable import HorongAI
import HorongAITestSupport

/// 공급자 계약이 **실제로 구현 가능한지**를 확인한다.
///
/// 아무도 구현하지 않는 프로토콜은 검증할 수 없다. `ReplayProvider` 가 이 계약을 만족하는 것
/// 자체가 "계약이 쓸 만하다"는 증거이고, 동시에 앞으로 모든 회귀 판정의 결정적 기반이 된다.
@MainActor
final class ProviderContractTests: XCTestCase {

    func testReplayProviderReturnsScriptedAnswer() async {
        let provider = ReplayProvider(script: [
            "테마 어디서 바꿔?": LLMResponse(text: "설정 → 외관에서 바꾸실 수 있어요.", mood: "calm")
        ])
        let session = provider.makeSession(SessionSetup(instructions: "너는 루미롱이다."))

        let reply = await session.reply(to: "테마 어디서 바꿔?", decoding: .precise) { _ in }

        XCTAssertEqual(reply.text, "설정 → 외관에서 바꾸실 수 있어요.")
        XCTAssertEqual(reply.mood, "calm")
    }

    /// 정해두지 않은 입력에는 fallback 이 나온다 — 테스트가 조용히 통과하지 않게.
    func testUnscriptedMessageFallsBack() async {
        let provider = ReplayProvider()
        let session = provider.makeSession(SessionSetup(instructions: ""))

        let reply = await session.reply(to: "모르는 질문", decoding: .casual) { _ in }

        XCTAssertEqual(reply.text, "(정해둔 답 없음)")
    }

    /// 같은 입력은 몇 번을 물어도 같은 답이다. 회귀 판정의 전제다.
    func testReplayIsDeterministic() async {
        let provider = ReplayProvider(script: ["안녕": LLMResponse(text: "안녕하세요.")])
        let session = provider.makeSession(SessionSetup(instructions: ""))

        var answers: [String] = []
        for _ in 0..<5 {
            answers.append(await session.reply(to: "안녕", decoding: .precise) { _ in }.text)
        }

        XCTAssertEqual(Set(answers).count, 1)
    }

    /// 부분 응답 콜백도 불린다. 스트리밍을 쓰는 화면 코드가 같은 경로를 타게 하려는 것이다.
    func testPartialCallbackIsInvoked() async {
        let provider = ReplayProvider(script: ["안녕": LLMResponse(text: "안녕하세요.")])
        let session = provider.makeSession(SessionSetup(instructions: ""))

        var partials: [String] = []
        _ = await session.reply(to: "안녕", decoding: .precise) { partials.append($0.text) }

        XCTAssertEqual(partials, ["안녕하세요."])
    }

    /// 세션에 넘긴 지시문이 그대로 보관된다 — 프롬프트가 의도대로 조립됐는지 볼 때 쓴다.
    func testProviderRecordsWhatItReceived() async {
        let provider = ReplayProvider()
        let session = provider.makeSession(SessionSetup(instructions: "너는 루미롱이다."))

        _ = await session.reply(to: "안녕", decoding: .precise) { _ in }

        XCTAssertEqual(provider.received.count, 1)
        XCTAssertEqual(provider.received.first?.instructions, "너는 루미롱이다.")
        XCTAssertEqual(provider.received.first?.message, "안녕")
    }

    func testDecodingPresets() {
        XCTAssertEqual(DecodingOptions.precise.temperature, 0.2)
        XCTAssertEqual(DecodingOptions.casual.temperature, 0.4)
    }
}
