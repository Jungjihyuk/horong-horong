import Foundation
import HorongAI

/// 모델을 부르지 않고 **미리 정해둔 응답을 재생하는** 공급자.
///
/// 제품에 들어가지 않는다. 쓰임새는 둘이다.
/// - 평가: 실모델은 같은 프롬프트에도 매번 다르게 답해 회귀 판정에 쓸 수 없다.
///   응답을 고정하면 파서·조립·채점만 따로 검증할 수 있다.
/// - 테스트: 케이스당 수 초 걸리던 것이 밀리초가 된다.
///
/// 사용자가 보는 "고정 응답"(모델을 못 쓰는 기기의 안내 문구)과는 다른 물건이다.
/// 그쪽은 제품이라 `HorongAI/Providers/Fallback/` 에 산다.
@MainActor
public final class ReplayProvider: LLMProvider {
    /// 입력 → 정해둔 답. 없는 입력이 오면 `fallback` 을 돌려준다.
    private let script: [String: LLMResponse]
    private let fallback: LLMResponse

    public let id: String
    public let displayName: String
    public var isAvailable: Bool { true }
    public let capabilities: ProviderCapabilities

    /// 이 공급자가 받은 지시문·질문을 그대로 쌓아 둔다. 프롬프트가 의도대로 조립됐는지 볼 때 쓴다.
    public private(set) var received: [(instructions: String, message: String)] = []

    public init(
        id: String = "replay",
        displayName: String = "재생",
        script: [String: LLMResponse] = [:],
        fallback: LLMResponse = LLMResponse(text: "(정해둔 답 없음)"),
        capabilities: ProviderCapabilities = ProviderCapabilities(maxPromptCharacters: 100_000)
    ) {
        self.id = id
        self.displayName = displayName
        self.script = script
        self.fallback = fallback
        self.capabilities = capabilities
    }

    public func makeSession(_ setup: SessionSetup) -> LLMSession {
        ReplaySession(owner: self, instructions: setup.instructions)
    }

    fileprivate func answer(to message: String, instructions: String) -> LLMResponse {
        received.append((instructions: instructions, message: message))
        return script[message] ?? fallback
    }
}

@MainActor
private final class ReplaySession: LLMSession {
    private unowned let owner: ReplayProvider
    private let instructions: String

    init(owner: ReplayProvider, instructions: String) {
        self.owner = owner
        self.instructions = instructions
    }

    func reply(
        to message: String,
        decoding: DecodingOptions,
        onPartial: @escaping (LLMResponse) -> Void
    ) async -> LLMResponse {
        let result = owner.answer(to: message, instructions: instructions)
        // 스트리밍을 흉내 낸다. 부분 응답을 쓰는 화면 코드도 같은 경로를 타게 하려는 것이다.
        onPartial(result)
        return result
    }
}
