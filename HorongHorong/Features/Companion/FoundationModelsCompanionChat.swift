import Foundation
import SwiftData

#if canImport(FoundationModels)
import FoundationModels

/// Apple 온디바이스 모델 기반 대화 공급자.
/// 추론과 대화 내용이 기기 밖으로 나가지 않는다.
@available(macOS 26.0, *)
@MainActor
final class FoundationModelsCompanionChatProvider: CompanionChatProvider {
    var displayName: String { "Apple 온디바이스 모델" }

    var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    func makeSession(_ context: CompanionChatContext) -> CompanionChatSession {
        FoundationModelsCompanionChatSession(context: context)
    }
}

/// 모델이 고르는 감정. 앱 쪽 `CompanionMood` 와 짝을 이룬다.
/// `@Generable` 이 FoundationModels 를 요구하므로 공용 타입과 분리해 둔다.
@available(macOS 26.0, *)
@Generable
private enum GeneratedMood: String {
    case cheerful, playful, calm, encouraging, concerned

    var mood: CompanionMood { CompanionMood(modelValue: rawValue) ?? .calm }
}

@available(macOS 26.0, *)
@Generable
private struct GeneratedReply {
    @Guide(description: "사용자에게 건넬 말. 존댓말 2~3문장.")
    let text: String
    @Guide(description: "그 말을 할 때의 감정")
    let mood: GeneratedMood
}

@available(macOS 26.0, *)
@MainActor
private final class FoundationModelsCompanionChatSession: CompanionChatSession {
    private let context: CompanionChatContext
    private var session: LanguageModelSession

    init(context: CompanionChatContext) {
        self.context = context
        self.session = Self.makeSession(context)
    }

    private static func makeSession(_ context: CompanionChatContext) -> LanguageModelSession {
        // 도구는 쓰지 않는다. 지시문이 조금만 길어져도 이 모델은 도구를 거의 부르지 않아
        // 할일을 지어낸다. 대신 컨트롤러가 할일 목록을 프롬프트에 직접 끼워 넣는다.
        LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: CompanionPromptTemplate.instructions(
                for: context.character,
                profile: context.profile
            )
        )
    }

    func reply(
        to message: String,
        onPartial: @escaping (CompanionChatReply) -> Void
    ) async -> CompanionChatReply {
        let options = GenerationOptions(temperature: 0.8, maximumResponseTokens: 220)

        do {
            return try await stream(message, options: options, onPartial: onPartial)
        } catch {
            // 문맥이 넘치면 대화를 새로 열고 한 번만 다시 시도한다.
            session = Self.makeSession(context)
            do {
                return try await stream(message, options: options, onPartial: onPartial)
            } catch {
                return CompanionChatReply(
                    text: "지금은 생각이 잘 안 나요. 잠시 뒤에 다시 말 걸어 주세요.",
                    mood: .concerned
                )
            }
        }
    }

    /// 말은 흘러나오고 감정은 마지막에 확정된다.
    private func stream(
        _ message: String,
        options: GenerationOptions,
        onPartial: @escaping (CompanionChatReply) -> Void
    ) async throws -> CompanionChatReply {
        var latest = CompanionChatReply.empty
        for try await partial in session.streamResponse(
            to: message,
            generating: GeneratedReply.self,
            options: options
        ) {
            latest = CompanionChatReply(
                text: partial.content.text ?? latest.text,
                mood: partial.content.mood?.mood ?? latest.mood
            )
            onPartial(latest)
        }

        let trimmed = latest.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return CompanionChatReply(text: trimmed.isEmpty ? "…" : trimmed, mood: latest.mood)
    }
}
#endif
