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
        let runner = RunLogger(outputURL: outputFile)
        // 스위트 한 바퀴가 실행 하나다. 케이스 6개가 같은 runID 를 달고 나간다 —
        // "언제 돌렸나"(runID)와 "어떤 문제를 풀었나"(caseID)는 층이 다르다.
        let runID = "G-\(stamp)"

        for goldenCase in goldenCases {
            await run(goldenCase, runner: runner, runID: runID)
        }

        // 비동기 기록이 전부 파일에 닿은 뒤에 런을 마친다. 없으면 마지막 결과가 유실될 수 있다.
        runner.flush()

        print("[eval] \(goldenCases.count)개 케이스 → \(outputFile.path)")
    }

    // MARK: - 한 케이스 실행

    private func run(_ goldenCase: GoldenSet.Case, runner: RunLogger, runID: String) async {
        let shortIDByUUID = goldenCase.identifiers.shortIDByUUID
        let snapshots = goldenCase.memos.map { memo in
            AchievementMemoSnapshot(
                id: GoldenSet.deterministicUUID(for: memo.id),
                content: memo.content,
                icon: memo.icon,
                date: memo.derivedDate(referenceDate: goldenCase.reference),
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
        // 공급자는 인자로 넘긴다. 안쪽에서 읽던 시절에는 이 한 줄이 곧 선택이었지만,
        // 지금은 실행당 한 번만 읽는 값을 부르는 쪽이 정한다. 이 줄은 **모델 이름 같은
        // 나머지 설정**을 안쪽이 같은 공급자 기준으로 읽게 맞춰 두는 용도로 남긴다.
        UserDefaults.standard.set(requested, forKey: Constants.AppStorageKey.achievementSuggestionProvider)
        let provider = Constants.AchievementSuggestionProviderKind(rawValue: requested) ?? .appleFoundation

        let startTime = Date()
        let result = await AchievementFoundationGoalSuggestionProvider.suggestions(
            from: snapshots,
            suggestionCount: Constants.defaultAchievementSuggestionCount,
            maxMemoCount: Constants.defaultAchievementSuggestionMaxTodoCount,
            provider: provider
        )
        let suggestions = result.suggestions
        let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)

        let predicted = suggestions.map { suggestion in
            suggestion.memoIDs.compactMap { shortIDByUUID[$0] }
        }

        let score = PairEvaluator.score(
            expectedGroups: goldenCase.expectedMemoGroups(of: .weekly),
            predictedGroups: predicted,
            traps: goldenCase.traps ?? []
        )

        let outputText = suggestions.map { "- \($0.title)" }.joined(separator: "\n")

        runner.record(
            RunRecord(
                caseId: goldenCase.caseName,
                model: requested,
                output: outputText,
                // 목표 추천에 맞는 자는 `pairF1` 하나뿐이다.
                //
                // `honorific`·`sentenceCount` 는 **대화용 자**라 뗐다(2026-08-19). 출력이 명사구
                // 제목이라 존댓말로 끝날 이유가 없어 전 케이스 0.00 이 나왔는데, 그 0 이 셋을 망쳤다.
                // - 열 평균을 끌어내린다 (`eval-report.py` 의 `column_summary` 가 전 점수를 평균낸다)
                // - **모든 케이스를 '주의'로 칠한다** (`is_warning` — 0.5 미만이 하나라도 있으면 주의)
                // - 모든 칸을 최저 등급으로 칠한다 (`worst_class` 가 최솟값을 본다)
                //
                // 자가 틀린 게 아니라 **붙일 곳이 틀렸다.** 두 함수는 `DeterministicCheckers` 에
                // 그대로 있고, 컴패니언 스위트가 생기면 거기 붙인다.
                scores: [
                    // 순수 F1. **함정 감점 전** 값이라 옛 기록과 그대로 비교된다.
                    "pairF1": score.f1,
                    // 함정을 얼마나 피했나. 함정을 안 적은 케이스는 1.0.
                    "trapAvoidance": score.trapAvoidance,
                    // **묶음 일치도** — 최종 점수. F1 × 함정 회피.
                    "groupingScore": score.groupingScore,
                ],
                totalMs: latencyMs,
                runId: runID,
                startedAt: startTime,
                task: "weekly_goal",
                source: "golden",
                recipe: "promptOnly", // 문맥 주입이 없는 순수 프롬프팅
                provider: requested
            )
        )
    }
}
