import XCTest
@testable import 호롱호롱

/// **터미널을 띄우지 않고** 실험실 화면이 어떤 요청을 만드는지 검사한다.
@MainActor
final class LabViewModelTests: XCTestCase {
    private final class FakeGateway: AgentGateway {
        private(set) var planRequest: AgentPlanRequest?
        private(set) var experimentRequest: TodayExperimentRequest?
        var error: Error?

        func generatePlan(_ request: AgentPlanRequest) throws -> AgentPlanLaunchResult {
            planRequest = request
            if let error { throw error }
            return AgentPlanLaunchResult(outputFileName: "plan.md")
        }

        func runTodayExperiment(_ request: TodayExperimentRequest) throws -> TodayExperimentRunResult {
            experimentRequest = request
            if let error { throw error }
            return TodayExperimentRunResult(planFileName: "today.md")
        }
    }

    private func settings(keywords: String = "자동화", dayCount: Int = 5) -> LabSettings {
        LabSettings(
            agentRootDirectoryPath: "  /root  ",
            interestKeywords: keywords,
            agent: .claude,
            dayCount: dayCount
        )
    }

    func testPlanRequestDerivesPathsFromRoot() {
        let gateway = FakeGateway()
        let viewModel = LabViewModel(gateway: gateway)

        viewModel.generatePlan(settings())

        let request = gateway.planRequest
        XCTAssertEqual(request?.ideaDirectoryPath, Constants.agentIdeaDirectoryPath(for: "/root"))
        XCTAssertEqual(request?.outputDirectoryPath, Constants.agentOutputDirectoryPath(for: "/root"))
        XCTAssertEqual(request?.agent, .claude)
        XCTAssertEqual(request?.dayCount, 5)
    }

    /// 키워드가 비면 **경계를 넘기 전에** 기본값으로 채운다. Gateway 가 또 판단하지 않게.
    func testBlankKeywordsAreFilledBeforeCrossingTheBoundary() {
        let gateway = FakeGateway()
        let viewModel = LabViewModel(gateway: gateway)

        viewModel.generatePlan(settings(keywords: "   "))

        XCTAssertEqual(gateway.planRequest?.interestKeywords, Constants.defaultInterestKeywords)
    }

    func testKeywordsArePassedThroughWhenPresent() {
        let gateway = FakeGateway()
        let viewModel = LabViewModel(gateway: gateway)

        viewModel.generatePlan(settings(keywords: "회고, 자동화"))

        XCTAssertEqual(gateway.planRequest?.interestKeywords, "회고, 자동화")
    }

    func testSuccessReportsFileNameAndAgent() {
        let viewModel = LabViewModel(gateway: FakeGateway())

        let outcome = viewModel.generatePlan(settings())

        XCTAssertEqual(outcome, .planStarted(fileName: "plan.md", agent: .claude))
        XCTAssertTrue(viewModel.statusMessage.contains("plan.md"))
        XCTAssertTrue(viewModel.statusMessage.contains("Claude"))
    }

    func testExperimentUsesOutputDirectoryOnly() {
        let gateway = FakeGateway()
        let viewModel = LabViewModel(gateway: gateway)

        let outcome = viewModel.runTodayExperiment(settings())

        XCTAssertEqual(gateway.experimentRequest?.outputDirectoryPath, Constants.agentOutputDirectoryPath(for: "/root"))
        XCTAssertEqual(outcome, .experimentStarted(fileName: "today.md", agent: .claude))
    }

    /// 실패하면 사람이 읽을 수 있는 이유가 상태 메시지에 남는다.
    func testFailureSurfacesReason() {
        let gateway = FakeGateway()
        gateway.error = AgentRunError.planFileNotFound("/root/output")
        let viewModel = LabViewModel(gateway: gateway)

        let outcome = viewModel.runTodayExperiment(settings())

        guard case .failed(let message) = outcome else { return XCTFail("실패로 보고해야 한다") }
        XCTAssertTrue(message.contains("/root/output"))
        XCTAssertTrue(viewModel.statusMessage.hasPrefix("실패: "))
    }
}
