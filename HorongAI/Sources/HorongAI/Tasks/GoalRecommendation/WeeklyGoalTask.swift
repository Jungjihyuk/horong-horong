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
        // 프롬프트 크기가 추론 성패를 가르므로(인시던트 2026-07-31) 값이 없는 필드는 생략한다.
        // "없음"으로 채우면 메모당 30자 이상을 정보 없이 소비한다.
        let lines = memos.map { memo in
            var fields = [
                "- id: \(memo.id.uuidString)",
                "  text: \(memo.content)",
                "  icon: \(memo.icon)",
                "  date: \(dateText(memo.date))",
            ]
            if memo.startDate != nil {
                fields.append("  startDate: \(dateText(memo.startDate))")
            }
            if memo.deadline != nil {
                fields.append("  deadline: \(dateText(memo.deadline))")
            }
            // 미완료 할일만 입력으로 들어오므로 기본값일 때는 생략한다.
            if memo.isCompleted {
                fields.append("  completed: true")
            }
            return fields.joined(separator: "\n")
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
            case decodeFailed(characters: Int)
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
    /// 없는 id · 이미 쓴 id · 개수 초과 · 2개 미만 · JSON 깨짐.
    public static func parse(
        _ text: String,
        allowedIDs: Set<UUID>,
        suggestionCount: Int,
        maxMemoCount: Int
    ) -> ParseOutcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let payload = GoalSuggestionPayload(responseText: trimmed) else {
            return ParseOutcome(drafts: [], diagnostics: .decodeFailed(characters: trimmed.count))
        }

        var badID = 0
        var alreadyUsed = 0
        var overMaxMemo = 0
        var tooFewIDs = 0
        var requestedIDs = 0
        var used = Set<UUID>()
        let result = payload.suggestions.compactMap { item -> GoalSuggestionDraft? in
            let raw = item.memoIDs ?? []
            requestedIDs += raw.count
            let parsedIDs = raw.compactMap(UUID.init(uuidString:)).filter { allowedIDs.contains($0) }
            badID += raw.count - parsedIDs.count
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
            let criterion = item.criterion.trimmingCharacters(in: .whitespacesAndNewlines)
            return GoalSuggestionDraft(
                title: title.isEmpty ? "추천 목표" : title,
                reason: item.reason,
                memoIDs: Array(ids),
                scheduleText: item.scheduleText.isEmpty ? "이번 주에 나눠 진행" : item.scheduleText,
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

    // MARK: - 한 번 돌리기

    /// 한 번의 추천에서 일어난 일. 로그 문구는 앱이 정하므로 여기서는 값만 돌려준다.
    public struct RunOutcome {
        public let drafts: [GoalSuggestionDraft]
        public let diagnostics: Diagnostics

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
        onPromptBuilt: (_ characters: Int, _ memoCount: Int) -> Void = { _, _ in },
        generate: (_ prompt: String, _ instructions: String) async throws -> String
    ) async -> RunOutcome {
        let selected = memosWithinPromptBudget(
            Array(memos.prefix(inputLimit)),
            suggestionCount: suggestionCount,
            maxMemoCount: maxMemoCount,
            budget: budget
        )
        let prompt = prompt(
            for: selected,
            suggestionCount: suggestionCount,
            maxMemoCount: maxMemoCount
        )
        onPromptBuilt(prompt.count, selected.count)

        do {
            let text = try await generate(prompt, instructions)
            // 허용 id 는 **자르기 전 전체**다. 예산에 밀려 프롬프트에 안 들어간 id 를 모델이
            // 지어내는 일은 없지만, 좁히면 재시도·캐시 같은 걸 붙일 때 조용히 후보를 잃는다.
            let outcome = parse(
                text,
                allowedIDs: Set(memos.map(\.id)),
                suggestionCount: suggestionCount,
                maxMemoCount: maxMemoCount
            )
            return RunOutcome(drafts: outcome.drafts, diagnostics: .parsed(outcome.diagnostics))
        } catch {
            return RunOutcome(drafts: [], diagnostics: .generationFailed(error))
        }
    }

    // MARK: - 직렬화

    private static func dateText(_ date: Date?) -> String {
        guard let date else { return "없음" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy-MM-dd E HH:mm"
        return formatter.string(from: date)
    }

    private static let promptFallback = """
    아래 할일들을 의미, 아이콘, 시작일, 마감일, 완료 상태를 함께 보고 주간 목표 후보를 최대 {{suggestionCount}}개 제안해줘.
    목표 후보 하나에는 할일을 최대 {{maxMemoCount}}개까지만 넣어.
    각 후보는 사용자가 수정할 수 있는 초안이어야 하고, 같은 할일을 여러 후보에 중복해서 넣지 마.
    존재하는 id만 memoIDs에 넣어.
    scheduleText는 실제 startDate, deadline, date를 고려해 짧게 작성해.

    JSON 형식:
    {
      "suggestions": [
        {
          "title": "목표명",
          "reason": "묶은 이유",
          "memoIDs": ["UUID"],
          "scheduleText": "월/수/금에 나눠 진행",
          "criterion": "연결한 할일 3개 완료",
          "emoji": "🎯"
        }
      ]
    }

    할일:
    {{items}}
    """
}
