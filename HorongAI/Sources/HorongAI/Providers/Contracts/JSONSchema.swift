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
public indirect enum JSONSchema: Encodable, Sendable, Equatable {
    case string
    case integer
    case array(of: JSONSchema)
    /// `required` 에 없는 키는 모델이 **빼도 된다.** 우리 파서가 기본값을 채우는 필드
    /// (`scheduleText` · `criterion` 등)까지 필수로 걸면, 모델이 그걸 지어내느라
    /// 토큰을 쓰고 내용도 나빠진다.
    case object(properties: [String: JSONSchema], required: [String])

    private enum Key: String, CodingKey {
        case type, items, properties, required
    }

    /// 속성 이름은 미리 알 수 없으므로 문자열을 그대로 키로 쓴다.
    private struct DynamicKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ stringValue: String) { self.stringValue = stringValue }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        switch self {
        case .string:
            try container.encode("string", forKey: .type)
        case .integer:
            try container.encode("integer", forKey: .type)
        case .array(let element):
            try container.encode("array", forKey: .type)
            try container.encode(element, forKey: .items)
        case .object(let properties, let required):
            try container.encode("object", forKey: .type)
            var props = container.nestedContainer(keyedBy: DynamicKey.self, forKey: .properties)
            // 이름순으로 넣는다. JSON 객체는 순서가 의미 없지만, **출력이 매번 같아야**
            // 테스트가 문자열을 그대로 비교할 수 있다.
            for name in properties.keys.sorted() {
                try props.encode(properties[name], forKey: DynamicKey(name))
            }
            try container.encode(required.sorted(), forKey: .required)
        }
    }
}
