import HorongAI
import Foundation
import OSLog

/// Ollama 서버로 목표 후보를 만든다.
///
/// MLX와 달리 가중치가 **다른 프로세스**에 올라가므로, 앱 메모리를 잡아먹지 않는다.
/// 그래서 앱 안에서는 못 올리는 큰 모델(20GB대)도 쓸 수 있고, MoE 구조도 Ollama가 알아서 처리한다.
///
/// 프롬프트와 파서는 AFM·MLX 경로와 같은 것을 쓴다 — 그래야 골든셋에서 공정하게 비교된다.
@available(macOS 26.0, *)
struct OllamaGoalSuggestionProvider {

    let model: String
    let endpoint: String

    init(
        model: String = Constants.defaultAchievementSuggestionOllamaModel,
        endpoint: String = Constants.defaultNewsOllamaEndpoint
    ) {
        self.model = model
        self.endpoint = endpoint
    }

    func suggestions(
        from memos: [AchievementMemoSnapshot],
        suggestionCount: Int,
        maxMemoCount: Int
    ) async -> [AchievementGoalSuggestion] {
        let shared = FoundationModelsGoalSuggestionProvider()
        let budget = Constants.achievementPromptCharacterBudget(for: .ollama)
        let inputLimit = max(8, min(60, suggestionCount * maxMemoCount * 3))
        let selected = shared.memosWithinPromptBudget(
            Array(memos.prefix(inputLimit)),
            suggestionCount: suggestionCount,
            maxMemoCount: maxMemoCount,
            budget: budget
        )
        let prompt = shared.prompt(
            for: selected,
            suggestionCount: suggestionCount,
            maxMemoCount: maxMemoCount
        )

        achievementSuggestionLog.info(
            """
            weekly ollama prompt chars=\(prompt.count, privacy: .public) \
            memos=\(selected.count, privacy: .public) model=\(model, privacy: .public)
            """
        )

        guard await OllamaChatClient.isReachable(endpoint: endpoint) else {
            achievementSuggestionLog.error("weekly ollama failure=serverUnavailable")
            return []
        }

        do {
            let client = OllamaChatClient(endpoint: endpoint, model: model)
            var text = ""
            for try await piece in client.stream(
                messages: [
                    .init(
                        role: "system",
                        content: "너는 사용자의 할일을 목표 지향적으로 묶어주는 생산성 앱 도우미다. 응답은 반드시 유효한 JSON만 출력한다."
                    ),
                    .init(role: "user", content: prompt),
                ],
                temperature: 0.2,
                maxTokens: 1_200
            ) {
                // `stream` 은 조각이 아니라 **매번 지금까지의 전문**을 준다. 더하면
                // "A" + "AB" + "ABC" 가 되어 JSON 이 깨지고 조용히 AFM 으로 폴백한다.
                text = piece
            }

            let parsed = Array(shared.parse(
                text,
                allowedIDs: Set(memos.map(\.id)),
                suggestionCount: suggestionCount,
                maxMemoCount: maxMemoCount
            ).prefix(suggestionCount))
            if parsed.isEmpty {
                achievementSuggestionLog.error(
                    "weekly ollama failure=\(AchievementSuggestionModelFailure.parsedEmpty.rawValue, privacy: .public)"
                )
            }
            // 파서를 AFM 경로와 공유하므로 실제 공급자로 다시 태깅한다.
            return parsed.map { $0.retagged(as: .ollama) }
        } catch {
            achievementSuggestionLog.error(
                """
                weekly ollama failure=\(AchievementSuggestionModelFailure.inferenceFailed.rawValue, privacy: .public) \
                error=\(String(describing: error).prefix(200), privacy: .public)
                """
            )
            return []
        }
    }
}
