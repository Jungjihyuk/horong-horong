import Foundation

#if canImport(MLXLLM)
import MLXLLM
import MLXLMCommon

/// MLX 로 돌아가는 대화 공급자.
///
/// Ollama 와 달리 사용자가 따로 설치할 프로그램이 없다. 모델 가중치만 한 번 내려받으면
/// 앱이 직접 Metal 로 추론한다. 대신 그 가중치가 이 앱의 메모리를 그대로 차지한다.
@MainActor
final class MLXCompanionChatProvider: CompanionChatProvider {
    private let model: String

    init(model: String) {
        self.model = model
    }

    var displayName: String { "MLX · \(Constants.companionMLXModelLabel(for: model))" }
    var isAvailable: Bool { MLXModelStore.isSupported }

    func makeSession(_ context: CompanionChatContext) -> CompanionChatSession {
        MLXCompanionChatSession(
            model: model,
            instructions: CompanionPromptTemplate.instructions(
                for: context.character,
                profile: context.profile
            )
        )
    }
}

@MainActor
private final class MLXCompanionChatSession: CompanionChatSession {
    private let model: String
    private let instructions: String
    /// MLX 의 `ChatSession` 이 대화 문맥(KV 캐시)을 직접 들고 있어서 Ollama 쪽처럼
    /// 우리가 메시지 배열을 나를 필요가 없다. 첫 대화 때 모델을 올리며 만든다.
    private var session: ChatSession?

    init(model: String, instructions: String) {
        self.model = model
        self.instructions = instructions
    }

    func reply(
        to message: String,
        precise: Bool,
        onPartial: @escaping (CompanionChatReply) -> Void
    ) async -> CompanionChatReply {
        do {
            let session = try await currentSession()
            session.generateParameters = GenerateParameters(
                maxTokens: 300,
                temperature: precise ? 0.2 : 0.4
            )

            var text = ""
            for try await piece in session.streamResponse(to: message) {
                text += piece
                onPartial(CompanionChatReply(text: text, mood: nil))
            }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw MLXChatError.emptyResponse }
            return CompanionChatReply(text: trimmed, mood: nil)
        } catch is MLXChatError {
            return CompanionChatReply(
                text: "아직 모델이 준비되지 않았어요. 설정 → 컴패니언 → AI 대화의 모델 목록에서 내려받기 아이콘을 눌러 주세요.",
                mood: .concerned
            )
        } catch {
            NSLog("[MLX] 실패: \(error)")
            return CompanionChatReply(
                text: "모델을 불러오지 못했어요. 설정에서 모델이 다 내려받아졌는지 확인해 주세요.",
                mood: .concerned
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

    /// 대화 도중에는 **내려받지 않는다.** 이미 메모리에 있으면 그걸 쓰고,
    /// 예전에 끝까지 준비해 둔 모델이면 디스크에서 올리는 것까지만 허용한다.
    /// 한 번도 준비한 적 없는 모델은 설정 화면으로 안내한다 — 말 한마디에 수 GB 가 받아지면 안 된다.
    private func container() async throws -> ModelContainer {
        if let loaded = await MLXModelStore.shared.loadedContainer(for: model) {
            return loaded
        }
        guard MLXModelStore.isKnownPrepared(model) else {
            throw MLXChatError.notPrepared
        }
        return try await MLXModelStore.shared.container(for: model)
    }
}
#endif
