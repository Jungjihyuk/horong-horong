import Foundation

/// AI 를 한 번 돌린 결과 한 건. **실험실(골든셋)과 야생(실사용)이 같은 모양을 쓴다.**
///
/// 둘을 나누면 "골든셋에선 좋아졌는데 실사용은 어떤가"를 나란히 놓을 수 없다.
/// 폴더 뼈대 문서가 `Logging/` 의 검산 질문으로 적어둔 것이 정확히 이것이다 —
/// *"평가 결과와 실사용 기록이 같은 모양인가."*
///
/// ## `EvalResult` 에서 정리한 것
///
/// 처음에는 옛 키 7개를 그대로 두려 했다 — 보관된 기준선과의 비교가 깨질까 봐서다.
/// 다시 보니 그 논거가 약했다. 기준선은 **6줄**이고, 우리는 이미 **골든셋 점수로 회귀를
/// 판정하지 않기로** 했다(모델이 비결정적이라 성립하지 않는다). 반대로 기록은 앞으로
/// 계속 쌓이므로, 이름이 안 맞는 채로 두면 되돌리는 비용이 매일 커진다.
///
/// | 옛 키 | 지금 | 왜 |
/// |---|---|---|
/// | `case_id` | 옵셔널 | 실사용에는 시험 문제가 없다 |
/// | `input` | 제거 | 케이스 설명은 골든셋 JSON 에 원본이 있다 |
/// | `level` | 제거 → `recipe` | 문맥 주입 레벨과 기법 조합은 같은 축이다 |
/// | `latency_ms` | `total_ms` | 단계별(`timings`)과 단위를 맞춘다 |
///
/// `Evals/eval-report.py` 와 기준선 6줄은 이 이름에 맞춰 함께 옮긴다.
///
/// ## 여기 담지 않는 것
///
/// 할 일 제목·대화 원문 같은 **사용자 내용은 담지 않는다.** 기록 파일은 밖으로 나갈 수 있다.
/// 대신 `inputSummary.itemIDs` 로 id 만 남기고, 원문이 필요하면 앱이 저장소에서 붙인다.
/// 지워진 항목까지 되짚어야 하면 입력 스냅샷을 **별도 파일**로 남긴다(기록 본체와 분리).
public struct RunRecord: Codable {

    // MARK: - 옛 키 (건드리지 않는다)

    /// **어떤 시험 문제를 풀었나.** 골든셋 케이스 이름(`"도구 이름만 겹치는 함정"` 등)이다.
    ///
    /// `runId`(언제 돌렸나)와 층이 다르다 — 골든셋 한 번 실행은 `runId` 하나에 `caseId` 6개다.
    /// **같은 `caseId` 끼리 세로로 비교하는 것**이 회귀 판정의 핵심이다. 평균만 보면
    /// `0.2778 → 0.3810` 이 "좋아졌다"로 읽히지만, 케이스별로 펼치면 4개는 미동도 없고
    /// 2개만 흔들린 게 보인다 — 그래서 "모델이 튄 것"으로 판정할 수 있었다.
    ///
    /// 실사용에는 정답이 없어 시험 문제가 아니다. `nil` 이고,
    /// 무엇을 넣었는지는 `inputSummary.itemIDs` 로 식별한다.
    public let caseId: String?
    public let model: String?
    /// 사람이 훑어볼 요약. 목표 추천이면 제안 제목 목록이다 — **입력 원문이 아니다.**
    public let output: String
    /// 정답이 있어야 매길 수 있는 점수는 골든셋에서만 채워진다(`pairF1` 등).
    /// 실사용은 비어 있는 것이 정상이다.
    public let scores: [String: Double]
    /// 이 시도 전체에 걸린 시간(ms). 단계별 내역은 `timings`.
    public let totalMs: Int

    // MARK: - 새 키 (전부 옵셔널)

    /// **언제 돌렸나.** 버튼 한 번 = 하나. 골든셋은 스위트 한 바퀴 = 하나.
    public let runId: String?
    public let startedAt: Date?
    /// `"weekly_goal"` · `"monthly_goal"` · `"companion_chat"`.
    /// 스위트마다 채점자가 다르므로(존댓말 검사는 대화용이다) 이 값으로 가른다.
    public let task: String?
    /// `"golden"`(통제된 실험실) · `"live"`(야생).
    public let source: String?
    /// 어떤 기법을 켠 실행인가. **이게 없으면 "기법을 늘려가며 나아졌는가"를 비교할 수 없다.**
    public let recipe: String?
    /// 같은 레시피 안의 실험 표시(프롬프트 문구 A/B 등).
    public let variant: String?
    /// 이 줄에서 실제로 부른 공급자.
    public let provider: String?
    /// 폴백 사슬에서 몇 번째 시도인가(1부터).
    ///
    /// **한 번 누른 실행이 여러 줄이 되는 이유다.** Ollama 가 실패해 AFM 으로 내려가면
    /// 두 시도는 예산이 달라(16k vs 4k) **입력 자체가 다른 질문**이 된다. 최종 결과만 남기면
    /// 실패한 시도의 소요 시간과 입력이 통째로 사라져, "Ollama 가 쓸 만한가"를 잴 수 없다.
    ///
    /// 사슬 전체는 같은 `runId` 의 줄을 `attempt` 순으로 읽으면 그대로 보인다.
    public let attempt: Int?
    public let inputSummary: InputSummary?
    /// `"ok"` · `"generationFailed"` · `"decodeFailed"` · `"parsedEmpty"` · `"modelUnavailable"`.
    public let outcome: String?
    /// 결과를 한 겹 더 들여다본 이유. `decodeFailed` 만으로는 **프롬프트 문제인지 모델 문제인지
    /// 파서 문제인지 가릴 수 없다.** 예: `missingKey:criterion`(모델이 필수 키를 빠뜨림) ·
    /// `noJSON`(JSON 을 아예 안 냄) · `malformed`(중간에 잘림).
    public let outcomeDetail: String?
    public let parse: ParseSummary?
    public let usage: UsageSummary?
    /// 단계별 소요(ms). `select_input` · `render_prompt` · `generate` · `parse`.
    /// 총합만 보면 58초 중 무엇이 오래 걸렸는지 알 수 없다.
    public let timings: [String: Int]?
    public let parameters: [String: Double]?

    // MARK: - 곁딸린 것

    /// 무엇을 넣었나. **개수와 id 까지만** — 원문은 담지 않는다.
    public struct InputSummary: Codable {
        /// 필터를 통과해 **후보 자격을 얻은** 전체 수.
        public let candidateCount: Int?
        /// 그중 실제로 프롬프트에 실린 수.
        ///
        /// `candidateCount` 와 벌어질수록 모델이 못 본 것이 많다는 뜻이다(실측: 123 → 60 → 6).
        /// 하나만 남기면 이 차이가 안 보인다.
        public let itemCount: Int
        public let itemIDs: [String]
        public let promptCharacters: Int

        public init(candidateCount: Int? = nil, itemCount: Int, itemIDs: [String], promptCharacters: Int) {
            self.candidateCount = candidateCount
            self.itemCount = itemCount
            self.itemIDs = itemIDs
            self.promptCharacters = promptCharacters
        }

        enum CodingKeys: String, CodingKey {
            case candidateCount = "candidate_count"
            case itemCount = "item_count"
            case itemIDs = "item_ids"
            case promptCharacters = "prompt_characters"
        }
    }

    /// 모델이 낸 것과 파서가 살린 것. 둘을 나눠야 "모델이 못 냈다"와 "파서가 버렸다"를 가른다.
    public struct ParseSummary: Codable {
        public let modelReturned: Int
        public let kept: Int
        public let requestedIDs: Int
        public let badID: Int
        public let alreadyUsed: Int
        public let overMaxMemo: Int
        public let tooFewIDs: Int

        public init(
            modelReturned: Int,
            kept: Int,
            requestedIDs: Int,
            badID: Int,
            alreadyUsed: Int,
            overMaxMemo: Int,
            tooFewIDs: Int
        ) {
            self.modelReturned = modelReturned
            self.kept = kept
            self.requestedIDs = requestedIDs
            self.badID = badID
            self.alreadyUsed = alreadyUsed
            self.overMaxMemo = overMaxMemo
            self.tooFewIDs = tooFewIDs
        }

        enum CodingKeys: String, CodingKey {
            case modelReturned = "model_returned"
            case kept
            case requestedIDs = "requested_ids"
            case badID = "bad_id"
            case alreadyUsed = "already_used"
            case overMaxMemo = "over_max_memo"
            case tooFewIDs = "too_few_ids"
        }
    }

    /// 모델이 실제로 쓴 양. **공급자마다 알 수 있는 것이 다르다** — 모르면 `nil`.
    public struct UsageSummary: Codable, Sendable {
        public let tokensIn: Int?
        public let tokensOut: Int?

        public init(tokensIn: Int? = nil, tokensOut: Int? = nil) {
            self.tokensIn = tokensIn
            self.tokensOut = tokensOut
        }

        enum CodingKeys: String, CodingKey {
            case tokensIn = "tokens_in"
            case tokensOut = "tokens_out"
        }
    }

    enum CodingKeys: String, CodingKey {
        case caseId = "case_id"
        case model
        case output
        case scores
        case totalMs = "total_ms"
        case runId = "run_id"
        case startedAt = "started_at"
        case task
        case source
        case recipe
        case variant
        case provider
        case attempt
        case inputSummary = "input_summary"
        case outcome
        case outcomeDetail = "outcome_detail"
        case parse
        case usage
        case timings
        case parameters
    }

    public init(
        caseId: String? = nil,
        model: String? = nil,
        output: String,
        scores: [String: Double] = [:],
        totalMs: Int,
        runId: String? = nil,
        startedAt: Date? = nil,
        task: String? = nil,
        source: String? = nil,
        recipe: String? = nil,
        variant: String? = nil,
        provider: String? = nil,
        attempt: Int? = nil,
        inputSummary: InputSummary? = nil,
        outcome: String? = nil,
        outcomeDetail: String? = nil,
        parse: ParseSummary? = nil,
        usage: UsageSummary? = nil,
        timings: [String: Int]? = nil,
        parameters: [String: Double]? = nil
    ) {
        self.caseId = caseId
        self.model = model
        self.output = output
        self.scores = scores
        self.totalMs = totalMs
        self.runId = runId
        self.startedAt = startedAt
        self.task = task
        self.source = source
        self.recipe = recipe
        self.variant = variant
        self.provider = provider
        self.attempt = attempt
        self.inputSummary = inputSummary
        self.outcome = outcome
        self.outcomeDetail = outcomeDetail
        self.parse = parse
        self.usage = usage
        self.timings = timings
        self.parameters = parameters
    }
}
