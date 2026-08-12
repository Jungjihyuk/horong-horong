import HorongAI
import Foundation

/// Ollama 로 돌아가는 대화 공급자.
///
/// Apple 온디바이스 모델과 달리 사용자가 Ollama 를 설치하고 모델을 받아야 한다.
/// 대신 더 큰 모델을 쓸 수 있어 긴 프롬프트와 복잡한 지시를 훨씬 잘 견딘다.
@MainActor
final class OllamaCompanionChatProvider: CompanionChatProvider {
    private let endpoint: String
    private let model: String
    private let reachable: Bool

    init(endpoint: String, model: String, reachable: Bool) {
        self.endpoint = endpoint
        self.model = model
        self.reachable = reachable
    }

    var displayName: String { "Ollama · \(model)" }
    var isAvailable: Bool { reachable }

    func makeSession(_ context: CompanionChatContext) -> CompanionChatSession {
        OllamaCompanionChatSession(
            client: OllamaChatClient(endpoint: endpoint, model: model),
            instructions: CompanionPromptTemplate.instructions(
                for: context.character,
                profile: context.profile
            )
        )
    }
}

@MainActor
private final class OllamaCompanionChatSession: CompanionChatSession {
    private let client: OllamaChatClient
    /// 대화 문맥. Ollama 는 세션을 기억하지 않으므로 우리가 들고 다닌다.
    private var messages: [OllamaChatClient.Message]

    /// 문맥이 무한정 늘어나지 않도록 최근 것만 남긴다(system 은 항상 유지).
    private static let maxTurns = 12

    init(client: OllamaChatClient, instructions: String) {
        self.client = client
        self.messages = [.init(role: "system", content: instructions)]
    }

    func reply(
        to message: String,
        precise: Bool,
        onPartial: @escaping (CompanionChatReply) -> Void
    ) async -> CompanionChatReply {
        messages.append(.init(role: "user", content: message))
        trimHistory()

        do {
            var text = ""
            for try await partial in client.stream(
                messages: messages,
                temperature: precise ? 0.2 : 0.4,
                maxTokens: 300
            ) {
                text = partial
                onPartial(CompanionChatReply(text: partial, mood: nil))
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            messages.append(.init(role: "assistant", content: trimmed))
            return CompanionChatReply(text: trimmed, mood: nil)
        } catch {
            NSLog("[OLLAMA] 실패: \(error)")
            messages.removeLast()
            return CompanionChatReply(
                text: "Ollama 에 연결하지 못했어요. 서버가 켜져 있는지, 모델이 설치돼 있는지 확인해 주세요.",
                mood: .concerned
            )
        }
    }

    private func trimHistory() {
        let system = messages.first
        var rest = messages.dropFirst()
        while rest.count > Self.maxTurns {
            rest = rest.dropFirst()
        }
        messages = ([system].compactMap { $0 }) + rest
    }
}
