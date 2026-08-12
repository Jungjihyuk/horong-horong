import Foundation

/// Ollama 로 돌아가는 공급자.
///
/// Apple 온디바이스 모델과 달리 사용자가 Ollama 를 설치하고 모델을 받아야 한다.
/// 대신 더 큰 모델을 쓸 수 있어 긴 프롬프트와 복잡한 지시를 훨씬 잘 견딘다.
@MainActor
public final class OllamaProvider: LLMProvider {
    private let endpoint: String
    private let model: String
    private let reachable: Bool

    public let capabilities: ProviderCapabilities

    /// `reachable` 은 지금 **호출하는 쪽이 미리 확인해서 넣어 준다**(`OllamaChatClient.isReachable`).
    /// 공급자가 스스로 확인하는 계약(`ProviderReadiness`)은 그 로직을 옮길 때 만든다.
    public init(
        endpoint: String,
        model: String,
        reachable: Bool,
        capabilities: ProviderCapabilities = ProviderCapabilities(maxPromptCharacters: 16_000)
    ) {
        self.endpoint = endpoint
        self.model = model
        self.reachable = reachable
        self.capabilities = capabilities
    }

    public var id: String { "ollama" }
    public var displayName: String { "Ollama · \(model)" }
    public var isAvailable: Bool { reachable }

    public func makeSession(_ setup: SessionSetup) -> LLMSession {
        OllamaSession(
            client: OllamaChatClient(endpoint: endpoint, model: model),
            instructions: setup.instructions
        )
    }
}

@MainActor
final class OllamaSession: LLMSession {
    private let client: OllamaChatClient
    /// 대화 문맥. Ollama 는 세션을 기억하지 않으므로 우리가 들고 다닌다.
    private(set) var messages: [OllamaChatClient.Message]

    /// 문맥이 무한정 늘어나지 않도록 최근 것만 남긴다(system 은 항상 유지).
    static let maxTurns = 12
    /// 답이 길어지면 말풍선을 넘친다.
    private static let maxTokens = 300

    init(client: OllamaChatClient, instructions: String) {
        self.client = client
        self.messages = [.init(role: "system", content: instructions)]
    }

    func reply(
        to message: String,
        decoding: DecodingOptions,
        onPartial: @escaping (LLMResponse) -> Void
    ) async -> LLMResponse {
        messages.append(.init(role: "user", content: message))
        trimHistory()

        do {
            var text = ""
            for try await partial in client.stream(
                messages: messages,
                temperature: decoding.temperature,
                maxTokens: decoding.maxTokens ?? Self.maxTokens
            ) {
                text = partial
                onPartial(LLMResponse(text: partial))
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            messages.append(.init(role: "assistant", content: trimmed))
            return LLMResponse(text: trimmed)
        } catch {
            NSLog("[OLLAMA] 실패: \(error)")
            messages.removeLast()
            return LLMResponse(
                text: "Ollama 에 연결하지 못했어요. 서버가 켜져 있는지, 모델이 설치돼 있는지 확인해 주세요.",
                mood: "concerned"
            )
        }
    }

    private func trimHistory() {
        messages = Self.trimmed(messages)
    }

    /// system 한 줄은 남기고 나머지를 최근 것부터 `maxTurns` 개만 유지한다.
    ///
    /// 순수 함수로 둔 이유는 네트워크 없이 검증하기 위해서다 —
    /// 캐릭터 설정(system)이 잘려 나가면 말투가 통째로 바뀌는데, 그건 조용히 일어난다.
    static func trimmed(_ messages: [OllamaChatClient.Message]) -> [OllamaChatClient.Message] {
        let system = messages.first
        var rest = messages.dropFirst()
        while rest.count > maxTurns {
            rest = rest.dropFirst()
        }
        return ([system].compactMap { $0 }) + rest
    }
}
