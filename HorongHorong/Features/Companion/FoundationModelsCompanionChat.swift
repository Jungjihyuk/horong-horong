import Foundation

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

    func makeSession(for character: CompanionCharacter) -> CompanionChatSession {
        FoundationModelsCompanionChatSession(character: character)
    }
}

@available(macOS 26.0, *)
@MainActor
private final class FoundationModelsCompanionChatSession: CompanionChatSession {
    private let character: CompanionCharacter
    private var session: LanguageModelSession

    init(character: CompanionCharacter) {
        self.character = character
        self.session = Self.makeSession(for: character)
    }

    private static func makeSession(for character: CompanionCharacter) -> LanguageModelSession {
        LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: CompanionPromptTemplate.instructions(for: character)
        )
    }

    func reply(to message: String, onPartial: @escaping (String) -> Void) async -> String {
        let options = GenerationOptions(temperature: 0.8, maximumResponseTokens: 220)

        do {
            return try await stream(message, options: options, onPartial: onPartial)
        } catch {
            // 문맥이 넘치면 대화를 새로 열고 한 번만 다시 시도한다.
            session = Self.makeSession(for: character)
            do {
                return try await stream(message, options: options, onPartial: onPartial)
            } catch {
                return "지금은 생각이 잘 안 나요. 잠시 뒤에 다시 말 걸어 주세요."
            }
        }
    }

    private func stream(
        _ message: String,
        options: GenerationOptions,
        onPartial: @escaping (String) -> Void
    ) async throws -> String {
        var latest = ""
        for try await partial in session.streamResponse(to: message, options: options) {
            latest = partial.content
            onPartial(latest)
        }
        let trimmed = latest.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "…" : trimmed
    }
}
#endif
