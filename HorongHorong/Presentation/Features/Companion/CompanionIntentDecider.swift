import Foundation
import HorongAI

/// Ollama 로 컴패니언의 의도를 판단한다.
///
/// 평가기(`Evals/companion_eval.py` v5)와 같은 지시문·양식·추론 설정으로 부른다. 평가가 Ollama 경로만 쟀기 때문에
/// 이 판단은 Ollama 를 골랐을 때만 쓴다. MLX·Apple 모델은 평가 전이라 기존 흐름을 유지한다.
struct CompanionIntentDecider {
    let endpoint: String
    let model: String

    /// 평가 사례의 대화 기록은 두 말풍선이었다. 길게 넣을수록 평가하지 않은 조건이 된다.
    static let historyLimit = 6

    /// Ollama 를 골랐으면 판단을 **시도한다**. 연결 여부를 미리 캐시해 막지 않는다.
    ///
    /// 연결 확인은 공급자 설정을 바꿀 때만 갱신돼서, 앱을 켠 뒤 Ollama 를 띄우면 새 흐름이 조용히 꺼져 있었다
    /// (2026-09-29). 서버가 없으면 판단이 바로 실패하고 기존 흐름으로 돌아가므로 미리 막을 이유가 없다.
    static func make(selectedOllama: (endpoint: String, model: String)?) -> CompanionIntentDecider? {
        selectedOllama.map { CompanionIntentDecider(endpoint: $0.endpoint, model: $0.model) }
    }

    func decide(
        history: [CompanionChatMessage],
        message: String,
        now: Date,
        timeZone: TimeZone = .current
    ) async throws -> CompanionIntentTask.Decision {
        let text = try await OllamaTextGenerator(endpoint: endpoint, model: model).generate(
            messages: Self.messages(history: history, message: message, now: now, timeZone: timeZone),
            temperature: CompanionIntentTask.decisionTemperature,
            maxTokens: CompanionIntentTask.decisionMaxTokens,
            format: CompanionIntentTask.decisionSchema,
            contextLength: CompanionIntentTask.decisionContextLength
        )
        return try CompanionIntentTask.parseDecision(text)
    }

    /// 지시문 + 최근 말풍선 + 이번 말. 평가기의 `decision_input` 과 같은 모양이다.
    static func messages(
        history: [CompanionChatMessage],
        message: String,
        now: Date,
        timeZone: TimeZone
    ) -> [OllamaChatClient.Message] {
        let turns = history
            .filter { !$0.text.isEmpty }
            .suffix(historyLimit)
            .map { OllamaChatClient.Message(role: $0.role == .user ? "user" : "assistant", content: $0.text) }
        return [.init(role: "system", content: CompanionIntentTask.decisionInstructions(now: now, timeZone: timeZone))]
            + turns
            + [.init(role: "user", content: message)]
    }
}
