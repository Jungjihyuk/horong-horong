import Foundation

/// 목표 추천에 참고할, 입력 목록 밖의 사용자 맥락.
///
/// 할일·주간 목표 자체는 각 태스크의 입력으로 전달한다. 이 값은 그것만으로는 알 수 없는
/// 사용자 정보(예: 현재 집중 중인 프로젝트)를 짧게 보태는 용도다.
public struct GoalRecommendationContext: Sendable, Hashable {
    public let persona: String?
    public let profile: String?

    public init(persona: String? = nil, profile: String? = nil) {
        self.persona = Self.normalized(persona)
        self.profile = Self.normalized(profile)
    }

    public static let empty = GoalRecommendationContext()

    var promptText: String {
        var lines: [String] = []
        if let persona { lines.append("페르소나: \(persona)") }
        if let profile { lines.append("사용자 프로필: \(profile)") }
        return lines.joined(separator: "\n")
    }

    private static func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// 제목만 보고 안전하게 판정할 수 있는 구체화 축.
public enum GoalRefinementDimension: String, Codable, Sendable, Hashable, CaseIterable {
    case specific
    case measurable
    case timeBound = "time_bound"
}

/// 추천 묶음에 들어가지 못한 입력들을 한 번에 설명하는 구체화 보조.
///
/// 같은 조언을 입력별로 복제하지 않는다. 서로 다른 입력이라는 사실은 UUID 배열로 보존한다.
public struct GoalRecommendationRefinement: Sendable, Hashable, Identifiable {
    public let inputIDs: [UUID]
    public let missing: [GoalRefinementDimension]
    public let example: String

    public init(inputIDs: [UUID], missing: [GoalRefinementDimension], example: String) {
        var seen = Set<UUID>()
        self.inputIDs = inputIDs.filter { seen.insert($0).inserted }
        self.missing = Array(Set(missing)).sorted { $0.rawValue < $1.rawValue }
        self.example = example
    }

    public var id: String {
        inputIDs.map(\.uuidString).sorted().joined(separator: "|")
            + "|" + missing.map(\.rawValue).joined(separator: ",")
            + "|" + example
    }
}

/// 한 번의 추천 결과. 묶음과 구체화 보조는 서로 배타적이지 않다.
public struct GoalRecommendationResult: Sendable, Hashable {
    public let suggestions: [GoalSuggestionDraft]
    public let refinements: [GoalRecommendationRefinement]

    public init(
        suggestions: [GoalSuggestionDraft] = [],
        refinements: [GoalRecommendationRefinement] = []
    ) {
        self.suggestions = suggestions
        self.refinements = refinements
    }

    public var drafts: [GoalSuggestionDraft] { suggestions }
    public var isEmpty: Bool { suggestions.isEmpty && refinements.isEmpty }

    /// 파싱 단계 trace에 남길 사람이 읽을 수 있는 표현.
    var traceText: String {
        let suggestionLines = suggestions.map { "- suggestion=\($0.title)" }
        let refinementLines = refinements.map {
            let ids = $0.inputIDs.map(\.uuidString).joined(separator: ",")
            let missing = $0.missing.map(\.rawValue).joined(separator: ", ")
            return "- inputIDs=[\(ids)] missing=[\(missing)] example=\($0.example)"
        }
        return (suggestionLines + refinementLines).joined(separator: "\n")
    }
}
