import HorongAITestSupport
import XCTest
@testable import HorongAI

/// 골든셋을 **고정 응답으로** 끝까지 돌린다 — 앱 타깃을 빌드하지 않고.
///
/// 실모델 점수로는 회귀를 판정할 수 없다. 코드를 한 줄도 안 바꾸고 두 번 돌렸더니
/// 평균이 `0.3810` → `0.2333` 으로 흔들렸다
/// (→ `Bug/incident-20260813-nondeterministic-model-breaks-regression-check.md`).
/// 모델 층을 고정하면 점수가 바뀌는 이유가 **코드밖에** 남지 않는다.
///
/// 여기서 재는 것은 모델 품질이 아니라 **파이프라인**이다 —
/// 입력 고르기 → 프롬프트 → 파싱 → id 매핑 → 채점이 제대로 이어져 있는가.
final class GoldenSetHarnessTests: XCTestCase {

    /// 앱이 정하는 값이라 태스크가 모른다. 제품과 같은 프롬프트를 만들려면 같은 값을 넣어야 한다.
    private let defaultIcon = "📝"

    private func goldenCases() throws -> [GoldenSet.Case] {
        guard let goldenDirectory = TestRepository.goldenDirectory() else {
            throw XCTSkip("골든셋 폴더를 찾지 못했다")
        }
        let cases = try GoldenSet.load(goldenDirectory: goldenDirectory)
        try XCTSkipIf(cases.isEmpty, "골든셋 케이스가 없다")
        return cases
    }

    private func monthlyGoldenCases() throws -> [GoldenSet.MonthlyCase] {
        guard let goldenDirectory = TestRepository.goldenDirectory() else {
            throw XCTSkip("골든셋 폴더를 찾지 못했다")
        }
        let cases = try GoldenSet.loadMonthly(goldenDirectory: goldenDirectory)
        try XCTSkipIf(cases.isEmpty, "월간 골든셋 케이스가 없다")
        return cases
    }

    /// 정답 묶음을 그대로 뱉는 "완벽한 모델" 의 응답을 만든다.
    private func perfectResponse(for goldenCase: GoldenSet.Case) -> String {
        let uuidByShortID = goldenCase.identifiers.uuidByShortID
        let items = goldenCase.expectedMemoGroups(of: .weekly).map { group -> String in
            let ids = group
                .compactMap { uuidByShortID[$0] }
                .map { "\"\($0.uuidString)\"" }
                .joined(separator: ", ")
            return """
            {"title": "묶음", "reason": "같은 결과로 이어진다", "memoIDs": [\(ids)],
             "scheduleText": "이번 주에 나눠 진행", "criterion": "연결한 할일 완료", "emoji": "🎯"}
            """
        }
        return "{\"suggestions\": [\(items.joined(separator: ", "))]}"
    }

    private func score(
        _ goldenCase: GoldenSet.Case,
        response: String
    ) async -> PairEvaluator.Score {
        let shortIDByUUID = goldenCase.identifiers.shortIDByUUID
        let generator = ReplayTextGenerator(response)

        let outcome = await WeeklyGoalTask.run(
            memos: goldenCase.taskMemos(defaultIcon: defaultIcon),
            suggestionCount: 4,
            maxMemoCount: 5,
            inputLimit: 60,
            budget: 16_000,
            generate: { prompt, instructions in
                try await generator.generate(prompt: prompt, instructions: instructions)
            }
        )

        let predicted = outcome.drafts.map { draft in
            draft.memoIDs.compactMap { shortIDByUUID[$0] }
        }
        return PairEvaluator.score(
            expectedGroups: goldenCase.expectedMemoGroups(of: .weekly),
            predictedGroups: predicted,
            traps: goldenCase.traps ?? []
        )
    }

    // MARK: - 파이프라인이 이어져 있는가

    /// 정답을 그대로 뱉으면 모든 케이스가 만점이어야 한다.
    ///
    /// 만점이 안 나오면 모델이 아니라 **우리 코드** 어딘가가 끊긴 것이다 —
    /// id 매핑, 파서의 방어 갈래, 채점 중 하나다.
    func testPerfectAnswerScoresFullMarksOnEveryCase() async throws {
        for goldenCase in try goldenCases() {
            let score = await score(goldenCase, response: perfectResponse(for: goldenCase))
            XCTAssertEqual(
                score.f1, 1.0, accuracy: 0.0001,
                "\(goldenCase.caseName): 정답을 그대로 넣었는데 만점이 아니다"
            )
            XCTAssertEqual(score.violations, 0, goldenCase.caseName)
        }
    }

    /// 월간 골든셋도 주간과 같은 «고정 응답 → 태스크 → id 매핑» 경로를 탄다.
    /// 이 검사가 없으면 `monthly` 파일은 있어도 평가에는 조용히 포함되지 않는다.
    func testPerfectMonthlyAnswerScoresFullMarksOnEveryCase() async throws {
        for goldenCase in try monthlyGoldenCases() {
            let uuidByShortID = goldenCase.identifiers.uuidByShortID
            let items = goldenCase.expectedGoalGroups().map { group in
                let ids = group.compactMap { uuidByShortID[$0] }
                    .map { "\"\($0.uuidString)\"" }
                    .joined(separator: ", ")
                return "{\"title\": \"묶음\", \"reason\": \"같은 결과로 이어진다\", \"goalIDs\": [\(ids)]}"
            }
            let response = "{\"suggestions\": [\(items.joined(separator: ", "))]}"
            let generator = ReplayTextGenerator(response)
            let outcome = await MonthlyGoalTask.run(
                goals: goldenCase.taskGoals(),
                suggestionCount: 4,
                inputLimit: 60,
                context: goldenCase.context?.taskContext ?? .empty,
                generate: { prompt, instructions in
                    try await generator.generate(prompt: prompt, instructions: instructions)
                }
            )
            let predicted = outcome.drafts.map { draft in
                draft.childGoalIDs.compactMap { goldenCase.identifiers.shortIDByUUID[$0] }
            }
            let score = PairEvaluator.score(
                expectedGroups: goldenCase.expectedGoalGroups(),
                predictedGroups: predicted,
                traps: goldenCase.traps ?? []
            )
            XCTAssertEqual(score.f1, 1.0, accuracy: 0.0001, goldenCase.caseName)
        }
    }

    /// 함정을 밟으면 위반으로 잡히고 **최종 점수가 깎여야** 한다.
    /// 채점 방향이 반대면 위반이 0 으로 나온다.
    func testSteppingOnATrapIsCaughtAndPenalized() async throws {
        let cases = try goldenCases()
        guard let target = cases.first(where: { ($0.traps ?? []).contains { !PairEvaluator.pairs(ofTrap: $0).isEmpty } }),
              let trap = (target.traps ?? []).first(where: { !PairEvaluator.pairs(ofTrap: $0).isEmpty }),
              // 함정 쌍 하나를 골라 그 둘을 억지로 한 묶음에 넣는다.
              let pair = PairEvaluator.pairs(ofTrap: trap).sorted().first else {
            throw XCTSkip("함정이 있는 케이스가 없다")
        }

        let uuidByShortID = target.identifiers.uuidByShortID
        let ids = pair.split(separator: "|").compactMap { uuidByShortID[String($0)] }
            .map { "\"\($0.uuidString)\"" }.joined(separator: ", ")
        let response = """
        {"suggestions": [{"title": "억지 묶음", "reason": "이유", "memoIDs": [\(ids)],
         "scheduleText": "", "criterion": "", "emoji": "🎯"}]}
        """

        let score = await score(target, response: response)
        XCTAssertGreaterThan(score.violations, 0, "\(target.caseName): 함정을 밟았는데 위반이 0 이다")
        XCTAssertLessThan(
            score.groupingScore, score.f1 + 1e-9,
            "\(target.caseName): 함정을 밟았는데 최종 점수가 안 깎였다"
        )
    }

    /// 같은 입력·같은 응답이면 점수가 **정확히** 같아야 한다. 이게 회귀 판정의 전제다.
    func testSameInputProducesIdenticalScore() async throws {
        let goldenCase = try XCTUnwrap(try goldenCases().first)
        let response = perfectResponse(for: goldenCase)

        let first = await score(goldenCase, response: response)
        let second = await score(goldenCase, response: response)

        XCTAssertEqual(first.f1, second.f1)
        XCTAssertEqual(first.predictedPairs, second.predictedPairs)
    }

    // MARK: - 실패 경로

    /// 생성이 실패하면 후보 없이 진단만 남는다. 호출부는 이걸 보고 다음 공급자로 내려간다.
    func testGenerationFailureYieldsNoDraftsAndIsReported() async throws {
        let generator = ReplayTextGenerator(failingWith: ReplayGenerationFailure(reason: "서버 없음"))

        let outcome = await WeeklyGoalTask.run(
            memos: [
                WeeklyGoalTask.Memo(id: UUID(), content: "보고서 초안", icon: "📝", date: Date()),
                WeeklyGoalTask.Memo(id: UUID(), content: "보고서 검토", icon: "📝", date: Date()),
            ],
            suggestionCount: 3,
            maxMemoCount: 3,
            inputLimit: 60,
            budget: 16_000,
            generate: { prompt, instructions in
                try await generator.generate(prompt: prompt, instructions: instructions)
            }
        )

        XCTAssertTrue(outcome.drafts.isEmpty)
        guard case .generationFailed(let error) = outcome.diagnostics else {
            return XCTFail("생성 실패가 진단에 안 남았다")
        }
        // 에러를 문자열이 아니라 그대로 돌려줘야 앱이 릴리스에서 타입 이름만 남길 수 있다.
        XCTAssertEqual(error as? ReplayGenerationFailure, ReplayGenerationFailure(reason: "서버 없음"))
    }

    /// 모델에게 나간 프롬프트에 지시문과 할일이 실제로 실렸는지.
    func testPromptAndInstructionsReachTheGenerator() async throws {
        let generator = ReplayTextGenerator("{\"suggestions\": []}")

        _ = await WeeklyGoalTask.run(
            memos: [
                WeeklyGoalTask.Memo(id: UUID(), content: "주간 보고서 초안", icon: "📝", date: Date()),
            ],
            suggestionCount: 3,
            maxMemoCount: 3,
            inputLimit: 60,
            budget: 16_000,
            generate: { prompt, instructions in
                try await generator.generate(prompt: prompt, instructions: instructions)
            }
        )

        let sent = try XCTUnwrap(generator.received.first)
        XCTAssertEqual(sent.instructions, WeeklyGoalTask.instructions)
        XCTAssertTrue(sent.prompt.contains("주간 보고서 초안"))
        XCTAssertTrue(sent.prompt.contains("[가장 중요한 묶는 기준]"), ".md 가 아니라 폴백이 쓰였다")
    }
}
