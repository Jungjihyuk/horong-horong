import HorongAI
import XCTest
@testable import 호롱호롱

/// 골든셋을 **실모델로** 돌려 결과를 JSONL 로 뱉는 생성기.
///
/// 여기서 나오는 점수는 **품질 참고값**이지 회귀 판정 기준이 아니다. 모델이 비결정적이라
/// 코드를 한 줄도 안 바꿔도 매번 다르게 나온다(실측 `0.3810` → `0.2333`).
/// 회귀 판정은 고정 응답으로 도는 `HorongAITests/GoldenSetHarnessTests` 가 담당한다.
/// → `Bug/incident-20260813-nondeterministic-model-breaks-regression-check.md`
///
/// 케이스 로딩·id 매핑은 `HorongAITestSupport.GoldenSet` 이 한다. 패키지 테스트와 **같은 것**을
/// 써야 두 결과를 나란히 놓을 수 있다.
///
/// 실행:
///   touch Evals/.run-golden && make app-test
final class GoalSuggestionEvalTests: XCTestCase {

    func testGenerateGoldenSetResults() async throws {
        let repositoryRoot = try XCTUnwrap(GoldenSet.repositoryRoot(), "저장소 루트를 찾지 못했습니다.")

        // 환경변수는 xcodebuild 가 테스트 프로세스로 전달하지 않으므로 마커 파일로 켠다.
        let marker = repositoryRoot.appendingPathComponent("Evals/.run-golden")
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: marker.path),
            "Evals/.run-golden 없음 — 골든셋 실행을 건너뜁니다. (추론이 느려 기본 테스트에서는 제외)"
        )

        let goldenCases = try GoldenSet.load(repositoryRoot: repositoryRoot)
        XCTAssertFalse(goldenCases.isEmpty, "골든셋 케이스가 없습니다.")

        let outputDirectory = repositoryRoot.appendingPathComponent("Evals/results", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let outputFile = outputDirectory.appendingPathComponent("\(stamp).jsonl")
        let runner = EvalRunner(outputURL: outputFile)

        for goldenCase in goldenCases {
            await run(goldenCase, runner: runner)
        }

        // 비동기 기록이 전부 파일에 닿은 뒤에 런을 마친다. 없으면 마지막 결과가 유실될 수 있다.
        runner.flush()

        print("[eval] \(goldenCases.count)개 케이스 → \(outputFile.path)")
    }

    // MARK: - 한 케이스 실행

    private func run(_ goldenCase: GoldenSet.Case, runner: EvalRunner) async {
        let shortIDByUUID = goldenCase.identifiers.shortIDByUUID
        let snapshots = goldenCase.memos.map { memo in
            AchievementMemoSnapshot(
                id: GoldenSet.deterministicUUID(for: memo.id),
                content: memo.content,
                icon: memo.icon,
                date: GoldenSet.date(memo.date) ?? Date(),
                startDate: GoldenSet.date(memo.startDate),
                deadline: GoldenSet.date(memo.deadline),
                isCompleted: false
            )
        }

        // EVAL_PROVIDER=mlx 로 공급자를 바꿔 같은 골든셋을 두 모델에 돌린다.
        // 주의: 앱과 같은 도메인을 쓰므로 이 값은 **실제 사용자 설정을 덮어쓴다.**
        let requested = ProcessInfo.processInfo.environment["EVAL_PROVIDER"]
            ?? (GoldenSet.repositoryRoot()?.appendingPathComponent("Evals/.provider"))
                .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? Constants.defaultAchievementSuggestionProvider
        UserDefaults.standard.set(requested, forKey: Constants.AppStorageKey.achievementSuggestionProvider)

        let startTime = Date()
        let suggestions = await AchievementFoundationGoalSuggestionProvider.suggestions(
            from: snapshots,
            suggestionCount: Constants.defaultAchievementSuggestionCount,
            maxMemoCount: Constants.defaultAchievementSuggestionMaxTodoCount
        )
        let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)

        let predicted = suggestions.map { suggestion in
            suggestion.memoIDs.compactMap { shortIDByUUID[$0] }
        }

        let f1Score = PairEvaluator.score(
            expectedGroups: goldenCase.expectedGroups,
            predictedGroups: predicted,
            shouldNotGroup: goldenCase.shouldNotGroup ?? []
        ).f1

        let outputText = suggestions.map { "- \($0.title)" }.joined(separator: "\n")

        runner.record(
            EvalResult(
                caseId: goldenCase.caseName,
                input: goldenCase.note,
                level: "L0", // 문맥 주입이 없는 순수 프롬프팅
                model: requested,
                output: outputText,
                scores: [
                    "pairF1": f1Score,
                    "honorific": DeterministicCheckers.checkHonorific(outputText),
                    "sentenceCount": DeterministicCheckers.checkSentenceCount(outputText, maxCount: 3),
                ],
                latencyMs: latencyMs
            )
        )
    }
}
