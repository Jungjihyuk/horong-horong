import Foundation

/// 대화 세션 하나를 세울 때 필요한 재료.
///
/// 지금 앱의 `CompanionChatContext` 는 `CompanionCharacter` · `CompanionUserProfile` ·
/// `ModelContainer`(SwiftData) 를 들고 있는데, 셋 다 앱 도메인이라 패키지가 알면 안 된다.
/// 살펴보니 캐릭터·프로필은 **지시문을 만드는 재료로만** 쓰인다(`MLXCompanionChat.swift:25`).
/// 그래서 경계에서는 **이미 완성된 지시문 문자열**만 받는다. 만드는 일은 `Tasks/` 의 몫이다.
public struct SessionSetup: Sendable {
    /// 시스템 프롬프트. 앱이 캐릭터·프로필로 렌더해 넘긴다.
    public let instructions: String

    public init(instructions: String) {
        self.instructions = instructions
    }
}

/// 한 번의 응답을 만들 때의 디코딩 값.
///
/// 지금은 `reply(to:precise:)` 의 `precise` 불리언 하나가 이 역할을 한다 —
/// 근거를 함께 넘겼으면 낮은 온도로 답한다는 뜻이다. 세션이 아니라 **호출마다** 달라지므로
/// 세션이 아닌 `reply` 인자로 받는다.
public struct DecodingOptions: Sendable, Equatable {
    public let temperature: Double
    public let maxTokens: Int?

    public init(temperature: Double, maxTokens: Int? = nil) {
        self.temperature = temperature
        self.maxTokens = maxTokens
    }

    /// 근거를 함께 넘겼을 때. 지어내는 걸 줄인다.
    public static let precise = DecodingOptions(temperature: 0.2)
    /// 잡담처럼 근거가 없을 때.
    public static let casual = DecodingOptions(temperature: 0.4)
}
