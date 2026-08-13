import Foundation

/// 프롬프트 하나로 **한 덩어리 텍스트**를 받아오는 Ollama 경로.
///
/// 대화용 `OllamaProvider` 와 나눈 이유는 실패를 다루는 방식이 정반대이기 때문이다.
/// 대화는 실패해도 캐릭터가 뭐라도 말해야 해서 사과 문구를 **반환**하지만,
/// 태스크는 실패가 그대로 **던져져야** 호출부가 다음 공급자로 내려갈 수 있다.
/// 사과 문구를 JSON 파서에 넣으면 "모델이 못 만든 것"과 "서버가 죽은 것"을 구분할 수 없다.
public struct OllamaTextGenerator: Sendable {
    private let endpoint: String
    private let model: String

    public init(endpoint: String, model: String) {
        self.endpoint = endpoint
        self.model = model
    }

    /// 서버가 떠 있는지. 꺼져 있으면 시도 자체를 하지 않는다.
    public func isReachable() async -> Bool {
        await OllamaChatClient.isReachable(endpoint: endpoint)
    }

    public func generate(
        prompt: String,
        instructions: String,
        temperature: Double,
        maxTokens: Int
    ) async throws -> String {
        let client = OllamaChatClient(endpoint: endpoint, model: model)
        var text = ""
        for try await partial in client.stream(
            messages: [
                .init(role: "system", content: instructions),
                .init(role: "user", content: prompt),
            ],
            temperature: temperature,
            maxTokens: maxTokens
        ) {
            // `stream` 은 조각이 아니라 매번 지금까지의 전문을 준다(`OllamaStreamContractTests`).
            text = partial
        }
        return text
    }
}
