import Foundation
import HorongAI

/// 패키지의 `LLMProvider` 를 앱의 `CompanionChatProvider` 로 잇는 어댑터.
///
/// 컨트롤러와 화면 코드를 건드리지 않은 채 구현만 패키지로 밀어내기 위한 다리다.
/// 앱이 패키지 계약을 직접 쓰게 되면 사라진다.
///
/// 공급자에 무관하게 동작하므로 Ollama · Apple 온디바이스 · MLX 가 모두 이 하나를 쓴다.
@MainActor
final class PackageChatProvider: CompanionChatProvider {
    private let inner: any LLMProvider

    init(_ inner: any LLMProvider) {
        self.inner = inner
    }

    var displayName: String { inner.displayName }
    var isAvailable: Bool { inner.isAvailable }

    func makeSession(_ context: CompanionChatContext) -> CompanionChatSession {
        // 캐릭터·프로필로 지시문을 만드는 일은 앱에 남는다. 패키지는 완성된 문자열만 받는다.
        // 이 렌더링 자체는 S4 에서 Tasks/ 로 옮겨간다.
        let instructions = CompanionPromptTemplate.instructions(
            for: context.character,
            profile: context.profile
        )
        return PackageChatSession(inner.makeSession(SessionSetup(instructions: instructions)))
    }
}

@MainActor
private final class PackageChatSession: CompanionChatSession {
    private let inner: LLMSession

    init(_ inner: LLMSession) {
        self.inner = inner
    }

    func reply(
        to message: String,
        precise: Bool,
        onPartial: @escaping (CompanionChatReply) -> Void
    ) async -> CompanionChatReply {
        let response = await inner.reply(
            to: message,
            decoding: precise ? .precise : .casual
        ) { partial in
            onPartial(Self.convert(partial))
        }
        return Self.convert(response)
    }

    /// 패키지는 감정을 문자열로 다룬다. 원시값이 문자열이라 되돌릴 때 손실이 없다.
    private static func convert(_ response: LLMResponse) -> CompanionChatReply {
        CompanionChatReply(
            text: response.text,
            mood: response.mood.flatMap(CompanionMood.init(rawValue:))
        )
    }
}
