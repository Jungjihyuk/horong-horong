import AppKit
import HorongAI
import HorongAIMLX
import OSLog
import SwiftUI
import UniformTypeIdentifiers
#if canImport(FoundationModels)
import FoundationModels
#endif

/*
 Apple Foundation Models 를 쓰는 추천 공급자.
 
  통째로 `#if canImport(FoundationModels)` 안에 있다 — 그 프레임워크가 없는 환경에서도
  빌드되어야 한다.

 원래 `AchievementViews.swift`(9,854줄) 한 파일에 있었다. 2026-09-03 분할.
 */

#if canImport(FoundationModels)
@available(macOS 26.0, *)
struct FoundationModelsGoalSuggestionProvider {
    func suggestions(
        from memos: [AchievementMemoSnapshot],
        suggestionCount: Int,
        maxMemoCount: Int,
        context: RunContext,
        recommendationContext: GoalRecommendationContext
    ) async -> AchievementGoalRecommendationResult {
        let startedAt = Date()
        let generator = AppleFoundationModelsTextGenerator()
        guard generator.isAvailable else {
            achievementSuggestionLog.error(
                "weekly model failure=\(AchievementSuggestionModelFailure.modelUnavailable.rawValue, privacy: .public)"
            )
            AIRunLog.record(
                context.record(
                    startedAt: startedAt,
                    provider: "appleFoundation",
                    model: nil,
                    outcome: "modelUnavailable"
                )
            )
        return .failure(reason: nil)
        }

        // 추론이 거부되면 그 자리를 다시 남긴다. 로그 문구는 인시던트 2026-07-31 의 진단 서명이라 유지한다.
        var promptSummary = ""
        let trace = TraceRecorder.shared?.makeCollector(
            runId: context.runID,
            task: context.task,
            provider: "appleFoundation",
            attempt: context.attemptNumber
        )
        let outcome = await WeeklyGoalTask.run(
            memos: memos.map(\.taskMemo),
            suggestionCount: suggestionCount,
            maxMemoCount: maxMemoCount,
            // 개수만으로 자르면 메모가 길 때 프롬프트가 커져 추론이 통째로 거부된다.
            // (측정: 3,424자는 통과, 5,203자는 실패 — 에러는 unsupportedLanguageOrLocale로 오분류되어 나온다)
            inputLimit: max(8, min(15, suggestionCount * maxMemoCount * 2)),
            budget: achievementPromptCharacterBudget,
            context: recommendationContext,
            timeoutInterval: Constants.achievementSuggestionTimeout,
            onPromptBuilt: { characters, memoCount in
                promptSummary = "weekly prompt chars=\(characters) memos=\(memoCount)"
                achievementSuggestionLog.info(
                    "weekly prompt chars=\(characters, privacy: .public) memos=\(memoCount, privacy: .public)"
                )
            },
            trace: trace,
            generate: { prompt, instructions in
                try await generator.generate(
                    prompt: prompt,
                    instructions: instructions,
                    temperature: 0.2,
                    maxTokens: 900
                )
            }
        )
        if let trace { TraceRecorder.shared?.record(trace) }

        switch outcome.diagnostics {
        case .parsed(let diagnostics):
            AchievementFoundationGoalSuggestionProvider.logWeeklyParse(diagnostics)
            if outcome.drafts.isEmpty {
                achievementSuggestionLog.error(
                    "weekly model failure=\(AchievementSuggestionModelFailure.parsedEmpty.rawValue, privacy: .public)"
                )
            }
        case .generationFailed(let error):
            achievementSuggestionLog.error(
                """
                weekly model failure=\(AchievementSuggestionModelFailure.inferenceFailed.rawValue, privacy: .public) \
                error=\(achievementModelErrorDescription(error), privacy: .public)
                """
            )
            achievementSuggestionLog.error("\(promptSummary, privacy: .public)")
        }

        let suggestions = outcome.drafts.map { $0.suggestion(cadence: .weekly, runID: context.runID) }
        AIRunLog.record(
            context.record(
                startedAt: startedAt,
                provider: "appleFoundation",
                model: nil,
                outcome: AchievementGoalRecommendationResult.from(
                    outcome.result, cadence: .weekly, source: .foundationModel, runID: context.runID
                ).recordedOutcome,
                outcomeDetail: outcome.diagnostics.outcomeDetail,
                titles: suggestions.map(\.title),
                selectedIDs: outcome.selectedIDs,
                promptCharacters: outcome.promptCharacters,
                parse: outcome.diagnostics.parseSummary,
                usage: outcome.usage,
                timings: outcome.timings,
                parameters: ["temperature": 0.2, "max_tokens": 900, "max_items_per_goal": Double(maxMemoCount)]
            )
        )
        return AchievementGoalRecommendationResult.from(
            outcome.result,
            cadence: .weekly,
            source: .foundationModel,
            runID: context.runID
        )
    }

    func monthlySuggestions(
        from goals: [AchievementGoalSnapshot],
        suggestionCount: Int,
        maxGoalsPerSuggestion: Int = MonthlyGoalTask.maxGoalsPerSuggestion,
        context: RunContext,
        recommendationContext: GoalRecommendationContext
    ) async -> AchievementGoalRecommendationResult {
        let startedAt = Date()
        let generator = AppleFoundationModelsTextGenerator()
        guard generator.isAvailable else {
            achievementSuggestionLog.error(
                "monthly model failure=\(AchievementSuggestionModelFailure.modelUnavailable.rawValue, privacy: .public)"
            )
            AIRunLog.record(
                context.record(
                    startedAt: startedAt,
                    provider: "appleFoundation",
                    model: nil,
                    outcome: "modelUnavailable",
                    parameters: ["temperature": 0.25, "max_tokens": Double(achievementMonthlyMaxTokens),
                     "max_items_per_goal": Double(maxGoalsPerSuggestion)]
                )
            )
        return .failure(reason: nil)
        }

        let trace = TraceRecorder.shared?.makeCollector(
            runId: context.runID,
            task: context.task,
            provider: "appleFoundation",
            attempt: context.attemptNumber
        )
        let outcome = await MonthlyGoalTask.run(
            goals: goals.map(\.taskGoal),
            suggestionCount: suggestionCount,
            inputLimit: max(3, min(30, suggestionCount * 6)),
            maxGoalsPerSuggestion: maxGoalsPerSuggestion,
            context: recommendationContext,
            timeoutInterval: Constants.achievementSuggestionTimeout,
            trace: trace,
            generate: { prompt, instructions in
                try await generator.generate(
                    prompt: prompt,
                    instructions: instructions,
                    temperature: 0.25,
                    maxTokens: achievementMonthlyMaxTokens
                )
            }
        )
        if let trace { TraceRecorder.shared?.record(trace) }

        if let error = outcome.failure {
            achievementSuggestionLog.error(
                """
                monthly model failure=\(AchievementSuggestionModelFailure.inferenceFailed.rawValue, privacy: .public) \
                error=\(achievementModelErrorDescription(error), privacy: .public)
                """
            )
            AIRunLog.record(
                context.record(
                    startedAt: startedAt,
                    provider: "appleFoundation",
                    model: nil,
                    outcome: "generationFailed",
                    outcomeDetail: error.detailedFailureReason,
                    selectedIDs: outcome.selectedIDs,
                    promptCharacters: outcome.promptCharacters,
                    timings: outcome.timings,
                    parameters: ["temperature": 0.25, "max_tokens": Double(achievementMonthlyMaxTokens),
                     "max_items_per_goal": Double(maxGoalsPerSuggestion)]
                )
            )
        return .failure(reason: nil)
        }
        if outcome.drafts.isEmpty {
            achievementSuggestionLog.error(
                "monthly model failure=\(AchievementSuggestionModelFailure.parsedEmpty.rawValue, privacy: .public)"
            )
        }
        let suggestions = outcome.drafts.map { $0.suggestion(cadence: .monthly, runID: context.runID) }
        // 주간과 **같은 그릇**에 담아 같은 헬퍼로 읽는다. `parse` 가 비는 건 생성 자체가
        // 실패했을 때뿐인데, 그건 위에서 이미 돌아갔다.
        let diagnostics = WeeklyGoalTask.RunOutcome.Diagnostics.parsed(
            outcome.parse ?? .decoded(
                modelReturned: 0, kept: 0, requestedIDs: 0,
                badID: 0, alreadyUsed: 0, overMaxMemo: 0, tooFewIDs: 0
            )
        )
        AIRunLog.record(
            context.record(
                startedAt: startedAt,
                provider: "appleFoundation",
                model: nil,
                // 왜 그만큼만 남았는지는 태스크가 안다. 여기서 다시 짐작하면
                // «잘려서 0개» 와 «묶을 게 없어 0개» 가 한 칸으로 뭉친다.
                outcome: AchievementGoalRecommendationResult.from(
                    outcome.result, cadence: .monthly, source: .foundationModel, runID: context.runID
                ).recordedOutcome,
                outcomeDetail: diagnostics.outcomeDetail,
                titles: suggestions.map(\.title),
                selectedIDs: outcome.selectedIDs,
                promptCharacters: outcome.promptCharacters,
                parse: diagnostics.parseSummary,
                timings: outcome.timings,
                parameters: ["temperature": 0.25, "max_tokens": Double(achievementMonthlyMaxTokens),
                     "max_items_per_goal": Double(maxGoalsPerSuggestion)]
            )
        )
        return AchievementGoalRecommendationResult.from(
            outcome.result,
            cadence: .monthly,
            source: .foundationModel,
            runID: context.runID
        )
    }

}
#endif
