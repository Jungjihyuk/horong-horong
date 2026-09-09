import Foundation

/// 타임라인 주제를 제안받고, 사용자가 고른 주제로 타임라인을 만든다.
///
/// **자동으로 만들지 않는다.** 리포트 생성과 완전히 분리되어 있고, 오직 사용자가 버튼을
/// 눌렀을 때만 동작한다 — 원한 적 없는 분야에 LLM 비용이 조용히 나가면 안 되기 때문이다.
/// 구현은 `Data/Adapters/News/` 에 있다.
@MainActor
protocol NewsTimelineGateway {
    /// 리포트에서 만들 수 있는 주제를 찾는다. LLM 을 쓰지 않아 즉시 끝난다.
    func suggestTopics(dataBasePath: String) async throws -> [NewsTimelineSuggestion]

    /// 고른 주제로 타임라인을 만들거나 갱신한다. 여기서만 LLM 이 돈다.
    func buildTimeline(label: String, dataBasePath: String) async throws
}

/// 타임라인 생성이 실패한 이유. 사용자에게 그대로 보여줄 수 있는 문장을 담는다.
enum NewsTimelineError: LocalizedError, Equatable {
    /// `timeline_runner.py` 를 찾지 못했다.
    case runnerNotFound
    /// 러너가 0이 아닌 코드로 끝났다.
    case runnerFailed(code: Int32, message: String)
    /// 출력이 기대한 JSON 이 아니었다.
    case malformedOutput

    var errorDescription: String? {
        switch self {
        case .runnerNotFound:
            return "타임라인 실행기(timeline_runner.py)를 찾지 못했습니다. 설정에서 러너 경로를 확인하세요."
        case .runnerFailed(let code, let message):
            return message.isEmpty ? "타임라인 생성이 실패했습니다 (코드 \(code))" : message
        case .malformedOutput:
            return "타임라인 실행기의 응답을 읽지 못했습니다."
        }
    }
}
