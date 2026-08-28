import Foundation
import HorongAI

#if canImport(MLXLLM)
import MLXLLM
import MLXLMCommon

/// MLX 로 돌아가는 대화 공급자.
///
/// Ollama 와 달리 사용자가 따로 설치할 프로그램이 없다. 모델 가중치만 한 번 내려받으면
/// 앱이 직접 Metal 로 추론한다. 대신 그 가중치가 이 앱의 메모리를 그대로 차지한다.
@MainActor
public final class MLXProvider: LLMProvider {
    private let model: String
    private let modelLabel: String

    public let capabilities: ProviderCapabilities

    /// `modelLabel` 은 설정 화면에 보여줄 사람이 읽는 이름이다.
    /// 그 표는 앱이 들고 있으므로(`Constants.companionMLXModelLabel`) 만들어서 넘겨준다.
    public init(
        model: String,
        modelLabel: String? = nil,
        capabilities: ProviderCapabilities = ProviderCapabilities(maxPromptCharacters: 16_000)
    ) {
        self.model = model
        self.modelLabel = modelLabel ?? model
        self.capabilities = capabilities
    }

    public var id: String { "mlx" }
    public var displayName: String { "MLX · \(modelLabel)" }
    public var isAvailable: Bool { MLXModelStore.isSupported }

    public func makeSession(_ setup: SessionSetup) -> LLMSession {
        MLXSession(model: model, instructions: setup.instructions)
    }
}

@MainActor
private final class MLXSession: LLMSession {
    private let model: String
    private let instructions: String
    /// MLX 의 `ChatSession` 이 대화 문맥(KV 캐시)을 직접 들고 있어서 Ollama 쪽처럼
    /// 우리가 메시지 배열을 나를 필요가 없다. 첫 대화 때 모델을 올리며 만든다.
    private var session: ChatSession?

    /// 답이 길어지면 말풍선을 넘친다.
    private static let maxTokens = 300

    init(model: String, instructions: String) {
        self.model = model
        self.instructions = instructions
    }

    func reply(
        to message: String,
        decoding: DecodingOptions,
        onPartial: @escaping (LLMResponse) -> Void
    ) async -> LLMResponse {
        do {
            let session = try await currentSession()
            session.generateParameters = GenerateParameters(
                maxTokens: decoding.maxTokens ?? Self.maxTokens,
                temperature: Float(decoding.temperature)
            )

            var text = ""
            for try await piece in session.streamResponse(to: message) {
                text += piece
                onPartial(LLMResponse(text: text))
            }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw MLXChatError.emptyResponse }
            return LLMResponse(text: trimmed)
        } catch is MLXChatError {
            return LLMResponse(
                text: "아직 모델이 준비되지 않았어요. 설정 → 컴패니언 → AI 대화의 모델 목록에서 내려받기 아이콘을 눌러 주세요.",
                mood: "concerned"
            )
        } catch {
            AILog.providers.error(
                "mlx failure=reply error=\(String(describing: error), privacy: .private)"
            )
            return LLMResponse(
                text: "모델을 불러오지 못했어요. 설정에서 모델이 다 내려받아졌는지 확인해 주세요.",
                mood: "concerned"
            )
        }
    }

    private func currentSession() async throws -> ChatSession {
        if let session { return session }

        let created = ChatSession(
            try await container(),
            instructions: instructions,
            // Ollama 쪽 `think: false` 와 같은 뜻. qwen3 계열은 기본이 추론 모드라
            // 생각하는 데 토큰을 다 쓰고 빈 답을 준다.
            additionalContext: ["enable_thinking": false]
        )
        session = created
        return created
    }

    private func container() async throws -> ModelContainer {
        try await MLXModelStore.preparedContainer(for: model)
    }
}
#endif
