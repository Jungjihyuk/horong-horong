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
        /// 실제로 프롬프트에 실린 주간 목표의 id.
        public let selectedIDs: [UUID]
        public let promptCharacters: Int
        public let timings: [String: Int]
        /// 왜 그만큼만 남았나. 생성 자체가 실패했으면 `nil` 이다 — 읽을 응답이 없었으니까.
        public let parse: WeeklyGoalTask.ParseOutcome.Diagnostics?
    }

    /// 개수 자르기 → 프롬프트 → 생성 → 파싱.
    ///
    /// 주간과 달리 **문자 예산 컷이 없다.** 월간은 주간 목표 몇 개만 넣으므로 프롬프트가
    /// 크게 자라지 않는다. 필요해지면 주간 쪽과 같은 방식으로 붙인다.
    public static func run(
        goals: [Goal],
        suggestionCount: Int,
        inputLimit: Int,
        timeoutInterval: TimeInterval = 60.0,
        /// 원문을 모을 자리. 개발자 모드가 아니면 `nil` 이라 아무 비용도 들지 않는다.
        trace: TraceCollector? = nil,
        // 타임아웃을 태스크 그룹으로 재므로 클로저가 탈출한다.
        generate: @escaping (_ prompt: String, _ instructions: String) async throws -> String
    ) async -> RunOutcome {
        let clock = StepClock()
        let selected = Array(goals.prefix(inputLimit))
        clock.mark("select_input")

        let prompt = prompt(for: selected, suggestionCount: suggestionCount)
        clock.mark("render_prompt")
        trace?.add(.input, selected.map { "- \($0.id): \($0.title)" }.joined(separator: "\n"),
                   facts: ["selected": selected.count, "candidates": goals.count])
        trace?.add(.prompt, prompt, facts: ["characters": prompt.count])

        func outcome(
            drafts: [GoalSuggestionDraft],
            failure: Error?,
            parse: WeeklyGoalTask.ParseOutcome.Diagnostics? = nil
        ) -> RunOutcome {
            RunOutcome(
                drafts: drafts,
                failure: failure,
                selectedIDs: selected.map(\.id),
                promptCharacters: prompt.count,
                timings: clock.elapsed,
                parse: parse
            )
        }

        do {
            let text = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    try await generate(prompt, instructions)
                }
                group.addTask {
                    // 생성 60초 타임아웃: 무한 루프/지연 발생 시 상한을 설정해 빠른 폴백 유도
                    let nanoseconds = UInt64(max(0.001, timeoutInterval) * 1_000_000_000)
                    try await Task.sleep(nanoseconds: nanoseconds)
                    throw CancellationError()
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
            clock.mark("generate")
            trace?.add(.rawResponse, text, facts: ["characters": text.count])
            trace?.add(.extractedJSON, GoalSuggestionPayload.extractJSONObject(from: text))
            // 허용 id 와 원본 목표는 **자르기 전 전체**다. 잘린 목표의 할일까지 끌어올려야 하는
            // 경우가 생기면 좁혀 둔 쪽이 조용히 후보를 잃는다.
            let parsed = parse(
                text,
                allowedIDs: Set(goals.map(\.id)),
                sourceGoals: goals,
                suggestionCount: suggestionCount
            )
            clock.mark("parse")
            trace?.add(.parsed, parsed.drafts.map { "- \($0.title)" }.joined(separator: "\n"),
                       facts: ["kept": parsed.drafts.count])
            return outcome(drafts: parsed.drafts, failure: nil, parse: parsed.diagnostics)
        } catch {
            clock.mark("generate")
            trace?.add(.failure, String(describing: error))
            return outcome(drafts: [], failure: error)
        }
    }

    /// 월간 목표 하나에 넣을 주간 목표의 최대 수. 프롬프트에도 같은 수가 적혀 있어
    /// **한쪽만 고치면 어긋난다.**
    public static let maxGoalsPerSuggestion = 4

    // MARK: - 응답 읽기

    /// 초안과 **왜 그만큼만 남았는지**를 함께 돌려준다.
    ///
    /// 예전에는 후보 목록만 돌려주고 실패 이유를 버렸다. 그 대가로 «초안 0개» 가 한 칸에
    /// 뭉쳐, 실측(2026-08-19/20)에서 서로 다른 세 원인이 똑같이 `parsedEmpty` 로 보였다.
    /// - 응답이 잘려 JSON 이 깨짐 (AFM, `max_tokens` 900 에 2016자)
    /// - 모델이 산문만 냄 (`qwen3:4b`)
    /// - JSON 은 멀쩡한데 **주간 목표를 1개씩만 묶어** 필터가 다 버림 (AFM)
    ///
    /// 원인을 가르려고 trace 파일을 하나씩 열어 봐야 했다. 이제는 기록 한 줄로 갈린다.
    ///
    /// 진단 그릇은 주간(`WeeklyGoalTask.ParseOutcome`)을 **그대로 쓴다.** 두 벌로 두면
    /// 한쪽만 고치는 실수가 나고, AI 실험실·리포트가 이미 그 모양을 읽고 있다.
    ///
    /// `sourceGoals` 가 필요한 이유는 월간 후보가 **묶은 주간 목표들의 할일까지 끌어올리기** 때문이다.
    public static func parse(
        _ text: String,
        allowedIDs: Set<UUID>,
        sourceGoals: [Goal],
        suggestionCount: Int
    ) -> WeeklyGoalTask.ParseOutcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: GoalSuggestionPayload
        switch GoalSuggestionPayload.decode(from: trimmed) {
        case .success(let decoded):
            payload = decoded
        case .failure(let failure):
            return WeeklyGoalTask.ParseOutcome(
                drafts: [],
                diagnostics: .decodeFailed(characters: trimmed.count, reason: failure.reason)
            )
        }

        let goalByID = Dictionary(uniqueKeysWithValues: sourceGoals.map { ($0.id, $0) })
        var badID = 0
        var alreadyUsed = 0
        var overMaxGoal = 0
        var tooFewIDs = 0
        var requestedIDs = 0
        var used = Set<UUID>()
        let result = payload.suggestions.compactMap { item -> GoalSuggestionDraft? in
            let rawIDs: [GoalSuggestionPayload.IDValue] = (item.goalIDs ?? item.items ?? item.memoIDs)?.values ?? []
            requestedIDs += rawIDs.count

            var parsedIDs: [UUID] = []
            for val in rawIDs {
                switch val {
                case .int(let idx):
                    if idx >= 1 && idx <= sourceGoals.count, allowedIDs.contains(sourceGoals[idx - 1].id) {
                        parsedIDs.append(sourceGoals[idx - 1].id)
                    } else {
                        badID += 1
                    }
                case .string(let str):
                    if let uuid = UUID(uuidString: str), allowedIDs.contains(uuid) {
                        parsedIDs.append(uuid)
                    } else {
                        badID += 1
                    }
                }
            }

            let unused = parsedIDs.filter { !used.contains($0) }
            alreadyUsed += parsedIDs.count - unused.count
            // 월간 하나에 주간 목표는 최대 4개. 프롬프트에도 같은 수가 적혀 있다.
            let ids = unused.prefix(maxGoalsPerSuggestion)
            overMaxGoal += unused.count - ids.count
            // **묶음은 2개 이상**이어야 한다. 1개짜리는 그 주간 목표 자체라 월간 목표가 아니다.
            guard ids.count >= 2 else {
                tooFewIDs += 1
                return nil
            }
            used.formUnion(ids)
            let goals = ids.compactMap { goalByID[$0] }
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let criterion = item.criterion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let scheduleText = item.scheduleText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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

        return WeeklyGoalTask.ParseOutcome(
            drafts: Array(result.prefix(suggestionCount)),
            diagnostics: .decoded(
                modelReturned: payload.suggestions.count,
                kept: result.count,
                requestedIDs: requestedIDs,
                badID: badID,
                alreadyUsed: alreadyUsed,
                // 주간의 `overMaxMemo` 자리다. 월간에서는 **주간 목표** 초과를 뜻한다 —
                // 기록 스키마를 그대로 쓰려고 이름은 주간 것을 따른다.
                overMaxMemo: overMaxGoal,
                tooFewIDs: tooFewIDs
            )
        )
    }

    /// 모델이 낼 수 있는 응답의 모양. 주간(`WeeklyGoalTask.responseSchema`)과 같은 사정이다.
    ///
    /// 월간은 주간 목표의 **UUID 문자열**로 받는다. 번호가 아니라 문자열인 것이 주간과 다르다.
    public static let responseSchema = JSONSchema.object(
        properties: [
            "suggestions": .array(of: .object(
                properties: [
                    "title": .string,
                    "reason": .string,
                    "goalIDs": .array(of: .string),
                    "scheduleText": .string,
                    "criterion": .string,
                    "emoji": .string,
                ],
                required: ["title", "reason", "goalIDs"]
            ))
        ],
        required: ["suggestions"]
    )

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
