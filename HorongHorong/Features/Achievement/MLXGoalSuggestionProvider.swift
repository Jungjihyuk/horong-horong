import HorongAIMLX
import Foundation
import OSLog

#if canImport(MLXLLM)
import MLXLMCommon

/// 앱 안에서 도는 MLX 모델로 목표 후보를 만든다.
///
/// 모델 로딩·다운로드·메모리 관리는 컴패니언이 쓰는 `MLXModelStore`를 그대로 재사용한다.
/// 프롬프트와 파서도 AFM 경로와 같은 것을 쓴다 — 그래야 골든셋에서 두 모델을 공정하게 비교할 수 있다.
///
/// AFM 대비 이점은 모델 크기가 아니라 **컨텍스트 폭**이다. AFM은 약 4k에서 추론이 거부되지만
/// MLX 모델은 훨씬 넓어, 같은 할 일 목록에서 더 많은 항목을 한 번에 보여줄 수 있다.
@available(macOS 26.0, *)
struct MLXGoalSuggestionProvider {

    let model: String
    private let budget: Int

    init(model: String = Constants.defaultAchievementSuggestionMLXModel) {
        self.model = model
        self.budget = Constants.achievementPromptCharacterBudget(for: .mlx)
    }

    func suggestions(
        from memos: [AchievementMemoSnapshot],
        suggestionCount: Int,
        maxMemoCount: Int
    ) async -> [AchievementGoalSuggestion] {
        let shared = FoundationModelsGoalSuggestionProvider()
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
            weekly mlx prompt chars=\(prompt.count, privacy: .public) \
            memos=\(selected.count, privacy: .public) model=\(model, privacy: .public)
            """
        )

        do {
            let text = try await generate(prompt: prompt)
            let parsed = Array(shared.parse(
                text,
                allowedIDs: Set(memos.map(\.id)),
                suggestionCount: suggestionCount,
                maxMemoCount: maxMemoCount
            ).prefix(suggestionCount))
            if parsed.isEmpty {
                achievementSuggestionLog.error(
                    "weekly mlx failure=\(AchievementSuggestionModelFailure.parsedEmpty.rawValue, privacy: .public)"
                )
            }
            // 파서는 AFM 경로와 공유하므로 source 가 .foundationModel 로 붙는다. MLX 결과로 다시 태깅한다.
            return parsed.map { $0.retagged(as: .mlx) }
        } catch {
            achievementSuggestionLog.error(
                """
                weekly mlx failure=\(AchievementSuggestionModelFailure.inferenceFailed.rawValue, privacy: .public) \
                error=\(String(describing: error).prefix(300), privacy: .public)
                """
            )
            return []
        }
    }

    // MARK: - 추론

    private func generate(prompt: String) async throws -> String {
        let container = try await container()
        let session = ChatSession(
            container,
            instructions: "너는 사용자의 할일을 목표 지향적으로 묶어주는 생산성 앱 도우미다. 응답은 반드시 유효한 JSON만 출력한다.",
            // qwen3 계열은 기본이 추론 모드라 생각하는 데 토큰을 다 쓰고 빈 답을 준다.
            additionalContext: ["enable_thinking": false]
        )
        session.generateParameters = GenerateParameters(maxTokens: 1_200, temperature: 0.2)

        var text = ""
        for try await piece in session.streamResponse(to: prompt) {
            text += piece
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MLXChatError.emptyResponse }
        return trimmed
    }

    /// 추천 도중에는 **내려받지 않는다.** 컴패니언과 같은 원칙이다 —
    /// 버튼 한 번에 수 GB 다운로드가 시작되면 안 된다.
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
