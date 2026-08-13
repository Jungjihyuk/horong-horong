import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// 프롬프트 하나로 **한 덩어리 텍스트**를 받아오는 Apple 온디바이스 모델 경로.
///
/// 대화용 `AppleFoundationModelsProvider` 와 나눈 이유는 `Ollama`·`MLX` 쪽과 같다 —
/// 대화는 실패해도 사과 문구를 반환해야 하고, 태스크는 실패가 던져져야 다음 공급자로 내려간다.
///
/// 대화 쪽의 3단 폴백(구조화 출력 → 평문 → 세션 재생성)도 여기엔 없다. 그건 캐릭터가
/// 무슨 말이라도 하게 만드는 장치인데, 목표 추천은 **JSON 이 아니면 아무 쓸모가 없다.**
///
/// 컨텍스트가 약 4k 로 좁아 프롬프트가 커지면 추론 자체가 거부된다
/// (측정: 3,424자 통과 / 5,203자 실패, 인시던트 2026-07-31). 예산을 지키는 일은
/// 호출부(`WeeklyGoalTask.run(budget:)`)의 몫이다.
@available(macOS 26.0, *)
public struct AppleFoundationModelsTextGenerator {

    public init() {}

    /// 지금 이 기기에서 답을 만들 수 있는지. 못 만들면 호출부가 룰 기반으로 내려간다.
    public var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    public func generate(
        prompt: String,
        instructions: String,
        temperature: Double,
        maxTokens: Int
    ) async throws -> String {
        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: instructions
        )
        let response = try await session.respond(
            to: prompt,
            options: GenerationOptions(temperature: temperature, maximumResponseTokens: maxTokens)
        )
        return response.content
    }
}
#endif
