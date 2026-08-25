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
        let runID = "G-\(stamp)"
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
        let expectsNoSuggestion = expectedOutcome?.action == "no_goal_recommendation"
        let output = !result.suggestions.isEmpty
            ? result.suggestions.map { "- \($0.title)" }.joined(separator: "\n")
            : result.guidance.map { "- \($0.suggestion)" }.joined(separator: "\n")
        var scores: [String: Double] = ["pairF1": grouping.f1, "trapAvoidance": grouping.trapAvoidance, "groupingScore": grouping.groupingScore]
        if !expectedGuidance.isEmpty { scores["guidanceF1"] = setF1(expected: expectedGuidance, actual: actualGuidance) }
        if expectsNoSuggestion { scores["noSuggestionCorrect"] = isNoSuggestion(result) ? 1 : 0 }

        runner.record(RunRecord(caseId: caseName, model: model, output: output, scores: scores, totalMs: Int(Date().timeIntervalSince(startedAt) * 1000), runId: runID, startedAt: startedAt, task: task, source: "golden", recipe: recipe, provider: provider, outcome: result.recordedOutcome, outcomeDetail: result.outcomeDetail))
    }

    private func isNoSuggestion(_ result: AchievementGoalRecommendationResult) -> Bool {
        if case .noSuggestion = result { return true }
        return false
    }

    private func setF1(expected: Set<String>, actual: Set<String>) -> Double {
        let overlap = Double(expected.intersection(actual).count)
        let precision = actual.isEmpty ? 0 : overlap / Double(actual.count)
        let recall = overlap / Double(expected.count)
        return precision + recall == 0 ? 0 : 2 * precision * recall / (precision + recall)
    }
}
