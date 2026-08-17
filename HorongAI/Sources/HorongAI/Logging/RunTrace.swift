import Foundation

/// 실행 하나가 거쳐 간 단계들의 **원문 기록**.
///
/// `RunRecord` 는 "무엇이 일어났나"를 숫자로 요약한다 — 어느 모델, 몇 초, 성공/실패.
/// 그것만으로는 못 푸는 질문이 있다: **"모델이 대체 뭐라고 답했길래?"**
///
/// 실제로 그 벽에 부딪혔다. `decodeFailed · typeMismatch:Index 0` 이라는 기록은 남았는데
/// 모델 응답 원문이 없어서 `memoIDs` 가 숫자로 왔는지 객체로 왔는지 알 수 없었다.
/// 정황은 다 있고 증거만 없는 상태였다.
///
/// 그래서 요약과 원문을 갈라 둔다.
/// - `RunRecord` → 항상 남긴다. 가볍고, 집계·비교에 쓴다
/// - `RunTrace`  → 개발자 모드에서만 남긴다. 무겁고, 한 건을 파고들 때 쓴다
///
/// 둘은 `runId` 로 이어진다. 새 연결 장치가 필요 없다 — 모든 기록이 이미 `runId` 를 갖고 있다.
///
/// 용어를 `trace` / `span` 으로 둔 이유는 LLM 관측 도구들(LangSmith · Langfuse · Phoenix)과
/// OpenTelemetry 가 같은 말을 쓰기 때문이다. 나중에 그런 도구로 옮길 때 개념이 그대로 간다.
public struct RunTrace: Codable, Sendable {
    public let runId: String
    public let task: String?
    public let provider: String?
    public let model: String?
    public let startedAt: Date
    public private(set) var spans: [Span]

    public init(
        runId: String,
        task: String? = nil,
        provider: String? = nil,
        model: String? = nil,
        startedAt: Date = Date(),
        spans: [Span] = []
    ) {
        self.runId = runId
        self.task = task
        self.provider = provider
        self.model = model
        self.startedAt = startedAt
        self.spans = spans
    }

    public mutating func append(_ span: Span) {
        spans.append(span)
    }

    /// 한 단계. 이름과 그때의 텍스트를 그대로 담는다.
    public struct Span: Codable, Sendable {
        public let name: Name
        public let text: String
        public let at: Date
        /// 숫자로 남길 만한 부수 정보(길이·개수 등). 원문을 다 읽지 않고도 훑을 수 있게.
        public let facts: [String: Int]?

        public init(_ name: Name, text: String, at: Date = Date(), facts: [String: Int]? = nil) {
            self.name = name
            self.text = text
            self.at = at
            self.facts = facts
        }

        /// 단계 이름을 자유 문자열로 두면 오타가 조용히 새 단계를 만든다.
        public enum Name: String, Codable, Sendable {
            /// 모델에 넣기로 고른 입력(예산에 잘린 뒤의 것).
            case input
            /// 실제로 보낸 프롬프트 전문.
            case prompt
            /// 모델이 돌려준 원문. **이것이 없어서 막혔던 자리다.**
            case rawResponse
            /// 원문에서 JSON 만 뽑아낸 결과. `<think>` 제거·코드펜스 추출이
            /// 실제로 일했는지는 이 값을 봐야 안다.
            case extractedJSON
            /// 파싱해 살아남은 결과.
            case parsed
            /// 실패했을 때의 오류 설명.
            case failure
        }
    }
}
