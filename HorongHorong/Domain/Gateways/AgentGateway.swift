import Foundation

/// 외부 Agent 에게 실험을 시킨다. 구현은 `Data/Adapters/` 에 있다.
///
/// **결과를 기다리지 않는다.** 실행은 터미널에서 사용자 눈앞에 일어나고, 이 앱이 아는 것은
/// 「전달했다」와 「어느 파일을 쓸 예정인가」까지다. 그래서 반환값이 파일 이름뿐이다.
@MainActor
protocol AgentGateway {
    /// N일치 실험 계획 파일을 만들도록 시킨다.
    func generatePlan(_ request: AgentPlanRequest) throws -> AgentPlanLaunchResult

    /// 이미 만들어진 계획에서 오늘 몫을 뽑아 실행을 시킨다.
    func runTodayExperiment(_ request: TodayExperimentRequest) throws -> TodayExperimentRunResult
}

struct AgentPlanRequest: Equatable, Sendable {
    let ideaDirectoryPath: String
    let outputDirectoryPath: String
    /// 이미 «비어 있으면 기본값» 처리가 끝난 값. 경계 안에서 다시 판단하지 않는다.
    let interestKeywords: String
    let agent: AgentKind
    let dayCount: Int
}

struct AgentPlanLaunchResult: Equatable, Sendable {
    let outputFileName: String
}

struct TodayExperimentRequest: Equatable, Sendable {
    let outputDirectoryPath: String
    let interestKeywords: String
    let agent: AgentKind
}

struct TodayExperimentRunResult: Equatable, Sendable {
    let planFileName: String
}

enum AgentRunError: LocalizedError, Equatable {
    case invalidDirectory(String)
    case scriptExecutionFailed(String)
    case planFileNotFound(String)
    case todaySectionNotFound(String)
    case fileReadFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidDirectory(let path):
            return "경로를 확인하세요: \(path)"
        case .scriptExecutionFailed(let message):
            return "터미널 실행 실패: \(message)"
        case .planFileNotFound(let directory):
            return "계획 파일을 찾을 수 없습니다: \(directory)"
        case .todaySectionNotFound(let file):
            return "오늘 날짜 섹션을 찾을 수 없습니다: \(file)"
        case .fileReadFailed(let file):
            return "파일 읽기 실패: \(file)"
        }
    }
}
