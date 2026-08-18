import XCTest
@testable import HorongAI

/// `extractJSONObject` 의 현재 동작을 못 박는다. 파서(`GoalSuggestionParserTests`)가 지키는
/// 다섯 갈래의 **바로 앞 단계**이고, 여기까지가 지금까지 비어 있었다.
///
/// 왜 필요했나 — 실측(2026-08-17) trace 에서 `rawResponse` 와 `extractedJSON` 이 774자로
/// **똑같았다.** 즉 이 함수가 아무것도 안 잘라냈다. 그런데 "`<think>` 처리 덕에 `noJSON` 이
/// 해소됐다"는 추측이 문서와 대화에 남아 있었다. 테스트가 없으니 **일하는지 모르는 코드**였고,
/// 그래서 틀린 추측이 사실처럼 굳었다.
///
/// 이 파일이 있으면 나중에 지울 때도 **무엇을 잃는지 알고** 지운다.
final class JSONExtractionTests: XCTestCase {

    private func extract(_ text: String) -> String {
        GoalSuggestionPayload.extractJSONObject(from: text)
    }

    private let json = #"{"suggestions": []}"#

    /// ① 추론 모델이 붙이는 `<think>` 블록을 걷어낸다.
    ///
    /// qwen3 계열이 추론 모드로 돌 때 나온다. 대화 경로(`OllamaChatClient`)는 `think: false` 로
    /// 끄지만 **목표 추천 경로(`OllamaTextGenerator`)는 끄지 않는다** — 그래서 올 수 있다.
    func testStripsThinkBlock() {
        XCTAssertEqual(extract("<think>어떤 목표로 묶을지 고민…</think>\n\(json)"), json)
    }

    /// 열림만 있고 닫힘이 없으면 손대지 않는다. 잘못 자르면 JSON 까지 날아간다.
    func testKeepsUnclosedThinkBlock() {
        // `{` 부터 `}` 까지만 남으므로 결과는 JSON 이다 — think 제거가 아니라 3단계가 살린 것.
        XCTAssertEqual(extract("<think>끝나지 않은 생각 \(json)"), json)
    }

    /// ② 마크다운 코드펜스에 싸서 주는 경우.
    ///
    /// 펜스를 벗긴 뒤 3단계(`{`~`}`)가 한 번 더 돌아 개행까지 정리된다 —
    /// 즉 2·3단계가 겹쳐 도는 것이 **의도된 동작**이다.
    func testExtractsFromJSONCodeFence() {
        XCTAssertEqual(extract("```json\n\(json)\n```"), json)
    }

    /// 언어 표시가 없는 펜스도 받는다.
    func testExtractsFromPlainCodeFence() {
        XCTAssertEqual(extract("```\n\(json)\n```"), json)
    }

    /// ③ 앞뒤에 설명을 붙여도 첫 `{` 부터 마지막 `}` 까지만 남는다.
    func testTrimsSurroundingProse() {
        XCTAssertEqual(extract("알겠습니다! 아래가 제안입니다.\n\(json)\n도움이 되었길 바랍니다."), json)
    }

    /// 셋이 한꺼번에 걸린 경우 — 실제로 가장 흔한 조합이다.
    func testHandlesThinkAndFenceTogether() {
        let raw = "<think>음…</think>\n다음과 같습니다:\n```json\n\(json)\n```"
        XCTAssertEqual(extract(raw), json)
    }

    /// **`{` 가 아예 없으면 원문을 그대로 돌려준다.** 이것이 `noJSON` 으로 기록되는 경로다.
    /// 여기서 빈 문자열을 돌려주면 파서가 "빈 응답"과 "JSON 아님"을 구분할 수 없게 된다.
    func testReturnsAsIsWhenNoBraces() {
        XCTAssertEqual(extract("죄송하지만 묶을 만한 할 일이 없습니다."), "죄송하지만 묶을 만한 할 일이 없습니다.")
    }

    /// 이미 순수 JSON 이면 아무것도 하지 않는다 — 실측에서 가장 흔한 경우다(774자 → 774자).
    func testLeavesCleanJSONUntouched() {
        XCTAssertEqual(extract(json), json)
    }
}
