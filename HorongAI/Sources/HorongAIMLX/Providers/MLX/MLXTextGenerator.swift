import Foundation
import HorongAI

#if canImport(MLXLLM)
import MLXLLM
import MLXLMCommon

/// 프롬프트 하나로 **한 덩어리 텍스트**를 받아오는 MLX 경로.
///
/// 대화용 `MLXProvider` 와 나눈 이유는 `OllamaTextGenerator` 와 같다 —
/// 대화는 실패해도 사과 문구를 반환하지만, 태스크는 실패가 던져져야 다음 공급자로 내려간다.
///
/// AFM 대비 이점은 모델 크기가 아니라 **컨텍스트 폭**이다. AFM 은 약 4k 에서 추론이 거부되지만
/// MLX 모델은 훨씬 넓어, 같은 할 일 목록에서 더 많은 항목을 한 번에 보여줄 수 있다.
public struct MLXTextGenerator: Sendable {
    private let model: String

    public init(model: String) {
        self.model = model
    }

    public func generate(
        prompt: String,
        instructions: String,
        temperature: Double,
        maxTokens: Int
    ) async throws -> String {
        let session = ChatSession(
            try await MLXModelStore.preparedContainer(for: model),
            instructions: instructions,
            // qwen3 계열은 기본이 추론 모드라 생각하는 데 토큰을 다 쓰고 빈 답을 준다.
            additionalContext: ["enable_thinking": false]
        )
        session.generateParameters = GenerateParameters(
            maxTokens: maxTokens,
            temperature: Float(temperature)
        )

        var text = ""
        for try await piece in session.streamResponse(to: prompt) {
            text += piece
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MLXChatError.emptyResponse }
        return trimmed
    }
}
#endif
