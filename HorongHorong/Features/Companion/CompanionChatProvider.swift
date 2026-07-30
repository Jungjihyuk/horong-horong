import Foundation
import SwiftData

/// 대화 세션을 만들 때 필요한 것들. 인자가 늘어나도 시그니처가 번지지 않도록 한데 묶는다.
struct CompanionChatContext {
    let character: CompanionCharacter
    let profile: CompanionUserProfile
    /// 할일 조회 도구에 넘길 저장소. 없으면 도구 없이 대화한다.
    let modelContainer: ModelContainer?
}

/// 대화 한 세션. 이전 turn 의 문맥을 유지한다.
@MainActor
protocol CompanionChatSession: AnyObject {
    /// 답을 만든다. 부분 응답이 들어올 때마다 `onPartial` 이 누적 결과로 불린다.
    /// `precise` 는 근거를 함께 넘겼다는 뜻. 그럴 때는 낮은 온도로 답한다.
    func reply(
        to message: String,
        precise: Bool,
        onPartial: @escaping (CompanionChatReply) -> Void
    ) async -> CompanionChatReply
}

/// 대화 공급자. 로컬 모델을 쓸 수 있으면 그쪽이, 아니면 고정 응답이 선택된다.
@MainActor
protocol CompanionChatProvider {
    /// 설정 화면에 보여줄 이름.
    var displayName: String { get }
    /// 지금 이 기기에서 실제로 답을 만들 수 있는지.
    var isAvailable: Bool { get }
    func makeSession(_ context: CompanionChatContext) -> CompanionChatSession
}

enum CompanionChatProviderFactory {
    /// 로컬 모델을 쓸 수 있으면 그것을, 아니면 고정 응답 공급자를 돌려준다.
    /// 대화·추론은 전부 기기 안에서 끝나며 어떤 경우에도 네트워크로 나가지 않는다.
    @MainActor
    static func make(ollamaReachable: Bool = false) -> CompanionChatProvider {
        let selected = UserDefaults.standard.string(
            forKey: Constants.AppStorageKey.companionChatProvider
        ) ?? Constants.defaultCompanionChatProvider

        NSLog("[PROVIDER] selected=\(selected) ollamaReachable=\(ollamaReachable)")
        if selected == Constants.CompanionChatProviderKind.ollama.rawValue {
            let provider = OllamaCompanionChatProvider(
                endpoint: UserDefaults.standard.string(
                    forKey: Constants.NewsStorageKey.ollamaEndpoint
                ) ?? Constants.defaultNewsOllamaEndpoint,
                model: UserDefaults.standard.string(
                    forKey: Constants.AppStorageKey.companionOllamaModel
                ) ?? Constants.defaultCompanionOllamaModel,
                reachable: ollamaReachable
            )
            NSLog("[PROVIDER] Ollama 공급자 반환 model=\(provider.displayName)")
            return provider
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let provider = FoundationModelsCompanionChatProvider()
            if provider.isAvailable { return provider }
        }
        #endif
        return ScriptedCompanionChatProvider()
    }
}

/// 로컬 모델을 쓸 수 없는 기기에서의 대체 응답.
@MainActor
final class ScriptedCompanionChatProvider: CompanionChatProvider {
    var displayName: String { "고정 응답" }
    var isAvailable: Bool { true }

    func makeSession(_ context: CompanionChatContext) -> CompanionChatSession {
        ScriptedCompanionChatSession()
    }
}

@MainActor
private final class ScriptedCompanionChatSession: CompanionChatSession {
    /// `precise` 는 근거를 함께 넘겼다는 뜻. 그럴 때는 낮은 온도로 답한다.
    func reply(
        to message: String,
        precise: Bool,
        onPartial: @escaping (CompanionChatReply) -> Void
    ) async -> CompanionChatReply {
        try? await Task.sleep(for: .milliseconds(400))
        return CompanionChatReply(
            text: "이 기기에서는 아직 로컬 AI 모델을 쓸 수 없어요. "
                + "그래도 얘기는 잘 들었어요 — 필요한 게 있으면 설정에서 확인해 보세요.",
            mood: .calm
        )
    }
}

/// 컴패니언 대화용 프롬프트. 성취 기능과 같은 규약(`Resources/Prompts/*.md` + `{{key}}`)을 쓴다.
enum CompanionPromptTemplate {
    static func instructions(
        for character: CompanionCharacter,
        profile: CompanionUserProfile = .empty
    ) -> String {
        let base = render(
            fileName: "companion_chat",
            fallback: fallbackInstructions,
            values: [
                "characterName": character.displayName,
                "tagline": character.tagline,
            ]
        )
        return base + profile.promptSection
    }

    private static func render(
        fileName: String,
        fallback: String,
        values: [String: String]
    ) -> String {
        var result = load(fileName: fileName) ?? fallback
        for (key, value) in values {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return result
    }

    private static func load(fileName: String) -> String? {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "md") else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private static let fallbackInstructions = """
    너는 macOS 생산성 앱 "호롱호롱"의 화면 위에 사는 컴패니언 "{{characterName}}"이야.
    한국어로 부드러운 존댓말을 쓰고, 말풍선이 좁으니 2~3문장 안에서 끝내.
    모르는 건 모른다고 말하고, 사용자의 일정·할일 내용을 지어내지 마.
    """
}
