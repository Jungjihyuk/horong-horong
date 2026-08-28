import Foundation

/// 모델을 부르지 않고 **정해둔 텍스트를 돌려주는** 생성기.
///
/// `ReplayProvider` 와 목적은 같지만 계약이 다르다. 그쪽은 대화용(`LLMSession`)이라 실패해도
/// 사과 문구를 반환하는데, 태스크 경로는 **실패가 던져져야** 호출부가 다음 공급자로 내려간다.
/// 그래서 `WeeklyGoalTask.run(generate:)` 이 받는 모양에 맞춘 물건이 따로 필요하다.
///
/// 쓰임새는 둘이다.
/// - 평가: 실모델은 같은 프롬프트에도 매번 다르게 답해 회귀 판정에 쓸 수 없다
///   (→ `Bug/incident-20260813-nondeterministic-model-breaks-regression-check.md`).
///   응답을 고정하면 입력 고르기·프롬프트·파싱·채점만 따로 검증할 수 있다.
/// - 테스트: 케이스당 수 초 걸리던 것이 밀리초가 된다.
public final class ReplayTextGenerator {
    private let responses: [String]
    private let error: Error?
    private var index = 0

    /// 이 생성기가 받은 프롬프트·지시문. 무엇이 조립돼 나갔는지 볼 때 쓴다.
    public private(set) var received: [(prompt: String, instructions: String)] = []

    /// 응답을 순서대로 하나씩 돌려준다. 다 쓰면 마지막 것을 반복한다 —
    /// 케이스 수와 응답 수가 어긋났을 때 조용히 빈 문자열이 나가는 것보다 낫다.
    public init(responses: [String]) {
        self.responses = responses
        self.error = nil
    }

    public convenience init(_ response: String) {
        self.init(responses: [response])
    }

    /// 항상 실패하는 생성기. 폴백 경로를 검증할 때 쓴다.
    public init(failingWith error: Error) {
        self.responses = []
        self.error = error
    }

    public func generate(prompt: String, instructions: String) async throws -> String {
        received.append((prompt: prompt, instructions: instructions))
        if let error { throw error }
        guard !responses.isEmpty else { return "" }
        let response = responses[min(index, responses.count - 1)]
        index += 1
        return response
    }
}

/// 고정 생성기가 던지는 실패. 실제 공급자의 에러 타입을 흉내 내지 않는다 —
/// 호출부가 에러 **종류**로 분기하면 그건 계약이 부족하다는 뜻이다.
public struct ReplayGenerationFailure: Error, Equatable {
    public let reason: String

    public init(reason: String = "정해둔 실패") {
        self.reason = reason
    }
}
