import Foundation

/// 할일 목록을 주고 **주간 목표 후보**를 받아오는 태스크.
///
/// 프롬프트 만들기 · 입력 고르기(예산) · 응답 읽기를 한 자리에 둔다. 셋은 함께 바뀐다 —
/// 프롬프트의 JSON 형식을 고치면 파서도 같이 고쳐야 하기 때문이다.
///
/// 공급자(AFM · MLX · Ollama)를 가리지 않는다. 셋 다 같은 프롬프트·파서를 써야
/// 골든셋에서 모델끼리 공정하게 비교된다.
public enum WeeklyGoalTask {

    /// 프롬프트에 실리는 할일 하나.
    ///
    /// 앱의 저장 모델을 그대로 받지 않는 이유는 패키지가 앱 도메인 타입을 알면 안 되기 때문이다.
    /// 아이콘 기본값처럼 **앱이 정하는 값**은 경계를 넘기 전에 앱이 채워 넣는다.
    public struct Memo: Sendable, Hashable, Identifiable {
        public let id: UUID
        public let content: String
        public let icon: String
        public let date: Date
        public let startDate: Date?
        public let deadline: Date?
        public let isCompleted: Bool

        public init(
            id: UUID,
            content: String,
            icon: String,
            date: Date,
            startDate: Date? = nil,
            deadline: Date? = nil,
            isCompleted: Bool = false
        ) {
            self.id = id
            self.content = content
            self.icon = icon
            self.date = date
            self.startDate = startDate
            self.deadline = deadline
            self.isCompleted = isCompleted
        }
    }

    /// 세션 지시문. 세 공급자(AFM · MLX · Ollama)가 **같은 문장**을 써야
    /// 골든셋에서 모델끼리 공정하게 비교된다. 한때 세 파일에 각각 박혀 있었다.
    public static let instructions =
        "너는 사용자의 할일을 목표 지향적으로 묶어주는 생산성 앱 도우미다. 응답은 반드시 유효한 JSON만 출력한다."

    // MARK: - 입력 고르기

    /// 프롬프트가 문자 예산을 넘지 않는 선까지만 메모를 담는다.
    /// 메모 길이는 사용자마다 제각각이라 "개수" 상한만으로는 크기를 보장할 수 없다.
    ///
    /// 예산은 공급자마다 다르므로(AFM 4,000 · MLX/Ollama 16,000) 태스크가 정하지 않고 받는다.
    public static func memosWithinPromptBudget(
        _ memos: [Memo],
        suggestionCount: Int,
        maxMemoCount: Int,
        budget: Int
    ) -> [Memo] {
        // 묶으려면 최소 2개는 있어야 하므로 예산을 넘더라도 2개는 유지한다.
        let minimumCount = min(2, memos.count)
        var selected = memos
        while selected.count > minimumCount {
            let size = prompt(
                for: selected,
                suggestionCount: suggestionCount,
                maxMemoCount: maxMemoCount
            ).count
            if size <= budget { break }
            selected.removeLast()
        }
        return selected
    }

    // MARK: - 프롬프트

    public static func prompt(
        for memos: [Memo],
        suggestionCount: Int,
        maxMemoCount: Int
    ) -> String {
        let lines = memos.enumerated().map { index, memo in
            let number = index + 1
            // 첫 줄 한 문장만 추출 (최대 80자)
            let firstLine = memo.content
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty }) ?? memo.content
            let cleanTitle = String(firstLine.prefix(80))

            var meta: [String] = []
            if let deadline = memo.deadline {
                meta.append("~\(dateText(deadline)) 마감")
            } else if let startDate = memo.startDate {
                meta.append("\(dateText(startDate)) 시작")
            }
            if memo.isCompleted {
                meta.append("완료됨")
            }

            if meta.isEmpty {
                return "[\(number)] \(cleanTitle)"
            } else {
                return "[\(number)] \(cleanTitle) (\(meta.joined(separator: ", ")))"
            }
        }.joined(separator: "\n")

        return PromptRenderer.render(
            fileName: "weekly_goal",
            fallback: promptFallback,
            values: [
                "suggestionCount": "\(suggestionCount)",
                "maxMemoCount": "\(maxMemoCount)",
                "items": lines,
            ]
        )
    }

    // MARK: - 응답 읽기

    /// 파싱 결과와 진단값. 로그 문구는 앱이 정하므로 여기서는 숫자만 돌려준다 —
    /// 패키지가 앱의 `OSLog` 카테고리를 알면 안 되기 때문이다.
    public struct ParseOutcome: Sendable {
        public let drafts: [GoalSuggestionDraft]
        public let diagnostics: Diagnostics

        public enum Diagnostics: Sendable {
            /// JSON 을 읽지 못했다. `characters` 는 다듬은 응답 길이 — 잘림인지 형식 문제인지 가른다.
            /// `reason` 은 왜 못 읽었나(`noJSON` · `missingKey:criterion` 등).
            case decodeFailed(characters: Int, reason: String)
            /// 모델이 낸 개수(`modelReturned`)와 파서가 살린 개수(`kept`)를 구분해야
            /// "모델이 적게 냄"과 "파서가 버림"을 나눌 수 있다.
            /// `kept` 는 개수 상한으로 자르기 **전** 값이다.
            case decoded(
                modelReturned: Int,
                kept: Int,
                requestedIDs: Int,
                badID: Int,
                alreadyUsed: Int,
                overMaxMemo: Int,
                tooFewIDs: Int
            )
        }
    }

    /// 모델 응답을 후보 목록으로 바꾼다. 모델을 믿지 않고 다섯 갈래로 방어한다 —
    /// 없는 id/번호 · 이미 쓴 id · 개수 초과 · 2개 미만 · JSON 깨짐.
    public static func parse(
        _ text: String,
        memos: [Memo] = [],
        allowedIDs: Set<UUID>,
        suggestionCount: Int,
        maxMemoCount: Int
    ) -> ParseOutcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: GoalSuggestionPayload
        switch GoalSuggestionPayload.decode(from: trimmed) {
        case .success(let decoded):
            payload = decoded
        case .failure(let failure):
            return ParseOutcome(
                drafts: [],
                diagnostics: .decodeFailed(characters: trimmed.count, reason: failure.reason)
            )
        }

        var badID = 0
        var alreadyUsed = 0
        var overMaxMemo = 0
        var tooFewIDs = 0
        var requestedIDs = 0
        var used = Set<UUID>()
        let result = payload.suggestions.compactMap { item -> GoalSuggestionDraft? in
            let rawValues: [GoalSuggestionPayload.IDValue] = (item.items ?? item.memoIDs ?? item.goalIDs)?.values ?? []
            requestedIDs += rawValues.count
            
            var parsedIDs: [UUID] = []
            for idVal in rawValues {
                switch idVal {
                case .int(let idx):
                    // 1-based index 매핑 ([1] -> memos[0].id)
                    if idx >= 1 && idx <= memos.count {
                        let id = memos[idx - 1].id
                        if allowedIDs.contains(id) {
                            parsedIDs.append(id)
                        } else {
                            badID += 1
                        }
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
            let ids = unused.prefix(maxMemoCount)
            overMaxMemo += unused.count - ids.count
            guard ids.count >= 2 else {
                tooFewIDs += 1
                return nil
            }
            used.formUnion(ids)
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let criterion = item.criterion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let scheduleText = item.scheduleText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return GoalSuggestionDraft(
                title: title.isEmpty ? "추천 목표" : title,
                reason: item.reason,
                memoIDs: Array(ids),
                scheduleText: scheduleText.isEmpty ? "이번 주에 나눠 진행" : scheduleText,
                criterion: criterion.isEmpty ? "연결한 할일 \(ids.count)개 완료" : criterion,
                targetValueText: "\(ids.count)개",
                emoji: item.emoji?.isEmpty == false ? String(item.emoji!.prefix(1)) : "🎯"
            )
        }

        return ParseOutcome(
            drafts: Array(result.prefix(suggestionCount)),
            diagnostics: .decoded(
                modelReturned: payload.suggestions.count,
                kept: result.count,
                requestedIDs: requestedIDs,
                badID: badID,
                alreadyUsed: alreadyUsed,
                overMaxMemo: overMaxMemo,
                tooFewIDs: tooFewIDs
            )
        )
    }

    public static func parse(
        _ text: String,
        allowedIDs: Set<UUID>,
        suggestionCount: Int,
        maxMemoCount: Int
    ) -> ParseOutcome {
        parse(
            text,
            memos: [],
            allowedIDs: allowedIDs,
            suggestionCount: suggestionCount,
            maxMemoCount: maxMemoCount
        )
    }

    // MARK: - 한 번 돌리기

    public struct GenerationOutput: Sendable {
        public let text: String
        public let usage: RunRecord.UsageSummary?

        public init(text: String, usage: RunRecord.UsageSummary? = nil) {
            self.text = text
            self.usage = usage
        }
    }

    /// 한 번의 추천에서 일어난 일. 로그 문구는 앱이 정하므로 여기서는 값만 돌려준다.
    public struct RunOutcome {
        public let drafts: [GoalSuggestionDraft]
        public let diagnostics: Diagnostics
        /// 실제로 프롬프트에 실린 입력의 id. **무엇을 보여줬는지**를 되짚는 축이다.
        /// 원문은 담지 않는다 — 필요하면 앱이 저장소에서 붙인다.
        public let selectedIDs: [UUID]
        public let promptCharacters: Int
        /// 단계별 소요(ms). 총합만 보면 58초 중 무엇이 오래 걸렸는지 알 수 없다.
        public let timings: [String: Int]
        public let usage: RunRecord.UsageSummary?

        public init(
            drafts: [GoalSuggestionDraft],
            diagnostics: Diagnostics,
            selectedIDs: [UUID],
            promptCharacters: Int,
            timings: [String: Int],
            usage: RunRecord.UsageSummary? = nil
        ) {
            self.drafts = drafts
            self.diagnostics = diagnostics
            self.selectedIDs = selectedIDs
            self.promptCharacters = promptCharacters
            self.timings = timings
            self.usage = usage
        }

        public enum Diagnostics {
            case parsed(ParseOutcome.Diagnostics)
            /// 모델을 부르다 실패했다.
            ///
            /// 문자열이 아니라 `Error` 를 그대로 돌려주는 이유는 **에러를 어떻게 적을지가 앱 정책**이기
            /// 때문이다. 앱은 릴리스 빌드에서 타입 이름만 남긴다 — 에러 설명에 프롬프트가 섞여 나오면
            /// 사용자의 할 일 제목이 로그에 남는다. 여기서 `String(describing:)` 로 바꿔 버리면
            /// 그 판단을 앱이 되돌릴 수 없다.
            case generationFailed(Error)
        }
    }

    /// 입력 고르기 → 프롬프트 → 생성 → 파싱을 한 줄기로 잇는다.
    ///
    /// **평가가 제품과 같은 경로를 타야 의미가 있다.** 앱이 이 순서를 따로 들고 있으면
    /// 한쪽만 바뀌었을 때 평가 결과가 제품을 더 이상 반영하지 않는데, 그건 조용히 일어난다.
    ///
    /// 모델을 부르는 일은 `generate` 로 주입받는다 — 그래야 실모델과 고정 응답이 같은 줄기를 탄다.
    ///
    /// - Parameters:
    ///   - inputLimit: 예산을 재기 전에 개수로 먼저 자르는 상한. 공급자마다 다르다(AFM 은 좁다).
    ///   - budget: 프롬프트 문자 상한. 공급자가 아는 값이라 태스크는 받아 쓰기만 한다.
    ///   - onPromptBuilt: 프롬프트를 만든 **직후** 불린다. 모델이 영영 안 돌아올 때
    ///     "프롬프트까지는 만들어졌다"를 남기려면 생성 전에 기록해야 한다(인시던트 2026-07-31).
    public static func run(
        memos: [Memo],
        suggestionCount: Int,
        maxMemoCount: Int,
        inputLimit: Int,
        budget: Int,
        timeoutInterval: TimeInterval = 60.0,
        onPromptBuilt: (_ characters: Int, _ memoCount: Int) -> Void = { _, _ in },
        /// 원문을 모을 자리. 개발자 모드가 아니면 `nil` 이라 아무 비용도 들지 않는다.
        /// `RunOutcome` 에 원문을 싣지 않기로 한 결정을 지키면서 원문을 꺼내는 통로다.
        trace: TraceCollector? = nil,
        // 타임아웃을 태스크 그룹으로 재므로 클로저가 탈출한다.
        generate: @escaping (_ prompt: String, _ instructions: String) async throws -> GenerationOutput
    ) async -> RunOutcome {
        let clock = StepClock()

        let selected = memosWithinPromptBudget(
            Array(memos.prefix(inputLimit)),
            suggestionCount: suggestionCount,
            maxMemoCount: maxMemoCount,
            budget: budget
        )
        clock.mark("select_input")

        let prompt = prompt(
            for: selected,
            suggestionCount: suggestionCount,
            maxMemoCount: maxMemoCount
        )
        clock.mark("render_prompt")
        onPromptBuilt(prompt.count, selected.count)
        trace?.add(.input, selected.map { "- \($0.id): \($0.content)" }.joined(separator: "\n"),
                   facts: ["selected": selected.count, "candidates": memos.count])
        trace?.add(.prompt, prompt, facts: ["characters": prompt.count])

        func outcome(
            drafts: [GoalSuggestionDraft],
            diagnostics: RunOutcome.Diagnostics,
            usage: RunRecord.UsageSummary?
        ) -> RunOutcome {
            RunOutcome(
                drafts: drafts,
                diagnostics: diagnostics,
                selectedIDs: selected.map(\.id),
                promptCharacters: prompt.count,
                timings: clock.elapsed,
                usage: usage
            )
        }

        do {
            let genOutput = try await withThrowingTaskGroup(of: GenerationOutput.self) { group in
                group.addTask {
                    try await generate(prompt, instructions)
                }
                group.addTask {
                    // 생성 60초 타임아웃: 실측(2026-08-14)에서 Ollama 무한 루프/지연 발생 시
                    // 107초 이상 사용자가 대기하는 문제를 방지하기 위해 60초 상한 설정.
                    // 초과 시 빠른 폴백(AFM/룰)을 유도한다.
                    let nanoseconds = UInt64(max(0.001, timeoutInterval) * 1_000_000_000)
                    try await Task.sleep(nanoseconds: nanoseconds)
                    throw CancellationError()
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
            clock.mark("generate")
            // 원문이 없어서 `typeMismatch:Index 0` 를 못 쫓았던 자리다(2026-08-17).
            // 추출 결과도 함께 남긴다 — `<think>` 제거·코드펜스 처리가 실제로 일했는지는
            // 이 둘을 나란히 놓아야만 알 수 있다.
            trace?.add(.rawResponse, genOutput.text, facts: ["characters": genOutput.text.count])
            trace?.add(.extractedJSON, GoalSuggestionPayload.extractJSONObject(from: genOutput.text))
            // 허용 id 는 **자르기 전 전체**다. 예산에 밀려 프롬프트에 안 들어간 id 를 모델이
            // 지어내는 일은 없지만, 좁히면 재시도·캐시 같은 걸 붙일 때 조용히 후보를 잃는다.
            let parsed = parse(
                genOutput.text,
                memos: selected,
                allowedIDs: Set(memos.map(\.id)),
                suggestionCount: suggestionCount,
                maxMemoCount: maxMemoCount
            )
            clock.mark("parse")
            trace?.add(.parsed, parsed.drafts.map { "- \($0.title)" }.joined(separator: "\n"),
                       facts: ["kept": parsed.drafts.count])
            return outcome(drafts: parsed.drafts, diagnostics: .parsed(parsed.diagnostics), usage: genOutput.usage)
        } catch {
            clock.mark("generate")
            trace?.add(.failure, String(describing: error))
            return outcome(drafts: [], diagnostics: .generationFailed(error), usage: nil)
        }
    }

    /// 단순 문자열 반환 generate 클로저를 위한 편의 오버로드.
    public static func run(
        memos: [Memo],
        suggestionCount: Int,
        maxMemoCount: Int,
        inputLimit: Int,
        budget: Int,
        timeoutInterval: TimeInterval = 60.0,
        onPromptBuilt: (_ characters: Int, _ memoCount: Int) -> Void = { _, _ in },
        trace: TraceCollector? = nil,
        generate: @escaping (_ prompt: String, _ instructions: String) async throws -> String
    ) async -> RunOutcome {
        await run(
            memos: memos,
            suggestionCount: suggestionCount,
            maxMemoCount: maxMemoCount,
            inputLimit: inputLimit,
            budget: budget,
            timeoutInterval: timeoutInterval,
            onPromptBuilt: onPromptBuilt,
            trace: trace,
            generate: { prompt, instructions in
                let text = try await generate(prompt, instructions)
                return GenerationOutput(text: text, usage: nil)
            }
        )
    }

    // MARK: - 직렬화

    private static func dateText(_ date: Date?) -> String {
        guard let date else { return "없음" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M/d(E)"
        return formatter.string(from: date)
    }

    /// 모델이 낼 수 있는 응답의 모양. 위 프롬프트의 «JSON 형식» 과 **같은 것을 두 번 적은 것**이라
    /// 한쪽만 고치면 어긋난다. 프롬프트 바로 옆에 두는 이유가 그것이다.
    ///
    /// `scheduleText` · `criterion` 은 필수로 걸지 않는다 — 파서가 기본값을 채우므로
    /// 모델에게 지어내라고 시킬 이유가 없다(토큰만 쓰고 내용도 나빠진다).
    public static let responseSchema = JSONSchema.object(
        properties: [
            "suggestions": .array(of: .object(
                properties: [
                    "title": .string,
                    "reason": .string,
                    // 주간은 할일 **번호**로 받는다. 스키마가 정수 배열이라
                    // `[[16],[17]]` 같은 중첩은 애초에 만들 수 없다.
                    "items": .array(of: .integer),
                    "emoji": .string,
                ],
                required: ["title", "reason", "items"]
            ))
        ],
        required: ["suggestions"]
    )

    private static let promptFallback = """
    너는 사용자가 등록한 할일들을 분석해서, 이번 주에 추진할 "의미 있는 주간 목표"로 묶어주는 어시스턴트야.

    [가장 중요한 묶는 기준]
    - 할일의 목적, 즉 "무엇을 이루려는가"가 같거나 하나의 결과물로 이어지는 것끼리만 묶어.
    - 같은 단어, 해시태그, 도구명, 앱 이름, 채널명, 파일명, URL 패턴이 겹친다는 이유로 묶지 마.
    - 표면적인 키워드 일치는 묶는 근거가 될 수 없어.
    - "이 할일들을 다 끝내면 하나의 결과나 진전이 생기는가?"에 yes일 때만 한 목표로 묶어.

    [목표 품질 규칙]
    - 최대 {{suggestionCount}}개까지 제안할 수 있지만, 반드시 {{suggestionCount}}개를 만들 필요는 없어.
    - 의미 있게 묶이는 후보가 적으면 적게 내고, 없으면 "suggestions": []로 비워도 돼.
    - 한 목표에는 서로 직접 관련된 할일을 2개 이상, {{maxMemoCount}}개 이하로 넣어.
    - {{maxMemoCount}}개를 초과해서 넣으면 초과분은 그냥 버려진다. 절대 한 목표에 몰아넣지 마.
    - 관련된 할일이 {{maxMemoCount}}개를 넘으면 목적별로 더 잘게 나눠서 서로 다른 목표 여러 개로 제안해.
    - 어느 목표에도 자연스럽게 속하지 않는 할일은 어디에도 넣지 말고 제외해.
    - 같은 할일을 여러 후보에 중복해서 넣지 마.
    - 존재하는 할일 번호([1], [2] 등)만 items에 넣어.
    - 입력에 없는 구체적인 숫자, 결과, 마감 조건을 만들지 마.

    [필드 작성 규칙]
    - title: 도구명이나 키워드가 아니라, 이루려는 결과를 담은 구체적인 문장으로 써.
    - reason: 어떤 공통 목적이나 결과물 때문에 묶었는지 구체적으로 써.
    - items: 묶은 할일의 번호 배열 (예: [1, 2])
    - emoji: 목표의 결과나 행동을 대표하는 아이콘 하나를 골라 (예: "🎯")

    JSON 형식:
    {
      "suggestions": [
        {
          "title": "결과를 담은 목표명",
          "reason": "묶은 공통 목적",
          "items": [1, 2],
          "emoji": "🎯"
        }
      ]
    }

    할일:
    {{items}}
    """
}
