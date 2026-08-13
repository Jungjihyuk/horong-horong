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

    /// 세션 지시문. 주간과 문장이 다른 이유는 묶는 대상이 다르기 때문이다.
    public static let instructions =
        "너는 사용자의 주간 목표를 더 큰 월간 목표로 묶어주는 생산성 앱 도우미다. 응답은 반드시 유효한 JSON만 출력한다."

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

    // MARK: - 한 번 돌리기

    /// 한 번의 월간 추천 결과. 주간(`WeeklyGoalTask.RunOutcome`)보다 단출한 이유는
    /// 이 경로에 진단 로그가 없어서다 — 없는 값을 만들어 내지 않는다.
    public struct RunOutcome {
        public let drafts: [GoalSuggestionDraft]
        /// 생성이 실패했으면 그 에러. **문자열이 아니라 에러 그대로** 돌려주는 이유는
        /// 릴리스에서 타입 이름만 남길지가 앱 정책이기 때문이다(`WeeklyGoalTask.RunOutcome` 과 같다).
        public let failure: Error?
    }

    /// 개수 자르기 → 프롬프트 → 생성 → 파싱.
    ///
    /// 주간과 달리 **문자 예산 컷이 없다.** 월간은 주간 목표 몇 개만 넣으므로 프롬프트가
    /// 크게 자라지 않는다. 필요해지면 주간 쪽과 같은 방식으로 붙인다.
    public static func run(
        goals: [Goal],
        suggestionCount: Int,
        inputLimit: Int,
        generate: (_ prompt: String, _ instructions: String) async throws -> String
    ) async -> RunOutcome {
        let prompt = prompt(
            for: Array(goals.prefix(inputLimit)),
            suggestionCount: suggestionCount
        )

        do {
            let text = try await generate(prompt, instructions)
            // 허용 id 와 원본 목표는 **자르기 전 전체**다. 잘린 목표의 할일까지 끌어올려야 하는
            // 경우가 생기면 좁혀 둔 쪽이 조용히 후보를 잃는다.
            let drafts = parse(
                text,
                allowedIDs: Set(goals.map(\.id)),
                sourceGoals: goals,
                suggestionCount: suggestionCount
            )
            return RunOutcome(drafts: drafts, failure: nil)
        } catch {
            return RunOutcome(drafts: [], failure: error)
        }
    }

    // MARK: - 응답 읽기

    /// 주간과 달리 진단 로그가 없어 후보 목록만 돌려준다.
    ///
    /// `sourceGoals` 가 필요한 이유는 월간 후보가 **묶은 주간 목표들의 할일까지 끌어올리기** 때문이다.
    public static func parse(
        _ text: String,
        allowedIDs: Set<UUID>,
        sourceGoals: [Goal],
        suggestionCount: Int
    ) -> [GoalSuggestionDraft] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let payload = GoalSuggestionPayload(responseText: trimmed) else {
            return []
        }

        let goalByID = Dictionary(uniqueKeysWithValues: sourceGoals.map { ($0.id, $0) })
        var used = Set<UUID>()
        return payload.suggestions.compactMap { item -> GoalSuggestionDraft? in
            let ids = (item.goalIDs ?? []).compactMap(UUID.init(uuidString:))
                .filter { allowedIDs.contains($0) && !used.contains($0) }
                .prefix(4)
            guard ids.count >= 2 else { return nil }
            used.formUnion(ids)
            let goals = ids.compactMap { goalByID[$0] }
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let criterion = item.criterion.trimmingCharacters(in: .whitespacesAndNewlines)
            let scheduleText = item.scheduleText.trimmingCharacters(in: .whitespacesAndNewlines)
            return GoalSuggestionDraft(
                title: title.isEmpty ? "추천 월간 목표" : title,
                reason: item.reason,
                memoIDs: Array(Set(goals.flatMap(\.sourceMemoIDs))),
                childGoalIDs: Array(ids),
                scheduleText: scheduleText.isEmpty ? "이번 달에 주간 목표 \(ids.count)개로 나눠 진행" : scheduleText,
                criterion: criterion.isEmpty ? "연결한 주간 목표 \(ids.count)개 달성" : criterion,
                targetValueText: "\(ids.count)개",
                emoji: item.emoji?.isEmpty == false ? String(item.emoji!.prefix(1)) : "📅"
            )
        }
        .prefix(suggestionCount)
        .map { $0 }
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
