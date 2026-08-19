import XCTest
@testable import HorongAI

/// 스키마가 **Ollama 가 알아듣는 JSON Schema 모양**으로 나가는지 못 박는다.
///
/// 이 값이 틀리면 서버가 요청을 거절하거나(400) 제약이 조용히 안 걸린다. 후자가 더 나쁘다 —
/// 아무 일도 안 일어난 것처럼 보이는데 모양 강제가 사라진 상태로 계속 돌기 때문이다.
final class JSONSchemaTests: XCTestCase {

    private func encoded(_ schema: JSONSchema) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(data: try encoder.encode(schema), encoding: .utf8)!
    }

    func testEncodesScalars() throws {
        XCTAssertEqual(try encoded(.string), #"{"type":"string"}"#)
        XCTAssertEqual(try encoded(.integer), #"{"type":"integer"}"#)
    }

    func testEncodesArray() throws {
        XCTAssertEqual(
            try encoded(.array(of: .integer)),
            #"{"items":{"type":"integer"},"type":"array"}"#
        )
    }

    func testEncodesObjectWithRequiredKeys() throws {
        let schema = JSONSchema.object(
            properties: ["title": .string, "items": .array(of: .integer)],
            required: ["title"]
        )
        XCTAssertEqual(
            try encoded(schema),
            #"{"properties":{"items":{"items":{"type":"integer"},"type":"array"},"title":{"type":"string"}},"required":["title"],"type":"object"}"#
        )
    }

    /// 같은 스키마는 **매번 같은 바이트**로 나가야 한다. 딕셔너리 순서가 흔들리면
    /// 요청이 달라져 서버 쪽 캐시나 비교가 어긋날 수 있다.
    func testEncodingIsStable() throws {
        let schema = JSONSchema.object(
            properties: ["b": .string, "a": .string, "c": .integer],
            required: ["c", "a"]
        )
        let first = try encoded(schema)
        for _ in 0..<20 {
            XCTAssertEqual(try encoded(schema), first)
        }
    }

    // MARK: - 실제로 쓰는 두 스키마

    /// 주간은 할일 **번호**를 받는다. `items` 가 정수 배열이라
    /// `[[16],[17]]` 같은 중첩(실측 2026-08-19/20)은 애초에 만들 수 없다.
    func testWeeklySchemaTakesIntegerItems() throws {
        let json = try encoded(WeeklyGoalTask.responseSchema)
        XCTAssertTrue(json.contains(#""items":{"items":{"type":"integer"},"type":"array"}"#), json)
        XCTAssertTrue(json.contains(#""required":["items","reason","title"]"#), json)
    }

    /// 월간은 주간 목표의 **UUID 문자열**을 받는다 — 주간과 타입이 다르다.
    func testMonthlySchemaTakesStringGoalIDs() throws {
        let json = try encoded(MonthlyGoalTask.responseSchema)
        XCTAssertTrue(json.contains(#""goalIDs":{"items":{"type":"string"},"type":"array"}"#), json)
        XCTAssertTrue(json.contains(#""required":["goalIDs","reason","title"]"#), json)
    }

    /// 파서가 기본값을 채우는 필드는 **필수로 걸지 않는다.**
    /// 모델에게 지어내라고 시키면 토큰만 쓰고 내용도 나빠진다.
    func testOptionalFieldsAreNotRequired() throws {
        let weekly = try encoded(WeeklyGoalTask.responseSchema)
        XCTAssertFalse(weekly.contains(#""required":["emoji"#), weekly)
        XCTAssertTrue(weekly.contains(#""emoji":{"type":"string"}"#), weekly)
    }
}
