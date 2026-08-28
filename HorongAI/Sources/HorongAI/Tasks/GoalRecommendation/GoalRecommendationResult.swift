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

/// 목표로 묶기에는 정보가 부족한 입력 하나에 대한 구체화 안내.
public struct GoalRecommendationGuidance: Sendable, Hashable, Identifiable {
    public let inputID: UUID
    public let missing: [String]
    public let suggestion: String

    public init(inputID: UUID, missing: [String], suggestion: String) {
        self.inputID = inputID
        self.missing = missing
        self.suggestion = suggestion
    }

    public var id: UUID { inputID }
}

/// 한 번의 추천이 화면에 전달할 결과.
///
/// 일반·맥락 의존 입력은 `.suggestions`, 정보 부족 입력은 `.guidance`, 의미 있는 묶음이
/// 전혀 없을 때는 `.noSuggestion` 이다. 골든셋의 `datasetType`은 평가용 분류이고,
/// 제품이 소비하는 분기는 이 결과 타입이다.
public enum GoalRecommendationResult: Sendable, Hashable {
    case suggestions([GoalSuggestionDraft])
    case guidance([GoalRecommendationGuidance])
    case noSuggestion

    public var drafts: [GoalSuggestionDraft] {
        guard case .suggestions(let drafts) = self else { return [] }
        return drafts
    }

    /// 파싱 단계 trace에 남길 사람이 읽을 수 있는 표현.
    var traceText: String {
        switch self {
        case .suggestions(let drafts):
            return drafts.map { "- \($0.title)" }.joined(separator: "\n")
        case .guidance(let guidance):
            return guidance.map {
                let missing = $0.missing.joined(separator: ", ")
                return "- inputID=\($0.inputID.uuidString) missing=[\(missing)] suggestion=\($0.suggestion)"
            }.joined(separator: "\n")
        case .noSuggestion:
            return ""
        }
    }
}
