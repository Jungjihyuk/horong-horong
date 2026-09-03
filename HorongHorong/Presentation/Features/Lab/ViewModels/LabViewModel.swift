import Foundation
import Observation

/// 화면이 들고 있는 설정값 묶음.
///
/// `@AppStorage` 는 뷰에 두고 값만 넘긴다 — ViewModel 이 `UserDefaults` 를 직접 읽으면
/// 테스트가 사용자 기본값에 딸려 간다.
struct LabSettings: Equatable {
    var agentRootDirectoryPath: String
    var interestKeywords: String
    var agent: AgentKind
    var dayCount: Int
}

/// 실행을 시킨 결과. 뷰는 이걸 보고 토스트를 띄운다.
enum LabOutcome: Equatable {
    case planStarted(fileName: String, agent: AgentKind)
    case experimentStarted(fileName: String, agent: AgentKind)
    case failed(String)
}

/// 실험실 화면의 상태.
///
/// SwiftData 를 쓰지 않는 화면이라 `@Query` 문제는 없었다. 옮긴 이유는 **터미널 실행과
/// 프롬프트 조립이 뷰 안에 있어 검사할 수 없어서**다. 지금 이 클래스는 「어떤 요청을
/// 만들지」만 정하고, 실제 실행은 `AgentGateway` 뒤에 있다.
@MainActor
@Observable
final class LabViewModel {
    private(set) var statusMessage = ""

    private let gateway: AgentGateway

    init(gateway: AgentGateway) {
        self.gateway = gateway
    }

    @discardableResult
    func generatePlan(_ settings: LabSettings) -> LabOutcome {
        let root = settings.agentRootDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = AgentPlanRequest(
            ideaDirectoryPath: Constants.agentIdeaDirectoryPath(for: root),
            outputDirectoryPath: Constants.agentOutputDirectoryPath(for: root),
            interestKeywords: Self.keywords(settings.interestKeywords),
            agent: settings.agent,
            dayCount: settings.dayCount
        )

        do {
            let result = try gateway.generatePlan(request)
            statusMessage = "터미널에서 \(settings.agent.rawValue) 실행 시작. 출력 예정: \(result.outputFileName)"
            return .planStarted(fileName: result.outputFileName, agent: settings.agent)
        } catch {
            return fail(error)
        }
    }

    @discardableResult
    func runTodayExperiment(_ settings: LabSettings) -> LabOutcome {
        let root = settings.agentRootDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = TodayExperimentRequest(
            outputDirectoryPath: Constants.agentOutputDirectoryPath(for: root),
            interestKeywords: Self.keywords(settings.interestKeywords),
            agent: settings.agent
        )

        do {
            let result = try gateway.runTodayExperiment(request)
            statusMessage = "터미널에서 오늘 실험 실행 시작: \(result.planFileName)"
            return .experimentStarted(fileName: result.planFileName, agent: settings.agent)
        } catch {
            return fail(error)
        }
    }

    /// 비어 있으면 기본 키워드로 채운다. **경계를 넘기 전에 한 번만 한다** —
    /// Gateway 안에서 또 판단하면 「빈 값을 넘겼을 때 무슨 일이 나는가」가 두 곳에 생긴다.
    private static func keywords(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Constants.defaultInterestKeywords : raw
    }

    private func fail(_ error: Error) -> LabOutcome {
        let message = error.localizedDescription
        statusMessage = "실패: \(message)"
        return .failed(message)
    }
}
