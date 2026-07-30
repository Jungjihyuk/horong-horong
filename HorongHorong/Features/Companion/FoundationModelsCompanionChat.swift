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
        precise: Bool,
        onPartial: @escaping (CompanionChatReply) -> Void
    ) async -> CompanionChatReply {
        // 온도가 높으면 이 크기의 모델은 배경 정보를 엉뚱한 자리에 끌어다 쓴다.
        // (인사에 대고 사용자 메모를 읊는 현상: 0.8 에서 3/5, 0.4 에서 0/5)
        // 근거를 넘긴 답변은 창의성이 필요 없어 더 낮춘다.
        let options = GenerationOptions(
            temperature: precise ? 0.2 : 0.4,
            maximumResponseTokens: 220
        )

        // 1) 감정까지 함께 받는 정상 경로.
        if let reply = try? await stream(message, options: options, onPartial: onPartial) {
            return reply
        }

        // 2) 구조화 출력은 안전 필터에 오탐으로 걸리는 일이 있다.
        //    그럴 때도 대화가 끊기지 않도록 감정 없이 평문으로 한 번 더 시도한다.
        if let reply = try? await streamPlainText(message, options: options, onPartial: onPartial) {
            return reply
        }

        // 3) 문맥이 넘쳤을 수 있으니 대화를 새로 열고 마지막으로 시도한다.
        session = Self.makeSession(context)
        if let reply = try? await streamPlainText(message, options: options, onPartial: onPartial) {
            return reply
        }

        return CompanionChatReply(
            text: "지금은 생각이 잘 안 나요. 잠시 뒤에 다시 말 걸어 주세요.",
            mood: .concerned
        )
    }

    /// 감정 없이 말만 받는 경로. 구조화 출력이 막혔을 때 쓴다.
    private func streamPlainText(
        _ message: String,
        options: GenerationOptions,
        onPartial: @escaping (CompanionChatReply) -> Void
    ) async throws -> CompanionChatReply {
        var latest = ""
        for try await partial in session.streamResponse(to: message, options: options) {
            latest = partial.content
            onPartial(CompanionChatReply(text: latest, mood: nil))
        }
        let trimmed = latest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CancellationError() }
        return CompanionChatReply(text: trimmed, mood: nil)
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
