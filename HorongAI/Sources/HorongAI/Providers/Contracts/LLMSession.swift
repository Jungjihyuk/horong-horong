import Foundation

/// 모델이 실제로 쓴 양. **공급자마다 알 수 있는 것이 다르다.**
///
/// Ollama 는 마지막 청크에 `prompt_eval_count` · `eval_count` 를 담아 주지만 지금은 파싱하지 않아
/// 버려진다. Apple Foundation Models 는 노출하지 않는 것으로 보인다 `[확인 필요]`.
/// 모르는 공급자는 `nil` 이다 — 그래서 옵셔널이다.
public struct Usage: Sendable, Equatable {
    public let tokensIn: Int?
    public let tokensOut: Int?

    public init(tokensIn: Int? = nil, tokensOut: Int? = nil) {
        self.tokensIn = tokensIn
        self.tokensOut = tokensOut
    }
}

/// 모델이 돌려준 답.
///
/// `mood` 를 앱의 `CompanionMood` 가 아니라 **문자열**로 두는 이유는, 그 열거형이
/// `animation` 같은 화면 관심사를 달고 있기 때문이다. 원시값이 문자열이라 앱에서
/// `CompanionMood(rawValue:)` 로 되돌리면 손실이 없다.
public struct LLMResponse: Sendable, Equatable {
    public let text: String
    public let mood: String?
    public let usage: Usage?

    public init(text: String, mood: String? = nil, usage: Usage? = nil) {
        self.text = text
        self.mood = mood
        self.usage = usage
    }

    public static let empty = LLMResponse(text: "")
}

/// 대화 한 세션. 이전 turn 의 문맥을 유지한다.
///
/// `@MainActor` 는 지금 앱 코드(`CompanionChatSession`)와 같은 격리를 그대로 옮긴 것이다.
/// 동시성 수준을 v6 로 올릴 때 다시 본다.
@MainActor
public protocol LLMSession: AnyObject {
    /// 답을 만든다. 부분 응답이 들어올 때마다 `onPartial` 이 **누적 결과**로 불린다.
    func reply(
        to message: String,
        decoding: DecodingOptions,
        onPartial: @escaping (LLMResponse) -> Void
    ) async -> LLMResponse
}
