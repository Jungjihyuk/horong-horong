import XCTest
@testable import HorongAI

/// 스키마가 **Ollama 가 알아듣는 JSON Schema 모양**으로 나가는지 못 박는다.
///
/// 이 값이 틀리면 서버가 요청을 거절하거나(400) 제약이 조용히 안 걸린다. 후자가 더 나쁘다 —
/// 아무 일도 안 일어난 것처럼 보이는데 모양 강제가 사라진 상태로 계속 돌기 때문이다.
///
/// **예전 이 테스트는 `JSONEncoder` 에 `.sortedKeys` 를 켜고 검사했다.** 그래서 «순서가 안정적이다»
/// 라고 통과했는데, 정작 전송 경로에는 그 옵션이 없어 순서가 매번 달랐다. 테스트가 실제로
/// 나가는 바이트가 아니라 **테스트 전용 바이트**를 보고 있었던 것이다(인시던트 2026-08-25).
/// 그래서 이제는 전송에 쓰는 `jsonText` 만 검사한다.
final class JSONSchemaTests: XCTestCase {

    func testEncodesScalars() {
        XCTAssertEqual(JSONSchema.string.jsonText, #"{"type":"string"}"#)
        XCTAssertEqual(JSONSchema.integer.jsonText, #"{"type":"integer"}"#)
    }

    func testEncodesStringEnum() {
        XCTAssertEqual(
            JSONSchema.stringEnum(["a", "b"]).jsonText,
            #"{"type":"string","enum":["a","b"]}"#
        )
    }

    func testEncodesArray() {
        XCTAssertEqual(
            JSONSchema.array(of: .integer).jsonText,
            #"{"type":"array","items":{"type":"integer"}}"#
        )
    }

    /// **적은 순서 그대로 나가야 한다.** 이름순으로 정렬되면 안 된다 —
    /// 순서가 곧 문법이라 정렬은 «다른 스키마» 를 보내는 것과 같다.
    func testKeepsDeclaredPropertyOrder() {
        let schema = JSONSchema.object(
            properties: [
                .init("zebra", .string),
                .init("apple", .integer),
            ],
            required: ["zebra"]
        )
        XCTAssertEqual(
            schema.jsonText,
            #"{"type":"object","properties":{"zebra":{"type":"string"},"apple":{"type":"integer"}},"required":["zebra"]}"#
        )
    }

    /// 같은 스키마는 **매번 같은 바이트**로 나가야 한다.
    func testEncodingIsStable() {
        let schema = JSONSchema.object(
            properties: [.init("b", .string), .init("a", .string), .init("c", .integer)],
            required: ["c", "a"]
        )
        let first = schema.jsonText
        for _ in 0..<20 {
            XCTAssertEqual(schema.jsonText, first)
        }
    }

    // MARK: - 실제로 쓰는 두 스키마

    /// `resultType` 은 **반드시 맨 앞**이어야 한다.
    ///
    /// 뒤로 밀리면 모델이 (프롬프트 예시대로) 그것부터 쓰는 순간 `suggestions` 가 등 뒤에 놓여
    /// 배열을 못 쓰고 객체가 닫힌다. 실측(2026-08-25) 골든셋 62건 중 56건이 이렇게
    /// `{"resultType": "suggestions"}` 14토큰으로 끝났다.
    func testResultTypeComesFirst() {
        for (name, json) in [
            ("weekly", WeeklyGoalTask.responseSchema.jsonText),
            ("monthly", MonthlyGoalTask.responseSchema.jsonText),
        ] {
            XCTAssertTrue(json.hasPrefix(#"{"type":"object","properties":{"resultType":"#), "\(name): \(json)")
            let resultType = json.range(of: #""resultType""#)!.lowerBound
            let suggestions = json.range(of: #""suggestions":{"type":"array""#)!.lowerBound
            let guidance = json.range(of: #""guidance""#)!.lowerBound
            XCTAssertLessThan(resultType, suggestions, "\(name): resultType 이 suggestions 보다 앞이어야 한다")
            XCTAssertLessThan(resultType, guidance, "\(name): resultType 이 guidance 보다 앞이어야 한다")
        }
    }

    /// `resultType` 은 세 값으로 못 박혀야 한다. 자유 문자열이면 갈 곳 없는 추론이 그리로 샌다
    /// (실측: `"resultType": "guidance, noSuggestion"` → `decodeFailed`).
    func testResultTypeIsConstrainedToThreeValues() {
        let expected = #""resultType":{"type":"string","enum":["suggestions","guidance","noSuggestion"]}"#
        XCTAssertTrue(WeeklyGoalTask.responseSchema.jsonText.contains(expected))
        XCTAssertTrue(MonthlyGoalTask.responseSchema.jsonText.contains(expected))
    }

    /// 주간은 할일 **번호**를 받는다. `items` 가 정수 배열이라
    /// `[[16],[17]]` 같은 중첩(실측 2026-08-19/20)은 애초에 만들 수 없다.
    func testWeeklySchemaTakesIntegerItems() {
        let json = WeeklyGoalTask.responseSchema.jsonText
        XCTAssertTrue(json.contains(#""items":{"type":"array","items":{"type":"integer"}}"#), json)
        XCTAssertTrue(json.contains(#""required":["items","reason","title"]"#), json)
    }

    /// 월간은 주간 목표의 **UUID 문자열**을 받는다 — 주간과 타입이 다르다.
    func testMonthlySchemaTakesStringGoalIDs() {
        let json = MonthlyGoalTask.responseSchema.jsonText
        XCTAssertTrue(json.contains(#""goalIDs":{"type":"array","items":{"type":"string"}}"#), json)
        XCTAssertTrue(json.contains(#""required":["goalIDs","reason","title"]"#), json)
    }

    /// 파서가 기본값을 채우는 필드는 **필수로 걸지 않는다.**
    /// 모델에게 지어내라고 시키면 토큰만 쓰고 내용도 나빠진다.
    func testOptionalFieldsAreNotRequired() {
        let weekly = WeeklyGoalTask.responseSchema.jsonText
        XCTAssertFalse(weekly.contains(#""required":["emoji"#), weekly)
        XCTAssertTrue(weekly.contains(#""emoji":{"type":"string"}"#), weekly)
    }

    // MARK: - 전송되는 본문

    /// 스키마 순서가 **요청 본문까지** 살아서 가는지 본다.
    ///
    /// `JSONSchema` 단위로만 검사하면 인코더가 중간에서 순서를 흐트러뜨리는 것을 못 잡는다.
    /// 실제로 그게 이번 사고였다 — 스키마 쪽 코드는 순서를 정하고 있었는데 전송된 바이트는 달랐다.
    func testRequestBodyKeepsSchemaOrder() throws {
        let body = try OllamaChatClient.body(
            OllamaChatClient.ChatRequest(
                model: "m",
                messages: [.init(role: "user", content: "안녕")],
                stream: true,
                think: false,
                options: .init(
                    temperature: 0.3,
                    num_predict: 10,
                    repeat_penalty: nil,
                    presence_penalty: nil,
                    frequency_penalty: nil
                )
            ),
            format: WeeklyGoalTask.responseSchema
        )
        let text = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertTrue(
            text.contains(#""format":{"type":"object","properties":{"resultType":"#),
            text
        )
        // 붙여 쓴 JSON 이 실제로 유효한지도 확인한다 — 문자열 조작이라 깨지면 조용히 400 이 난다.
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: body))
    }

    /// `format` 이 없으면 키 자체가 안 나가야 한다(예전처럼 자유 출력).
    func testRequestBodyOmitsFormatWhenNil() throws {
        let body = try OllamaChatClient.body(
            OllamaChatClient.ChatRequest(
                model: "m",
                messages: [.init(role: "user", content: "안녕")],
                stream: true,
                think: false,
                options: .init(
                    temperature: 0.3,
                    num_predict: 10,
                    repeat_penalty: nil,
                    presence_penalty: nil,
                    frequency_penalty: nil
                )
            ),
            format: nil
        )
        let text = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertFalse(text.contains(#""format""#), text)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: body))
    }
}
