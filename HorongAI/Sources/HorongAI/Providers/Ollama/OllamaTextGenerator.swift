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

    public struct GenerationOutput: Sendable {
        public let text: String
        public let usage: RunRecord.UsageSummary?

        public init(text: String, usage: RunRecord.UsageSummary? = nil) {
            self.text = text
            self.usage = usage
        }
    }

    public func generate(
        prompt: String,
        instructions: String,
        temperature: Double,
        maxTokens: Int,
        repeatPenalty: Double? = nil,
        presencePenalty: Double? = nil,
        frequencyPenalty: Double? = nil,
        format: JSONSchema? = nil,
        timeoutInterval: TimeInterval = 180.0
    ) async throws -> String {
        try await generateWithUsage(
            prompt: prompt,
            instructions: instructions,
            temperature: temperature,
            maxTokens: maxTokens,
            repeatPenalty: repeatPenalty,
            presencePenalty: presencePenalty,
            frequencyPenalty: frequencyPenalty,
            format: format,
            timeoutInterval: timeoutInterval
        ).text
    }

    public func generateWithUsage(
        prompt: String,
        instructions: String,
        temperature: Double,
        maxTokens: Int,
        repeatPenalty: Double? = nil,
        presencePenalty: Double? = nil,
        frequencyPenalty: Double? = nil,
        /// 응답의 모양을 강제하는 스키마. `nil` 이면 예전처럼 프롬프트로 부탁만 한다.
        format: JSONSchema? = nil,
        timeoutInterval: TimeInterval = 180.0
    ) async throws -> GenerationOutput {
        let client = OllamaChatClient(endpoint: endpoint, model: model)
        var text = ""
        var usage: RunRecord.UsageSummary? = nil
        for try await update in client.streamUpdates(
            messages: [
                .init(role: "system", content: instructions),
                .init(role: "user", content: prompt),
            ],
            temperature: temperature,
            maxTokens: maxTokens,
            repeatPenalty: repeatPenalty,
            presencePenalty: presencePenalty,
            frequencyPenalty: frequencyPenalty,
            format: format,
            requestTimeoutInterval: timeoutInterval
        ) {
            text = update.text
            if let u = update.usage {
                usage = RunRecord.UsageSummary(tokensIn: u.promptTokens, tokensOut: u.completionTokens)
            }
        }
        return GenerationOutput(text: text, usage: usage)
    }
}
