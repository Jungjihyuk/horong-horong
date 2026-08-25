import Foundation

/// 모델이 낼 수 있는 **응답의 모양**을 미리 못 박는 스키마.
///
/// 지금까지는 프롬프트로 «이런 JSON 으로 답해줘» 라고 **부탁**만 했다. 모델이 안 들으면
/// 그만이라 실측(2026-08-19/20)에서 두 갈래로 새어 나갔다.
/// - `gemma-4-e4b` 가 id 를 `[[16],[17]]` 로 한 겹 더 감쌌다 → `typeMismatch`
/// - `qwen3:4b` 가 JSON 대신 영어로 생각을 늘어놓다 토큰 한도에 걸렸다 → `noJSON`
///
/// 스키마를 함께 보내면 **모양을 어기는 토큰이 후보에서 빠져** 그런 답을 아예 만들 수 없다.
/// 파서 쪽 방어(`GoalSuggestionPayload.IDList`)가 «틀린 걸 받아 주는» 그물이라면,
/// 이쪽은 «틀린 게 안 나오게» 막는 울타리다. 둘은 대체 관계가 아니다 —
/// 이 장치를 못 쓰는 공급자가 있기 때문이다.
///
/// 지금은 Ollama(`format`)만 이 값을 받는다. AFM 은 `@Generable`, MLX 는 `LogitProcessor` 로
/// 직접 만들어야 해서 장치가 저마다 다르다. 그래서 여기서는 **표현만** 정하고,
/// 각 공급자가 자기 방식으로 옮긴다.
///
/// ## 순서가 의미를 갖는다
///
/// Ollama 는 이 스키마를 **문법(GBNF)** 으로 바꿔 디코딩을 제약한다. 객체의 속성은 여기 적힌
/// 순서를 따라가며, **앞선 속성으로 되돌아갈 수 없다.** 그래서 속성 순서는 장식이 아니라
/// 생성 가능한 답을 결정하는 값이다(→ `case object`, `jsonText`).
public indirect enum JSONSchema: Sendable, Equatable {
    case string
    /// 값을 몇 개로 못 박은 문자열.
    ///
    /// 제약 없는 `.string` 은 응답 맨 앞에 **무제한 자유 칸**을 여는 것과 같다. `think: false` 로
    /// 사고 채널을 막아 두면 갈 곳 없는 추론이 그리로 샌다 —
    /// 실측(2026-08-25): `"resultType": "suggestions, guidance mixed? No, strict JSON. Let's analyze first.…"`
    case stringEnum([String])
    case integer
    case array(of: JSONSchema)
    /// **속성 순서가 그대로 문법이 된다.** `[String: JSONSchema]` 로 두면 순서를 표현할 수 없어
    /// 인코더 마음대로 나가는데, 그게 실제로 사고를 냈다(2026-08-25) — `resultType` 이 맨 뒤로
    /// 밀리자 모델이 그걸 먼저 쓰는 순간 `suggestions` 가 등 뒤에 놓여, 배열을 못 쓰고
    /// 객체를 닫아 버렸다(14토큰, 빈 결과). 그래서 딕셔너리가 아니라 **순서 있는 배열**이다.
    ///
    /// `required` 에 없는 키는 모델이 **빼도 된다.** 우리 파서가 기본값을 채우는 필드
    /// (`scheduleText` · `criterion` 등)까지 필수로 걸면, 모델이 그걸 지어내느라
    /// 토큰을 쓰고 내용도 나빠진다.
    case object(properties: [Property], required: [String])

    /// 이름과 모양을 **순서까지 담아** 들고 다니는 한 쌍.
    public struct Property: Sendable, Equatable {
        public let name: String
        public let schema: JSONSchema

        public init(_ name: String, _ schema: JSONSchema) {
            self.name = name
            self.schema = schema
        }
    }
}

extension JSONSchema {
    /// 실제로 전송되는 JSON 텍스트.
    ///
    /// **`Encodable` 이 아니라 손으로 쓰는 이유가 순서다.** `JSONEncoder` 는 `.sortedKeys` 없이는
    /// 객체 키 순서를 보장하지 않고, 그 순서는 프로세스마다 달라진다. 예전 코드에는
    /// `properties.keys.sorted()` 와 «출력이 매번 같아야 한다» 는 주석이 있었지만
    /// **인코더가 그 순서를 버려서 아무 효과도 없었다**(실측 2026-08-25: 정렬이면
    /// `guidance, resultType, suggestions` 여야 할 것이 `suggestions, guidance, resultType` 으로 나갔다).
    ///
    /// `.sortedKeys` 로 켜는 것도 답이 아니다. 정렬하면 `guidance` 가 `resultType` 보다 앞이라
    /// **guidance 응답 경로가 막힌다.** 알파벳 순서가 우연히 맞아떨어지길 기대하는 설계는
    /// 다음 필드 이름 하나에 다시 깨진다.
    public var jsonText: String {
        switch self {
        case .string:
            return #"{"type":"string"}"#
        case .stringEnum(let values):
            let list = values.map(Self.quoted).joined(separator: ",")
            return #"{"type":"string","enum":[\#(list)]}"#
        case .integer:
            return #"{"type":"integer"}"#
        case .array(let element):
            return #"{"type":"array","items":\#(element.jsonText)}"#
        case .object(let properties, let required):
            let props = properties
                .map { #"\#(Self.quoted($0.name)):\#($0.schema.jsonText)"# }
                .joined(separator: ",")
            let requiredList = required.map(Self.quoted).joined(separator: ",")
            return #"{"type":"object","properties":{\#(props)},"required":[\#(requiredList)]}"#
        }
    }

    /// 손으로 만드는 JSON 이라 escape 만은 표준 도구에 맡긴다.
    /// 지금 들어오는 값은 우리가 정한 ASCII 이름뿐이지만, 그 전제가 코드에 적혀 있지 않다.
    private static func quoted(_ text: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed]),
              let quoted = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return quoted
    }
}
