import Foundation

/// 모델이 낸 목표 후보 하나. 주간·월간이 같은 모양을 쓴다.
///
/// **초안(draft)** 인 이유는 사용자가 화면에서 고쳐 쓰는 값이기 때문이다. 그대로 저장되지 않는다.
/// 앱이 어떤 목표 타입인지(`cadence`)와 어느 공급자에서 왔는지(`source`)를 붙여 자기 도메인 값으로 바꾼다.
public struct GoalSuggestionDraft: Sendable, Hashable {
    public let title: String
    public let reason: String
    public let memoIDs: [UUID]
    public let childGoalIDs: [UUID]
    public let scheduleText: String
    public let criterion: String
    public let targetValueText: String
    public let emoji: String

    public init(
        title: String,
        reason: String,
        memoIDs: [UUID],
        childGoalIDs: [UUID] = [],
        scheduleText: String,
        criterion: String,
        targetValueText: String,
        emoji: String
    ) {
        self.title = title
        self.reason = reason
        self.memoIDs = memoIDs
        self.childGoalIDs = childGoalIDs
        self.scheduleText = scheduleText
        self.criterion = criterion
        self.targetValueText = targetValueText
        self.emoji = emoji
    }
}

/// 모델 응답의 JSON 모양. 주간은 `memoIDs`, 월간은 `goalIDs` 를 채워 보내므로 둘 다 옵셔널이다.
struct GoalSuggestionPayload: Codable {
    let suggestions: [Item]

    struct Item: Codable {
        let title: String
        let reason: String
        let memoIDs: [String]?
        let goalIDs: [String]?
        let scheduleText: String
        let criterion: String
        let emoji: String?
    }

    /// 모델이 JSON 앞뒤에 설명을 붙여도 살려낸다 — 첫 `{` 부터 마지막 `}` 까지만 잘라 읽는다.
    /// 읽지 못하면 `nil` 이다. 던지지 않는 이유는 호출부가 실패를 "후보 없음"으로만 다루기 때문이다.
    init?(responseText: String) {
        let jsonText = Self.extractJSONObject(from: responseText)
        guard let data = jsonText.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(GoalSuggestionPayload.self, from: data) else {
            return nil
        }
        self = decoded
    }

    static func extractJSONObject(from text: String) -> String {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            return text
        }
        return String(text[start...end])
    }
}
