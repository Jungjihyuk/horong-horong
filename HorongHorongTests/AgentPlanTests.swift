import XCTest
@testable import 호롱호롱

/// 실험실의 순수 규칙들. **예전에는 전부 뷰 파일 안 `private static func` 이라 검사할 수
/// 없었다** — 계층을 나눈 이유가 이것이다.
@MainActor
final class AgentPlanTests: XCTestCase {
    // MARK: - 계획 파일 이름

    func testOutputFileNameFormat() {
        let date = DateComponents(calendar: .current, year: 2026, month: 9, day: 3).date!
        XCTAssertEqual(
            ExperimentPlanText.outputFileName(on: date, dayCount: 5),
            "2026-09-03_experiment_plan_5d.md"
        )
    }

    /// 이 접두사로 나중에 파일을 다시 찾는다. 이름 규칙과 찾는 규칙이 어긋나면 안 된다.
    func testFileNameIsFoundByItsOwnDatePrefix() {
        let date = DateComponents(calendar: .current, year: 2026, month: 9, day: 3).date!
        let name = ExperimentPlanText.outputFileName(on: date, dayCount: 3)

        XCTAssertTrue(name.hasPrefix("\(ExperimentPlanText.isoDate(date))_experiment_plan_"))
    }

    // MARK: - 오늘 섹션 잘라내기

    private let plan = """
    # 3일 실험 계획
    생성일: 2026-09-02

    ## Day 1 (수) - 첫째 날
    > 날짜: 2026-09-02

    - [ ] 완료
    **목표**: 어제 목표

    ## Day 2 (목) - 둘째 날

    - [ ] 완료
    > 날짜: 2026-09-03
    **목표**: 오늘 목표

    ## Day 3 (금) - 셋째 날
    > 날짜: 2026-09-04
    **목표**: 내일 목표
    """

    /// 날짜 줄이 섹션 제목 **바로 아래가 아니어도** 그 섹션을 찾아야 한다.
    func testTodaySectionFoundWhenDateLineIsNotFirst() {
        let section = ExperimentPlanText.todaySection(in: plan, today: "2026-09-03")

        XCTAssertNotNil(section)
        XCTAssertTrue(section!.hasPrefix("## Day 2 (목) - 둘째 날"))
        XCTAssertTrue(section!.contains("오늘 목표"))
    }

    /// 다음 `## Day` 를 넘어가면 안 된다.
    func testTodaySectionStopsAtNextDay() {
        let section = ExperimentPlanText.todaySection(in: plan, today: "2026-09-03")!

        XCTAssertFalse(section.contains("셋째 날"))
        XCTAssertFalse(section.contains("어제 목표"))
    }

    /// 마지막 섹션이면 파일 끝까지.
    func testLastSectionRunsToEndOfFile() {
        let section = ExperimentPlanText.todaySection(in: plan, today: "2026-09-04")!

        XCTAssertTrue(section.contains("내일 목표"))
        XCTAssertTrue(section.hasSuffix("**목표**: 내일 목표"))
    }

    func testMissingDateReturnsNil() {
        XCTAssertNil(ExperimentPlanText.todaySection(in: plan, today: "2026-12-25"))
    }

    /// **`## Day` 머리말이 없으면 파일 첫 줄부터 잘라 온다.**
    ///
    /// 이전 구현과 같은 동작이다. 위로 올라가며 머리말을 찾다가 못 찾으면 0번 줄에서
    /// 멈추기 때문이다. 계획 파일 형식이 깨졌을 때 빈 프롬프트를 보내느니 앞부분이라도
    /// 보내는 편이 낫다고 보고 그대로 두었다.
    func testSectionWithoutDayHeadingStartsFromTop() {
        let broken = "머리말\n> 날짜: 2026-09-03\n**목표**: 오늘"

        let section = ExperimentPlanText.todaySection(in: broken, today: "2026-09-03")

        XCTAssertEqual(section, broken)
    }

    func testContainsPlanMatchesByFileNameWithoutReadingContent() {
        var didRead = false
        let matched = ExperimentPlanText.containsPlan(
            for: "2026-09-03",
            fileName: "2026-09-03_experiment_plan_5d.md",
            content: { didRead = true; return nil }()
        )

        XCTAssertTrue(matched)
        XCTAssertFalse(didRead, "이름으로 맞으면 파일을 읽지 않는다")
    }

    func testContainsPlanFallsBackToContent() {
        XCTAssertTrue(
            ExperimentPlanText.containsPlan(for: "2026-09-03", fileName: "old_experiment_plan_5d.md", content: plan)
        )
        XCTAssertFalse(
            ExperimentPlanText.containsPlan(for: "2026-12-25", fileName: "old_experiment_plan_5d.md", content: plan)
        )
    }

    // MARK: - 작업 폴더

    /// 아이디어·출력이 같은 부모 아래면 그 부모에서 시작한다. Agent 가 양쪽을 다 볼 수 있게.
    func testWorkspaceIsSharedParentWhenSiblings() {
        XCTAssertEqual(
            ExperimentPlanText.workspaceDirectory(
                ideaDirectoryPath: "/a/agent/idea",
                outputDirectoryPath: "/a/agent/output"
            ),
            "/a/agent"
        )
    }

    func testWorkspaceFallsBackToIdeaWhenUnrelated() {
        XCTAssertEqual(
            ExperimentPlanText.workspaceDirectory(
                ideaDirectoryPath: "/a/idea",
                outputDirectoryPath: "/b/output"
            ),
            "/a/idea"
        )
    }

    // MARK: - 뿌리 경로 되살리기

    /// 한 번도 정한 적 없고 옛 설정 둘이 같으면 그것이 뿌리다.
    func testResolveMigratesSharedLegacyDirectory() {
        XCTAssertEqual(
            AgentRootPath.resolve(
                stored: nil, legacyIdeaDirectory: "/old", legacyOutputDirectory: "/old", fallback: "/fallback"
            ),
            "/old"
        )
    }

    /// 다르면 출력 쪽을 택한다 — 계획 파일이 쌓여 있어 잃으면 곤란하다.
    func testResolvePrefersLegacyOutputWhenDifferent() {
        XCTAssertEqual(
            AgentRootPath.resolve(
                stored: nil, legacyIdeaDirectory: "/idea", legacyOutputDirectory: "/output", fallback: "/fallback"
            ),
            "/output"
        )
    }

    func testResolveUsesLegacyIdeaWhenOutputMissing() {
        XCTAssertEqual(
            AgentRootPath.resolve(
                stored: nil, legacyIdeaDirectory: "/idea", legacyOutputDirectory: "  ", fallback: "/fallback"
            ),
            "/idea"
        )
    }

    func testResolveFallsBackWhenNothingToMigrate() {
        XCTAssertEqual(
            AgentRootPath.resolve(
                stored: nil, legacyIdeaDirectory: "", legacyOutputDirectory: "", fallback: "/fallback"
            ),
            "/fallback"
        )
    }

    /// **이미 정한 값이 있으면 옛 설정을 되살리지 않는다.** 사용자가 고른 것을 덮으면 안 된다.
    func testResolveKeepsStoredValueOverLegacy() {
        XCTAssertEqual(
            AgentRootPath.resolve(
                stored: "/chosen", legacyIdeaDirectory: "/old", legacyOutputDirectory: "/old", fallback: "/fallback"
            ),
            "/chosen"
        )
    }

    /// 정하긴 했는데 비워 뒀으면 기본값으로. 옛 설정으로 돌아가지는 않는다.
    func testResolveBlankStoredUsesFallbackNotLegacy() {
        XCTAssertEqual(
            AgentRootPath.resolve(
                stored: "   ", legacyIdeaDirectory: "/old", legacyOutputDirectory: "/old", fallback: "/fallback"
            ),
            "/fallback"
        )
    }

    // MARK: - 프롬프트

    func testPlanPromptListsEveryDay() {
        let now = DateComponents(calendar: .current, year: 2026, month: 9, day: 3).date!
        let prompt = AgentPrompt.plan(
            ideaDirectoryPath: "/idea",
            outputFilePath: "/out/plan.md",
            interestKeywords: "자동화, 회고",
            agent: .claude,
            dayCount: 3,
            now: now
        )

        XCTAssertTrue(prompt.contains("- 2026-09-03 (Thu)"))
        XCTAssertTrue(prompt.contains("- 2026-09-04 (Fri)"))
        XCTAssertTrue(prompt.contains("- 2026-09-05 (Sat)"))
        XCTAssertFalse(prompt.contains("- 2026-09-06"), "요청한 일수만큼만 나열한다")
        XCTAssertTrue(prompt.contains("# 3일 실험 계획"))
        XCTAssertTrue(prompt.contains("관심사 키워드: 자동화, 회고"))
        XCTAssertTrue(prompt.contains("Agent: Claude"))
        XCTAssertTrue(prompt.contains("출력 파일 경로: /out/plan.md"))
    }

    func testTodayPromptCarriesSection() {
        let prompt = AgentPrompt.todayExperiment(
            interestKeywords: "회고",
            today: "2026-09-03",
            todaySection: "## Day 2\n**목표**: 오늘 목표"
        )

        XCTAssertTrue(prompt.contains("오늘 날짜: 2026-09-03"))
        XCTAssertTrue(prompt.contains("**목표**: 오늘 목표"))
    }

    // MARK: - 셸 인용

    /// 프롬프트에 사용자가 쓴 문장이 그대로 들어간다. 작은따옴표가 새면 명령이 깨진다.
    func testShellQuoteEscapesSingleQuote() {
        XCTAssertEqual(CLIAgentAdapter.shellQuote("don't"), "'don'\"'\"'t'")
        XCTAssertEqual(CLIAgentAdapter.shellQuote("plain"), "'plain'")
    }

    func testEveryAgentHasACommand() {
        for agent in AgentKind.allCases {
            let command = CLIAgentAdapter.command(for: agent, prompt: "hi")
            XCTAssertFalse(command.isEmpty)
            XCTAssertTrue(command.contains("'hi'"), "\(agent.rawValue) 가 프롬프트를 안 넘긴다")
        }
    }
}
