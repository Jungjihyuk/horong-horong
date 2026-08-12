import Foundation

/// 주간 목표들을 주고 **월간 목표 후보**를 받아오는 태스크.
///
/// 주간(`WeeklyGoalTask`)과 나눈 이유는 묶는 기준이 다르기 때문이다 —
/// 주간은 할일을 하나의 결과물로, 월간은 주간 목표를 더 큰 결과로 묶는다.
public enum MonthlyGoalTask {

    /// 프롬프트에 실리는 주간 목표 하나.
    ///
    /// 앱의 목표 스냅샷에는 이 밖에도 필드가 더 있지만, 프롬프트와 파서가 실제로 읽는 것만 받는다.
    public struct Goal: Sendable, Hashable, Identifiable {
        public let id: UUID
        public let title: String
        public let emoji: String
        public let rule: String
        public let done: Int
        public let total: Int
        /// 월간 후보로 묶일 때 하위 할일까지 함께 끌어올리려면 필요하다.
        public let sourceMemoIDs: [UUID]
        public let roleName: String
        public let vision: String

        public init(
            id: UUID,
            title: String,
            emoji: String,
            rule: String,
            done: Int,
            total: Int,
            sourceMemoIDs: [UUID],
            roleName: String,
            vision: String
        ) {
            self.id = id
            self.title = title
            self.emoji = emoji
            self.rule = rule
            self.done = done
            self.total = total
            self.sourceMemoIDs = sourceMemoIDs
            self.roleName = roleName
            self.vision = vision
        }
    }

    // MARK: - 프롬프트

    public static func prompt(
        for goals: [Goal],
        suggestionCount: Int
    ) -> String {
        let lines = goals.map { goal in
            [
                "- id: \(goal.id.uuidString)",
                "  title: \(goal.title)",
                "  emoji: \(goal.emoji)",
                "  rule: \(goal.rule)",
                "  progress: \(goal.done)/\(goal.total)",
                "  role: \(goal.roleName.isEmpty ? "없음" : goal.roleName)",
                "  vision: \(goal.vision.isEmpty ? "없음" : goal.vision)",
                "  linkedTodoCount: \(goal.sourceMemoIDs.count)",
            ].joined(separator: "\n")
        }.joined(separator: "\n")

        return PromptRenderer.render(
            fileName: "monthly_goal",
            fallback: promptFallback,
            values: [
                "suggestionCount": "\(suggestionCount)",
                "items": lines,
            ]
        )
    }

    private static let promptFallback = """
    아래 주간 목표들을 의미, 달성 기준, 페르소나, 비전, 연결된 할일 수를 함께 보고 월간 목표 후보를 최대 {{suggestionCount}}개 제안해줘.
    월간 목표 하나에는 주간 목표를 2개 이상 4개 이하로 넣어.
    title은 입력된 주간 목표들의 실제 내용에서만 추론해 새로 작성해.
    입력에 없는 구체적인 숫자, 회사 수, 횟수, 마감 조건은 만들지 마.
    같은 주간 목표를 여러 월간 후보에 중복해서 넣지 마.
    존재하는 id만 goalIDs에 넣어.

    JSON 형식:
    {
      "suggestions": [
        {
          "title": "월간 목표명",
          "reason": "묶은 이유",
          "goalIDs": ["UUID"],
          "scheduleText": "이번 달에 주간 목표 3개로 나눠 진행",
          "criterion": "연결한 주간 목표 3개 달성",
          "emoji": "📅"
        }
      ]
    }

    주간 목표:
    {{items}}
    """
}
