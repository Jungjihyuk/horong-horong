import HorongAI
import XCTest
@testable import 호롱호롱

/// 골든셋을 실모델로 돌려 결과를 JSONL 로 남긴다.
/// 고정 응답 회귀 판정은 `HorongAITests/GoldenSetHarnessTests`가 담당한다.
final class GoalSuggestionEvalTests: XCTestCase {
    private struct EvaluationConfiguration: Decodable {
        let provider: String
        let model: String?
        let contextModes: [String]?
    }

    private struct ContextVariant {
        let recipe: String
        let context: GoalRecommendationContext
    }

    func testNoSuggestionCorrectAcceptsSilenceOrCompleteGuidance() {
        let expected = Set(["m1", "m2", "m3", "m4", "m5"])

        XCTAssertEqual(noSuggestionCorrectScore(
            result: .noSuggestion,
            expectedGuidance: expected,
            actualGuidance: []
        ), 1)
        XCTAssertEqual(noSuggestionCorrectScore(
            result: .guidance([]),
            expectedGuidance: expected,
            actualGuidance: expected
        ), 1)
        XCTAssertEqual(noSuggestionCorrectScore(
            result: .guidance([]),
            expectedGuidance: expected,
            actualGuidance: Set(["m1", "m2", "m3", "m4"])
        ), 0)
        XCTAssertEqual(noSuggestionCorrectScore(
            result: .suggestions([]),
            expectedGuidance: expected,
            actualGuidance: expected
        ), 0)
    }

    func testGenerateGoldenSetResults() async throws {
        let repositoryRoot = try XCTUnwrap(GoldenSet.repositoryRoot(), "저장소 루트를 찾지 못했습니다.")
        let marker = repositoryRoot.appendingPathComponent("Evals/.run-golden")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: marker.path), "Evals/.run-golden 없음 — 골든셋 실행을 건너뜁니다. (추론이 느려 기본 테스트에서는 제외)")

        let weeklyCases = try GoldenSet.load(repositoryRoot: repositoryRoot)
        let monthlyCases = try GoldenSet.loadMonthly(repositoryRoot: repositoryRoot)
        XCTAssertFalse(weeklyCases.isEmpty, "주간 골든셋 케이스가 없습니다.")
        XCTAssertFalse(monthlyCases.isEmpty, "월간 골든셋 케이스가 없습니다.")

        let outputDirectory = repositoryRoot.appendingPathComponent("Evals/results", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        // 파일명만 보고도 한국 시간 기준 실행 시각을 알 수 있게 UTC(`Z`) 대신 KST 오프셋을 남긴다.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ssZ"
        let stamp = formatter.string(from: Date())
        let outputFile = outputDirectory.appendingPathComponent("\(stamp).jsonl")
        let runner = RunLogger(
            outputURL: outputFile,
            timestampStyle: .koreaStandardTime
        )
        // 접두사를 여기서 또 적으면 앱의 판별(`AIRunLog.isGoldenRun`)과 조용히 어긋난다.
        let runID = "\(AIRunLog.goldenRunIDPrefix)\(stamp)"
        let configuration = evaluationConfiguration(repositoryRoot: repositoryRoot)
        let provider = selectedProvider(configuration: configuration, repositoryRoot: repositoryRoot)
        let model = configuration?.model ?? selectedModel(for: provider)

        // 원문 기록기를 켠다. 지금까지는 앱 시작 경로(`AIRunLog.installTraceRecorder`)에서만
        // 설치돼, 정작 원문이 필요한 골든셋 실행이 `trace: nil` 로 돌았다. 그래서 `noSuggestion`
        // 이 «모델이 안 냈다» 인지 «파서가 버렸다» 인지 가릴 수가 없었다(2026-08-25).
        //
        // 골든셋 입력은 저장소에 든 합성 데이터라 원문을 남겨도 사용자 정보가 새지 않는다.
        TraceRecorder.shared = TraceRecorder(
            directory: outputDirectory.appendingPathComponent("traces", isDirectory: true),
            isEnabled: true
        )
        // 쓰기가 큐에 실려 나가므로 테스트가 먼저 끝나면 마지막 케이스의 원문이 사라진다.
        defer {
            TraceRecorder.shared?.flush()
            TraceRecorder.shared = nil
        }

        // 생성 상한을 평가용으로 올린다. 제품 값(180초)을 그대로 쓰면 느린 머신에서
        // **«모델이 틀렸다» 와 «머신이 느렸다» 가 똑같이 0점으로 남는다.**
        let productTimeout = Constants.achievementSuggestionTimeout
        Constants.achievementSuggestionTimeout = Constants.achievementSuggestionEvalTimeout
        defer { Constants.achievementSuggestionTimeout = productTimeout }

        // 케이스마다 다른 `runId` 를 준다. **원문 파일 하나가 시도 하나**인데
        // (→ `TraceRecorder.fileURL`) 배치 전체가 한 `runId` 를 쓰면 케이스들이 같은 파일을
        // 덮어써 마지막 하나만 남는다. 배치 id 를 접두사로 두어 이름만으로 다시 묶인다.
        var caseNumber = 0
        for goldenCase in weeklyCases {
            for variant in contextVariants(for: goldenCase.context, configuration: configuration) {
                caseNumber += 1
                await run(goldenCase, provider: provider, model: model, variant: variant, runner: runner, runID: "\(runID)-w\(caseNumber)")
            }
        }
        caseNumber = 0
        for goldenCase in monthlyCases {
            for variant in contextVariants(for: goldenCase.context, configuration: configuration) {
                caseNumber += 1
                await run(goldenCase, provider: provider, model: model, variant: variant, runner: runner, runID: "\(runID)-m\(caseNumber)")
            }
        }
        runner.flush()
        print("[eval] 주간 \(weeklyCases.count)개, 월간 \(monthlyCases.count)개 → \(outputFile.path)")
    }

    private func evaluationConfiguration(repositoryRoot: URL) -> EvaluationConfiguration? {
        let file = repositoryRoot.appendingPathComponent("Evals/.goal-eval-configuration.json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(EvaluationConfiguration.self, from: data)
    }

    private func selectedProvider(
        configuration: EvaluationConfiguration?,
        repositoryRoot: URL
    ) -> Constants.AchievementSuggestionProviderKind {
        let requested = configuration?.provider
            ?? ProcessInfo.processInfo.environment["EVAL_PROVIDER"]
            ?? (try? String(contentsOf: repositoryRoot.appendingPathComponent("Evals/.provider"), encoding: .utf8))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? Constants.defaultAchievementSuggestionProvider
        return Constants.AchievementSuggestionProviderKind(rawValue: requested) ?? .appleFoundation
    }

    private func selectedModel(for provider: Constants.AchievementSuggestionProviderKind) -> String {
        switch provider {
        case .ollama:
            UserDefaults.standard.string(forKey: Constants.AppStorageKey.achievementSuggestionOllamaModel)
                ?? Constants.defaultAchievementSuggestionOllamaModel
        case .mlx:
            UserDefaults.standard.string(forKey: Constants.AppStorageKey.achievementSuggestionMLXModel)
                ?? Constants.defaultAchievementSuggestionMLXModel
        case .appleFoundation:
            "Apple Foundation Models"
        }
    }

    private func contextVariants(
        for context: GoldenSet.Context?,
        configuration: EvaluationConfiguration?
    ) -> [ContextVariant] {
        guard let context else {
            return [ContextVariant(recipe: "promptOnly", context: .empty)]
        }
        let modes = configuration?.contextModes ?? ["withContext"]
        let variants = modes.compactMap { mode -> ContextVariant? in
            switch mode {
            case "withoutContext": return ContextVariant(recipe: "promptOnly", context: .empty)
            case "withContext": return ContextVariant(recipe: "promptWithContext", context: context.taskContext)
            default: return nil
            }
        }
        return variants.isEmpty ? [ContextVariant(recipe: "promptWithContext", context: context.taskContext)] : variants
    }

    private func run(_ goldenCase: GoldenSet.Case, provider: Constants.AchievementSuggestionProviderKind, model: String, variant: ContextVariant, runner: RunLogger, runID: String) async {
        let snapshots = goldenCase.memos.map { memo in
            AchievementMemoSnapshot(id: GoldenSet.deterministicUUID(for: memo.id), content: memo.content, icon: memo.icon, date: memo.derivedDate(referenceDate: goldenCase.reference), startDate: GoldenSet.date(memo.startDate), deadline: GoldenSet.date(memo.deadline), isCompleted: false)
        }
        let startedAt = Date()
        let result = await AchievementFoundationGoalSuggestionProvider.suggestions(
            from: snapshots, suggestionCount: Constants.defaultAchievementSuggestionCount,
            maxMemoCount: Constants.defaultAchievementSuggestionMaxTodoCount, runID: runID,
            recommendationContext: variant.context, modelOverride: model, allowFallback: false, provider: provider
        )
        record(caseName: goldenCase.caseName, expectedGroups: goldenCase.expectedMemoGroups(of: .weekly), expectedOutcome: goldenCase.expectedOutcome, expectedInputIDs: goldenCase.identifiers.shortIDByUUID, result: result, task: "weekly_goal", provider: provider.rawValue, model: model, recipe: variant.recipe, startedAt: startedAt, runID: runID, traps: goldenCase.traps ?? [], runner: runner)
    }

    private func run(_ goldenCase: GoldenSet.MonthlyCase, provider: Constants.AchievementSuggestionProviderKind, model: String, variant: ContextVariant, runner: RunLogger, runID: String) async {
        let snapshots = goldenCase.weeklyGoals.map { goal in
            AchievementGoalSnapshot(id: GoldenSet.deterministicUUID(for: goal.id), title: goal.title, emoji: goal.icon ?? "🎯", rule: "", done: 0, total: 0, sourceMemoIDs: [], roleName: goldenCase.context?.persona ?? "", vision: goldenCase.context?.profile?.text ?? "", monthGoal: nil)
        }
        let startedAt = Date()
        let result = await AchievementFoundationGoalSuggestionProvider.monthlySuggestions(
            from: snapshots, suggestionCount: Constants.defaultAchievementMonthlySuggestionCount,
            runID: runID, recommendationContext: variant.context, modelOverride: model, allowFallback: false, provider: provider
        )
        record(caseName: goldenCase.caseName, expectedGroups: goldenCase.expectedGoalGroups(), expectedOutcome: goldenCase.expectedOutcome, expectedInputIDs: goldenCase.identifiers.shortIDByUUID, result: result, task: "monthly_goal", provider: provider.rawValue, model: model, recipe: variant.recipe, startedAt: startedAt, runID: runID, traps: goldenCase.traps ?? [], runner: runner)
    }

    private func record(caseName: String, expectedGroups: [[String]], expectedOutcome: GoldenSet.ExpectedOutcome?, expectedInputIDs: [UUID: String], result: AchievementGoalRecommendationResult, task: String, provider: String, model: String, recipe: String, startedAt: Date, runID: String, traps: [PairEvaluator.Trap], runner: RunLogger) {
        let predictedGroups = result.suggestions.map { suggestion in
            (task == "weekly_goal" ? suggestion.memoIDs : suggestion.childGoalIDs).compactMap { expectedInputIDs[$0] }
        }
        let grouping = PairEvaluator.score(expectedGroups: expectedGroups, predictedGroups: predictedGroups, traps: traps)
        let expectedGuidance = Set(expectedOutcome?.reviewedInputIDs ?? [])
        let actualGuidance = Set(result.guidance.compactMap { expectedInputIDs[$0.inputID] })
        let expectedReviews = (expectedOutcome?.memoReviews ?? []) + (expectedOutcome?.goalReviews ?? [])
        let expectedMissing = Dictionary(uniqueKeysWithValues: expectedReviews.compactMap { review in
            review.inputID.map { ($0, Set(review.missing)) }
        })
        let actualMissing = Dictionary(uniqueKeysWithValues: result.guidance.compactMap { item in
            expectedInputIDs[item.inputID].map { ($0, Set(item.missing)) }
        })
        let expectsNoSuggestion = expectedOutcome?.action == "no_goal_recommendation"
        let output = !result.suggestions.isEmpty
            ? result.suggestions.map { "- \($0.title)" }.joined(separator: "\n")
            : result.guidance.map { "- \($0.suggestion)" }.joined(separator: "\n")
        var scores: [String: Double] = ["pairF1": grouping.f1, "trapAvoidance": grouping.trapAvoidance, "groupingScore": grouping.groupingScore]
        if !expectedGuidance.isEmpty {
            let guidance = setCounts(expected: expectedGuidance, actual: actualGuidance)
            scores["guidanceTP"] = Double(guidance.truePositive)
            scores["guidanceFP"] = Double(guidance.falsePositive)
            scores["guidanceFN"] = Double(guidance.falseNegative)
            scores["guidancePrecision"] = guidance.precision
            scores["guidanceRecall"] = guidance.recall
            scores["guidanceF1"] = guidance.f1

            let expectedMissingPairs = Set(expectedMissing.flatMap { inputID, fields in
                fields.map { "\(inputID)|\($0)" }
            })
            let actualMissingPairs = Set(actualMissing.flatMap { inputID, fields in
                fields.map { "\(inputID)|\($0)" }
            })
            // 찾아낼 결손 항목이 애초에 0개인 케이스가 있다 — `non_goal_or_noise` 는
            // «아무것도 추천하지 마라» 가 정답이라 `missing` 을 적지 않는다. 그런 케이스에
            // 이 지표를 매기면 분모가 0 이고, **«측정 대상이 아님» 이 «0점» 으로 둔갑한다.**
            // 지표를 빼서 리포트가 분모에서 제외하게 둔다(`guidanceF1` 과 같은 규약).
            if !expectedMissingPairs.isEmpty {
                let missing = setCounts(expected: expectedMissingPairs, actual: actualMissingPairs)
                scores["missingTP"] = Double(missing.truePositive)
                scores["missingFP"] = Double(missing.falsePositive)
                scores["missingFN"] = Double(missing.falseNegative)
                scores["missingPrecision"] = missing.precision
                scores["missingRecall"] = missing.recall
                scores["missingF1"] = missing.f1
            }
        }
        if expectsNoSuggestion {
            scores["noSuggestionCorrect"] = noSuggestionCorrectScore(
                result: result,
                expectedGuidance: expectedGuidance,
                actualGuidance: actualGuidance
            )
        }

        runner.record(RunRecord(caseId: caseName, model: model, output: output, scores: scores, totalMs: Int(Date().timeIntervalSince(startedAt) * 1000), runId: runID, startedAt: startedAt, task: task, source: "golden", recipe: recipe, provider: provider, outcome: result.recordedOutcome, outcomeDetail: result.outcomeDetail))
    }

    /// 비목표 입력은 침묵해도, 모든 입력을 빠짐없이 설명해도 정답이다.
    /// 안내 문장의 의미 품질은 결정적 채점이 아니라 별도 LLM judge가 담당한다.
    private func noSuggestionCorrectScore(
        result: AchievementGoalRecommendationResult,
        expectedGuidance: Set<String>,
        actualGuidance: Set<String>
    ) -> Double {
        switch result {
        case .noSuggestion:
            return 1
        case .guidance:
            return !expectedGuidance.isEmpty && actualGuidance == expectedGuidance ? 1 : 0
        case .suggestions, .failure:
            return 0
        }
    }

    private struct SetCounts {
        let truePositive: Int
        let falsePositive: Int
        let falseNegative: Int
        let precision: Double
        let recall: Double
        let f1: Double
    }

    /// 집합 두 개를 TP/FP/FN 으로 세고 P·R·F1 을 낸다.
    ///
    /// **0 으로 나누지 않는다.** `expected` 가 비면 `overlap / 0` 이 `NaN` 이 되고,
    /// `NaN` 은 `== 0` 검사를 빠져나가 `f1` 까지 오염시킨 뒤 `JSONEncoder` 를 던지게 만든다.
    /// 그 줄은 통째로 기록되지 않는다 — 실제로 6행이 그렇게 사라졌다.
    /// 빈 쪽 처리는 `PairEvaluator.score` 의 규약을 그대로 따른다(«찾을 게 없는데
    /// 아무것도 안 냈으면 만점»).
    private func setCounts(expected: Set<String>, actual: Set<String>) -> SetCounts {
        let overlap = Double(expected.intersection(actual).count)
        let precision = actual.isEmpty ? (expected.isEmpty ? 1 : 0) : overlap / Double(actual.count)
        let recall = expected.isEmpty ? (actual.isEmpty ? 1 : 0) : overlap / Double(expected.count)
        let f1 = precision + recall == 0 ? 0 : 2 * precision * recall / (precision + recall)
        return SetCounts(
            truePositive: expected.intersection(actual).count,
            falsePositive: actual.subtracting(expected).count,
            falseNegative: expected.subtracting(actual).count,
            precision: precision,
            recall: recall,
            f1: f1
        )
    }
}
