import Foundation

/// 키워드가 직접 일치하지 않는 자연어 질문에 대해,
/// 등록된 기능 목록 중 가장 적합한 목적지 ID를 LLM을 통해 분류하기 위한 정책 및 파서다.
enum CompanionDestinationClassifier {
    struct Candidate: Equatable, Sendable {
        let destinationID: CompanionDestinationID
        let label: String
        let summary: String
    }

    /// Registry에 등록된 목적지가 있는 지식들로부터 분류 후보 목록을 구성한다 (중복 목적지 제거).
    static var defaultCandidates: [Candidate] {
        var seen: Set<CompanionDestinationID> = []
        var candidates: [Candidate] = []
        for item in CompanionKnowledgeRegistry.all {
            guard let destID = item.destinationID, !seen.contains(destID) else { continue }
            seen.insert(destID)
            candidates.append(
                Candidate(
                    destinationID: destID,
                    label: item.path ?? destID.rawValue,
                    summary: item.summary
                )
            )
        }
        return candidates
    }

    /// LLM에게 전달할 구조화 분류 프롬프트를 생성한다.
    static func prompt(
        for question: String,
        candidates: [Candidate] = defaultCandidates
    ) -> String {
        let candidateLines = candidates.map {
            "- \($0.destinationID.rawValue) (\($0.label)): \($0.summary)"
        }.joined(separator: "\n")

        return """
        사용자의 질문이 앱의 어떤 기능 화면과 가장 관련이 깊은지 다음 목적지 ID 목록 중에서 정확히 하나만 골라 JSON 형식으로 답하세요.
        관련된 기능 화면이 전혀 없거나 일반 대화/스몰톡인 경우 "NONE"으로 답하세요.

        [목적지 ID 목록]
        \(candidateLines)

        사용자 질문: "\(question)"

        응답 형식 (반드시 유효한 JSON만 출력, 추가 설명 금지):
        {"destinationId": "선택한_목적지_ID"}
        또는
        {"destinationId": "NONE"}
        """
    }

    /// 모델의 응답 문자열에서 유효하고 등록된 목적지 ID를 안전하게 파싱한다.
    /// 모델이 목록에 없는 ID를 지어내거나(할루시네이션) 잘못된 형식을 출력하면 nil을 반환한다.
    static func parse(
        from response: String,
        allowedCandidates: [Candidate] = defaultCandidates
    ) -> CompanionDestinationID? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let allowedMap = Dictionary(
            allowedCandidates.map { ($0.destinationID.rawValue, $0.destinationID) },
            uniquingKeysWith: { first, _ in first }
        )

        // 1. JSON에서 destinationId 또는 destination 추출 시도
        if let jsonID = extractIDFromJSON(trimmed) {
            if jsonID.uppercased() == "NONE" { return nil }
            if let validID = allowedMap[jsonID],
               CompanionDestinationRegistry.destination(for: validID) != nil {
                return validID
            }
        }

        // 2. 텍스트 내에서 등록된 후보 ID 단독 일치 검사
        for rawID in allowedMap.keys {
            if trimmed.contains("\"\(rawID)\"") || trimmed.contains("'\(rawID)'") || trimmed == rawID {
                if CompanionDestinationRegistry.destination(forRawID: rawID) != nil {
                    return allowedMap[rawID]
                }
            }
        }

        return nil
    }

    /// 주어진 텍스트 생성기 클로저를 사용하여 질문을 비동기로 분류한다.
    @MainActor
    static func classify(
        question: String,
        candidates: [Candidate] = defaultCandidates,
        generateText: @MainActor (String) async throws -> String
    ) async -> CompanionDestinationID? {
        let inputPrompt = prompt(for: question, candidates: candidates)
        guard let output = try? await generateText(inputPrompt) else {
            return nil
        }
        return parse(from: output, allowedCandidates: candidates)
    }

    private static func extractIDFromJSON(_ text: String) -> String? {
        guard let openBrace = text.firstIndex(of: "{"),
              let closeBrace = text.lastIndex(of: "}"),
              openBrace < closeBrace else {
            return nil
        }
        let jsonString = String(text[openBrace...closeBrace])
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let id = json["destinationId"] as? String {
            return id.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let id = json["destination"] as? String {
            return id.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}
