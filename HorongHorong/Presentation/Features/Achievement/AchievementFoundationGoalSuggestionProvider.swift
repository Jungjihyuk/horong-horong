import AppKit
import HorongAI
import HorongAIMLX
import OSLog
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if canImport(FoundationModels)
import FoundationModels
#endif

/*
 규칙 기반 추천 공급자와 그 보조 변환들. 모델을 쓸 수 없을 때의 폴백이다.

 원래 `AchievementViews.swift`(9,854줄) 한 파일에 있었다. 2026-09-03 분할.
 */

enum AchievementFoundationGoalSuggestionProvider {
    /// 설정에서 고른 공급자로 추천을 만든다. 실패하면 다음 단계로 내려간다.
    ///
    ///     MLX → AFM → (호출부의) 룰 기반
    ///
    /// MLX가 실패하는 경우는 대체로 모델 미준비이거나 Intel 맥이다. 둘 다 사용자가
    /// 당장 손쓸 수 없으므로 조용히 AFM으로 내려가는 편이 낫다.
    /// - Parameters:
    ///   - runID: 버튼 한 번에 붙는 id. 주간·월간이 같은 값을 받아 한 실행으로 묶인다.
    ///   - candidateCount: 필터를 통과한 **전체** 후보 수. 태스크는 이 값을 모른다 —
    ///     `memos` 는 이미 걸러진 뒤라, 얼마나 걸러졌는지는 앱만 안다.
    static func suggestions(
        from memos: [AchievementMemoSnapshot],
        suggestionCount: Int,
        maxMemoCount: Int,
        runID: String = AIRunLog.newRunID(),
        candidateCount: Int? = nil,
        variant: String? = nil,
        recommendationContext: GoalRecommendationContext = .empty,
        modelOverride: String? = nil,
        allowFallback: Bool = true,
        // 실행당 **한 번** 읽은 값을 받는다. 여기서 다시 읽으면 주간과 월간이 서로 다른
        // 공급자를 볼 수 있다 — 순차로 돌면 두 읽기 사이가 수십 초까지 벌어진다
        // (실측 2026-08-19: 주간 mlx, 7초 뒤 월간 appleFoundation).
        provider: Constants.AchievementSuggestionProviderKind
    ) async -> AchievementGoalRecommendationResult {
        let context = RunContext(
            runID: runID,
            task: "weekly_goal",
            candidateCount: candidateCount ?? memos.count,
            variant: variant
        )

        switch provider {
        case .mlx:
            let fromMLX = await mlxSuggestions(
                from: memos,
                suggestionCount: suggestionCount,
                maxMemoCount: maxMemoCount,
                context: context.attempt(1),
                recommendationContext: recommendationContext,
                modelOverride: modelOverride
            )
            if !fromMLX.shouldFallbackToNextProvider || !allowFallback { return fromMLX }
            achievementSuggestionLog.info("weekly provider fallback=mlx→afm")
        case .ollama:
            let fromOllama = await ollamaSuggestions(
                from: memos,
                suggestionCount: suggestionCount,
                maxMemoCount: maxMemoCount,
                context: context.attempt(1),
                recommendationContext: recommendationContext,
                modelOverride: modelOverride
            )
            if !fromOllama.shouldFallbackToNextProvider || !allowFallback { return fromOllama }
            achievementSuggestionLog.info("weekly provider fallback=ollama→afm")
        case .appleFoundation:
            break
        }
        // AFM 이 첫 시도인지 폴백인지에 따라 순번이 달라진다. 그래야 기록에서
        // "Ollama 가 실패해 내려온 AFM"과 "처음부터 AFM"이 구분된다.
        return await appleFoundationSuggestions(
            from: memos,
            suggestionCount: suggestionCount,
            maxMemoCount: maxMemoCount,
            context: context.attempt(provider == .appleFoundation ? 1 : 2),
            recommendationContext: recommendationContext
        )
    }

    static var selectedProvider: Constants.AchievementSuggestionProviderKind {
        let raw = UserDefaults.standard.string(forKey: Constants.AppStorageKey.achievementSuggestionProvider)
            ?? Constants.defaultAchievementSuggestionProvider
        return Constants.AchievementSuggestionProviderKind(rawValue: raw) ?? .appleFoundation
    }

    private static func mlxSuggestions(
        from memos: [AchievementMemoSnapshot],
        suggestionCount: Int,
        maxMemoCount: Int,
        context: RunContext,
        recommendationContext: GoalRecommendationContext,
        modelOverride: String?
    ) async -> AchievementGoalRecommendationResult {
        #if canImport(MLXLLM)
        if #available(macOS 26.0, *) {
            let model = modelOverride ?? UserDefaults.standard.string(forKey: Constants.AppStorageKey.achievementSuggestionMLXModel)
                ?? Constants.defaultAchievementSuggestionMLXModel
            let generator = MLXTextGenerator(model: model)
            let temperature = 0.2
            let maxTokens = 1_200
            return await weeklySuggestions(
                from: memos,
                suggestionCount: suggestionCount,
                maxMemoCount: maxMemoCount,
                provider: .mlx,
                model: model,
                source: .mlx,
                context: context,
                recommendationContext: recommendationContext,
                parameters: [
                    "temperature": temperature,
                    "max_tokens": Double(maxTokens)
                ],
                // 안 받아 둔 모델이면 프롬프트를 만들 필요가 없다. 그대로 보내면 생성 단계에서
                // `MLXChatError.notPrepared` 가 나는데, 그건 기록에 `inferenceError` 로 남아
                // «모델을 안 받았다» 는 진짜 원인이 가려진다 — Ollama 404 와 똑같은 사정이다.
                //
                // Apple Silicon 이 아닌 기기도 같은 값으로 묶는다. 그 기기에서는 **모든** MLX
                // 실행이 이렇게 나오므로 기록 한 건만 봐도 구분된다.
                preflight: {
                    MLXModelStore.isSupported && MLXModelStore.isKnownPrepared(model)
                        ? nil
                        : "modelUnavailable"
                },
                generate: { prompt, instructions in
                    let text = try await generator.generate(
                        prompt: prompt,
                        instructions: instructions,
                        temperature: temperature,
                        maxTokens: maxTokens
                    )
                    return WeeklyGoalTask.GenerationOutput(text: text, usage: nil)
                }
            )
        }
        #endif
        achievementSuggestionLog.error("weekly mlx failure=unavailable")
        return .failure(reason: nil)
    }

    private static func ollamaSuggestions(
        from memos: [AchievementMemoSnapshot],
        suggestionCount: Int,
        maxMemoCount: Int,
        context: RunContext,
        recommendationContext: GoalRecommendationContext,
        modelOverride: String?
    ) async -> AchievementGoalRecommendationResult {
        if #available(macOS 26.0, *) {
            let model = modelOverride ?? UserDefaults.standard.string(forKey: Constants.AppStorageKey.achievementSuggestionOllamaModel)
                ?? Constants.defaultAchievementSuggestionOllamaModel
            let endpoint = UserDefaults.standard.string(forKey: Constants.NewsStorageKey.ollamaEndpoint)
                ?? Constants.defaultNewsOllamaEndpoint
            let generator = OllamaTextGenerator(endpoint: endpoint, model: model)
            
            let temperature = 0.3
            let repeatPenalty = 1.15
            let presencePenalty = 0.0
            let frequencyPenalty = 0.0
            let maxTokens = 1_200
            
            return await weeklySuggestions(
                from: memos,
                suggestionCount: suggestionCount,
                maxMemoCount: maxMemoCount,
                provider: .ollama,
                model: model,
                source: .ollama,
                context: context,
                recommendationContext: recommendationContext,
                parameters: [
                    "temperature": temperature,
                    "repeat_penalty": repeatPenalty,
                    "presence_penalty": presencePenalty,
                    "frequency_penalty": frequencyPenalty,
                    "max_tokens": Double(maxTokens)
                ],
                // 서버가 꺼져 있거나 **모델을 안 받아 뒀으면** 프롬프트를 만들어 보낼 필요가 없다.
                // 보내 보면 Ollama 가 404 를 주는데, 그건 기록에 «추론 실패» 로 남아
                // «모델을 안 받았다» 는 진짜 원인이 가려진다(실측 2026-08-19).
                preflight: {
                    switch await OllamaChatClient.readiness(endpoint: endpoint, model: model) {
                    case .ready:            return nil
                    case .serverUnavailable: return "serverUnavailable"
                    case .modelNotInstalled: return "modelUnavailable"
                    }
                },
                generate: { prompt, instructions in
                    let output = try await generator.generateWithUsage(
                        prompt: prompt,
                        instructions: instructions,
                        temperature: temperature,
                        maxTokens: maxTokens,
                        repeatPenalty: repeatPenalty,
                        presencePenalty: presencePenalty,
                        frequencyPenalty: frequencyPenalty,
                        // 프롬프트로 부탁만 하지 않고 **모양을 강제한다.**
                        format: WeeklyGoalTask.responseSchema,
                        // 태스크 쪽 벽시계와 **같은 값**이어야 한다. 한쪽만 길면 짧은 쪽이 새 벽이 된다.
                        timeoutInterval: Constants.achievementSuggestionTimeout
                    )
                    return WeeklyGoalTask.GenerationOutput(text: output.text, usage: output.usage)
                }
            )
        }
        return .failure(reason: nil)
    }

    /// MLX·Ollama 가 공유하는 주간 추천 흐름.
    ///
    /// 두 공급자의 고유 코드는 `generate` 한 덩어리뿐이고 나머지(입력 고르기 · 프롬프트 ·
    /// 파싱 · 로그 · 재태깅)는 완전히 같았다. 두 파일로 나눠 두면 한쪽만 고치는 실수가 난다.
    /// AFM 은 세션 생성 방식이 달라(`LanguageModelSession`) 아직 합치지 않았다.
    ///
    /// `@available` 은 프롬프트·파서를 AFM 구현체에서 빌려 쓰기 때문에 따라온 것이다.
    /// 삭제한 두 파일도 같은 이유로 같은 제약을 달고 있었다.
    @available(macOS 26.0, *)
    private static func weeklySuggestions(
        from memos: [AchievementMemoSnapshot],
        suggestionCount: Int,
        maxMemoCount: Int,
        provider: Constants.AchievementSuggestionProviderKind,
        model: String,
        source: AchievementGoalSuggestionSource,
        context: RunContext,
        recommendationContext: GoalRecommendationContext,
        parameters: [String: Double] = [:],
        /// 실행 전에 막을 이유가 있으면 **기록할 결과 이름**을 돌려준다. 막을 이유가 없으면 `nil`.
        ///
        /// `Bool` 로 두면 «왜 막혔나» 가 사라져, 서버가 꺼진 것과 모델을 안 받아 둔 것이
        /// 기록에서 한 칸으로 뭉친다. 사용자가 할 일은 서로 다르다.
        preflight: () async -> String? = { nil },
        // 태스크가 타임아웃을 태스크 그룹으로 재므로 클로저가 탈출한다.
        generate: @escaping (_ prompt: String, _ instructions: String) async throws -> WeeklyGoalTask.GenerationOutput
    ) async -> AchievementGoalRecommendationResult {
        let label = provider.rawValue
        let startedAt = Date()
        // 묶음당 상한을 기록에 싣는다. 없으면 AI 실험실이 «3개 잘림» 만 보여줄 수 있고,
        // **설정이 몇이라 잘렸는지**를 못 말한다.
        let parameters = parameters.merging(["max_items_per_goal": Double(maxMemoCount)]) { a, _ in a }

        if let blocked = await preflight() {
            achievementSuggestionLog.error(
                "weekly \(label, privacy: .public) failure=\(blocked, privacy: .public)"
            )
            AIRunLog.record(
                context.record(
                    startedAt: startedAt,
                    provider: label,
                    model: model,
                    outcome: blocked,
                    parameters: parameters
                )
            )
            return .failure(reason: blocked)
        }

        // 원문 기록. 개발자 모드가 아니면 nil 이라 아무 비용도 들지 않는다.
        let trace = TraceRecorder.shared?.makeCollector(
            runId: context.runID,
            task: context.task,
            provider: label,
            model: model,
            attempt: context.attemptNumber
        )
        let outcome = await WeeklyGoalTask.run(
            memos: memos.map(\.taskMemo),
            suggestionCount: suggestionCount,
            maxMemoCount: maxMemoCount,
            inputLimit: max(8, min(provider == .ollama || provider == .appleFoundation ? 15 : 24, suggestionCount * maxMemoCount * 2)),
            budget: Constants.achievementPromptCharacterBudget(for: provider),
            context: recommendationContext,
            timeoutInterval: Constants.achievementSuggestionTimeout,
            onPromptBuilt: { characters, memoCount in
                achievementSuggestionLog.info(
                    """
                    weekly \(label, privacy: .public) prompt chars=\(characters, privacy: .public) \
                    memos=\(memoCount, privacy: .public) model=\(model, privacy: .public)
                    """
                )
            },
            trace: trace,
            generate: generate
        )
        if let trace { TraceRecorder.shared?.record(trace) }

        let suggestions = outcome.drafts.map { $0.suggestion(cadence: .weekly, runID: context.runID).retagged(as: source) }

        switch outcome.diagnostics {
        case .parsed(let diagnostics):
            logWeeklyParse(diagnostics)
            if outcome.drafts.isEmpty {
                achievementSuggestionLog.error(
                    """
                    weekly \(label, privacy: .public) \
                    failure=\(AchievementSuggestionModelFailure.parsedEmpty.rawValue, privacy: .public)
                    """
                )
            }
        case .generationFailed(let error):
            achievementSuggestionLog.error(
                """
                weekly \(label, privacy: .public) \
                failure=\(AchievementSuggestionModelFailure.inferenceFailed.rawValue, privacy: .public) \
                error=\(String(describing: error).prefix(300), privacy: .public)
                """
            )
        }

        let result: AchievementGoalRecommendationResult
        switch outcome.diagnostics {
        case .generationFailed, .parsed(.decodeFailed):
            result = .failure(reason: outcome.diagnostics.outcomeDetail)
        case .parsed:
            result = AchievementGoalRecommendationResult.from(
                outcome.result, cadence: .weekly, source: source, runID: context.runID
            )
        }

        AIRunLog.record(
            context.record(
                startedAt: startedAt,
                provider: label,
                model: model,
                outcome: result.recordedOutcome,
                outcomeDetail: outcome.diagnostics.outcomeDetail,
                titles: suggestions.map(\.title),
                selectedIDs: outcome.selectedIDs,
                promptCharacters: outcome.promptCharacters,
                parse: outcome.diagnostics.parseSummary,
                usage: outcome.usage,
                timings: outcome.timings,
                parameters: parameters
            )
        )

        // 태스크는 어느 공급자가 답했는지 모른다. 실제 공급자로 태깅해 폴백 비율 집계를 맞춘다.
        return result
    }

    /// 파서 진단을 로그 한 줄로. AFM 경로(`FoundationModelsGoalSuggestionProvider.parse`)와 같은 문구를 쓴다.
    /// 파일이 갈리면서 `fileprivate` 로는 안 보이게 됐다.
    /// `FoundationModelsGoalSuggestionProvider` 가 같은 형식으로 남기려고 부른다.
    static func logWeeklyParse(_ diagnostics: WeeklyGoalTask.ParseOutcome.Diagnostics) {
        switch diagnostics {
        case let .decodeFailed(characters, reason):
            achievementSuggestionLog.error(
                """
                weekly parse failure=decode chars=\(characters, privacy: .public) \
                reason=\(reason, privacy: .public)
                """
            )
        case let .decoded(modelReturned, kept, requestedIDs, badID, alreadyUsed, overMaxMemo, tooFewIDs):
            achievementSuggestionLog.info(
                """
                weekly parse modelReturned=\(modelReturned, privacy: .public) \
                kept=\(kept, privacy: .public) requestedIDs=\(requestedIDs, privacy: .public) \
                badID=\(badID, privacy: .public) alreadyUsed=\(alreadyUsed, privacy: .public) \
                overMaxMemo=\(overMaxMemo, privacy: .public) tooFewIDs=\(tooFewIDs, privacy: .public)
                """
            )
        }
    }

    private static func appleFoundationSuggestions(
        from memos: [AchievementMemoSnapshot],
        suggestionCount: Int,
        maxMemoCount: Int,
        context: RunContext,
        recommendationContext: GoalRecommendationContext
    ) async -> AchievementGoalRecommendationResult {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await FoundationModelsGoalSuggestionProvider().suggestions(
                from: memos,
                suggestionCount: suggestionCount,
                maxMemoCount: maxMemoCount,
                context: context,
                recommendationContext: recommendationContext
            )
        }
        #endif
        return .failure(reason: nil)
    }

    static func monthlySuggestions(
        from goals: [AchievementGoalSnapshot],
        suggestionCount: Int,
        maxGoalsPerSuggestion: Int = MonthlyGoalTask.maxGoalsPerSuggestion,
        runID: String = AIRunLog.newRunID(),
        candidateCount: Int? = nil,
        variant: String? = nil,
        recommendationContext: GoalRecommendationContext = .empty,
        modelOverride: String? = nil,
        allowFallback: Bool = true,
        /// 주간(`suggestions`)과 같은 사정이다 — 실행당 한 번 읽은 값을 받는다.
        provider: Constants.AchievementSuggestionProviderKind
    ) async -> AchievementGoalRecommendationResult {
        let context = RunContext(
            runID: runID,
            task: "monthly_goal",
            candidateCount: candidateCount ?? goals.count,
            variant: variant
        )

        // 주간과 같은 설정값(`achievementSuggestionProvider`)을 따른다. 8/2 에 Ollama 를 붙일 때
        // 주간 경로에만 분기를 달아서, 설정에서 Ollama 를 골라도 월간은 계속 AFM 으로만 돌았다.
        switch provider {
        case .mlx:
            let fromMLX = await monthlyMLXSuggestions(
                from: goals,
                suggestionCount: suggestionCount,
                maxGoalsPerSuggestion: maxGoalsPerSuggestion,
                context: context.attempt(1),
                recommendationContext: recommendationContext,
                modelOverride: modelOverride
            )
            if !fromMLX.shouldFallbackToNextProvider || !allowFallback { return fromMLX }
            achievementSuggestionLog.info("monthly provider fallback=mlx→afm")
        case .ollama:
            let fromOllama = await monthlyOllamaSuggestions(
                from: goals,
                suggestionCount: suggestionCount,
                maxGoalsPerSuggestion: maxGoalsPerSuggestion,
                context: context.attempt(1),
                recommendationContext: recommendationContext,
                modelOverride: modelOverride
            )
            if !fromOllama.shouldFallbackToNextProvider || !allowFallback { return fromOllama }
            achievementSuggestionLog.info("monthly provider fallback=ollama→afm")
        case .appleFoundation:
            break
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await FoundationModelsGoalSuggestionProvider().monthlySuggestions(
                from: goals,
                suggestionCount: suggestionCount,
                maxGoalsPerSuggestion: maxGoalsPerSuggestion,
                context: context.attempt(provider == .appleFoundation ? 1 : 2),
                recommendationContext: recommendationContext
            )
        }
        #endif
        return .failure(reason: nil)
    }

    private static func monthlyMLXSuggestions(
        from goals: [AchievementGoalSnapshot],
        suggestionCount: Int,
        maxGoalsPerSuggestion: Int,
        context: RunContext,
        recommendationContext: GoalRecommendationContext,
        modelOverride: String?
    ) async -> AchievementGoalRecommendationResult {
        #if canImport(MLXLLM)
        if #available(macOS 26.0, *) {
            let model = modelOverride ?? UserDefaults.standard.string(forKey: Constants.AppStorageKey.achievementSuggestionMLXModel)
                ?? Constants.defaultAchievementSuggestionMLXModel
            let generator = MLXTextGenerator(model: model)
            let temperature = 0.25
            let maxTokens = achievementMonthlyMaxTokens
            return await sharedMonthlySuggestions(
                from: goals,
                suggestionCount: suggestionCount,
                maxGoalsPerSuggestion: maxGoalsPerSuggestion,
                provider: .mlx,
                model: model,
                source: .mlx,
                context: context,
                recommendationContext: recommendationContext,
                parameters: [
                    "temperature": temperature,
                    "max_tokens": Double(maxTokens)
                ],
                // 주간 MLX 경로와 같은 판단이다.
                preflight: {
                    MLXModelStore.isSupported && MLXModelStore.isKnownPrepared(model)
                        ? nil
                        : "modelUnavailable"
                },
                generate: { prompt, instructions in
                    try await generator.generate(
                        prompt: prompt,
                        instructions: instructions,
                        temperature: temperature,
                        maxTokens: maxTokens
                    )
                }
            )
        }
        #endif
        achievementSuggestionLog.error("monthly mlx failure=unavailable")
        return .failure(reason: nil)
    }

    private static func monthlyOllamaSuggestions(
        from goals: [AchievementGoalSnapshot],
        suggestionCount: Int,
        maxGoalsPerSuggestion: Int,
        context: RunContext,
        recommendationContext: GoalRecommendationContext,
        modelOverride: String?
    ) async -> AchievementGoalRecommendationResult {
        if #available(macOS 26.0, *) {
            let model = modelOverride ?? UserDefaults.standard.string(forKey: Constants.AppStorageKey.achievementSuggestionOllamaModel)
                ?? Constants.defaultAchievementSuggestionOllamaModel
            let endpoint = UserDefaults.standard.string(forKey: Constants.NewsStorageKey.ollamaEndpoint)
                ?? Constants.defaultNewsOllamaEndpoint
            let generator = OllamaTextGenerator(endpoint: endpoint, model: model)

            // 온도·토큰은 AFM 월간 경로와 맞춘다 — 공급자를 바꿔도 같은 질문이어야 비교가 된다.
            // 반복 페널티는 주간 Ollama 경로와 같은 이유다(같은 생성기라 같은 루프 위험을 진다).
            let temperature = 0.25
            let repeatPenalty = 1.15
            let presencePenalty = 0.0
            let frequencyPenalty = 0.0
            let maxTokens = achievementMonthlyMaxTokens

            return await sharedMonthlySuggestions(
                from: goals,
                suggestionCount: suggestionCount,
                maxGoalsPerSuggestion: maxGoalsPerSuggestion,
                provider: .ollama,
                model: model,
                source: .ollama,
                context: context,
                recommendationContext: recommendationContext,
                parameters: [
                    "temperature": temperature,
                    "repeat_penalty": repeatPenalty,
                    "presence_penalty": presencePenalty,
                    "frequency_penalty": frequencyPenalty,
                    "max_tokens": Double(maxTokens)
                ],
                // 서버가 꺼져 있거나 **모델을 안 받아 뒀으면** 프롬프트를 만들어 보낼 필요가 없다.
                // 보내 보면 Ollama 가 404 를 주는데, 그건 기록에 «추론 실패» 로 남아
                // «모델을 안 받았다» 는 진짜 원인이 가려진다(실측 2026-08-19).
                preflight: {
                    switch await OllamaChatClient.readiness(endpoint: endpoint, model: model) {
                    case .ready:            return nil
                    case .serverUnavailable: return "serverUnavailable"
                    case .modelNotInstalled: return "modelUnavailable"
                    }
                },
                generate: { prompt, instructions in
                    try await generator.generate(
                        prompt: prompt,
                        instructions: instructions,
                        temperature: temperature,
                        maxTokens: maxTokens,
                        repeatPenalty: repeatPenalty,
                        presencePenalty: presencePenalty,
                        frequencyPenalty: frequencyPenalty,
                        format: MonthlyGoalTask.responseSchema,
                        // 태스크 쪽 벽시계와 **같은 값**이어야 한다. 한쪽만 길면 짧은 쪽이 새 벽이 된다.
                        timeoutInterval: Constants.achievementSuggestionTimeout
                    )
                }
            )
        }
        return .failure(reason: nil)
    }

    /// MLX·Ollama 가 공유하는 월간 추천 흐름. 주간의 `weeklySuggestions` 와 짝이다.
    ///
    /// 이름이 `monthlySuggestions` 가 아닌 이유는 **바깥에 같은 이름의 분배기가 있어서**다.
    /// 둘을 같은 이름으로 두면 호출부에서 어느 쪽이 불리는지 눈으로 가릴 수 없다.
    @available(macOS 26.0, *)
    private static func sharedMonthlySuggestions(
        from goals: [AchievementGoalSnapshot],
        suggestionCount: Int,
        maxGoalsPerSuggestion: Int,
        provider: Constants.AchievementSuggestionProviderKind,
        model: String,
        source: AchievementGoalSuggestionSource,
        context: RunContext,
        recommendationContext: GoalRecommendationContext,
        parameters: [String: Double] = [:],
        /// 주간(`weeklySuggestions`)과 같은 규약이다 — 막을 이유가 있으면 기록할 결과 이름.
        preflight: () async -> String? = { nil },
        // 태스크가 타임아웃을 태스크 그룹으로 재므로 클로저가 탈출한다.
        generate: @escaping (_ prompt: String, _ instructions: String) async throws -> String
    ) async -> AchievementGoalRecommendationResult {
        let label = provider.rawValue
        let startedAt = Date()
        // 주간과 같은 사정이다. 월간 상한은 설정이 아니라 상수(`maxGoalsPerSuggestion`)다.
        let parameters = parameters.merging(
            ["max_items_per_goal": Double(maxGoalsPerSuggestion)]
        ) { a, _ in a }

        if let blocked = await preflight() {
            achievementSuggestionLog.error(
                "monthly \(label, privacy: .public) failure=\(blocked, privacy: .public)"
            )
            AIRunLog.record(
                context.record(
                    startedAt: startedAt,
                    provider: label,
                    model: model,
                    outcome: blocked,
                    parameters: parameters
                )
            )
            return .failure(reason: blocked)
        }

        let trace = TraceRecorder.shared?.makeCollector(
            runId: context.runID,
            task: context.task,
            provider: label,
            model: model,
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
            generate: generate
        )
        if let trace { TraceRecorder.shared?.record(trace) }

        if let error = outcome.failure {
            achievementSuggestionLog.error(
                """
                monthly \(label, privacy: .public) \
                failure=\(AchievementSuggestionModelFailure.inferenceFailed.rawValue, privacy: .public) \
                error=\(achievementModelErrorDescription(error), privacy: .public)
                """
            )
            AIRunLog.record(
                context.record(
                    startedAt: startedAt,
                    provider: label,
                    model: model,
                    outcome: "generationFailed",
                    outcomeDetail: error.detailedFailureReason,
                    selectedIDs: outcome.selectedIDs,
                    promptCharacters: outcome.promptCharacters,
                    timings: outcome.timings,
                    parameters: parameters
                )
            )
            return .failure(reason: error.detailedFailureReason)
        }
        if outcome.drafts.isEmpty {
            achievementSuggestionLog.error(
                """
                monthly \(label, privacy: .public) \
                failure=\(AchievementSuggestionModelFailure.parsedEmpty.rawValue, privacy: .public)
                """
            )
        }

        // 파서를 AFM 경로와 공유하므로 초안은 `.foundationModel` 로 붙어 나온다. 실제 공급자로 다시 태깅한다.
        let suggestions = outcome.drafts.map { $0.suggestion(cadence: .monthly, runID: context.runID).retagged(as: source) }
        // 주간과 **같은 그릇**에 담아 같은 헬퍼로 읽는다. `parse` 가 비는 건 생성 자체가
        // 실패했을 때뿐인데, 그건 위에서 이미 돌아갔다.
        let diagnostics = WeeklyGoalTask.RunOutcome.Diagnostics.parsed(
            outcome.parse ?? .decoded(
                modelReturned: 0, kept: 0, requestedIDs: 0,
                badID: 0, alreadyUsed: 0, overMaxMemo: 0, tooFewIDs: 0
            )
        )
        let result: AchievementGoalRecommendationResult
        if case .decodeFailed = outcome.parse {
            result = .failure(reason: diagnostics.outcomeDetail)
        } else {
            result = AchievementGoalRecommendationResult.from(
                outcome.result, cadence: .monthly, source: source, runID: context.runID
            )
        }
        AIRunLog.record(
            context.record(
                startedAt: startedAt,
                provider: label,
                model: model,
                // 왜 그만큼만 남았는지는 태스크가 안다. 여기서 다시 짐작하면
                // «잘려서 0개» 와 «묶을 게 없어 0개» 가 한 칸으로 뭉친다.
                outcome: result.recordedOutcome,
                outcomeDetail: diagnostics.outcomeDetail,
                titles: suggestions.map(\.title),
                selectedIDs: outcome.selectedIDs,
                promptCharacters: outcome.promptCharacters,
                parse: diagnostics.parseSummary,
                timings: outcome.timings,
                parameters: parameters
            )
        )
        return result
    }
}

/// 앱 도메인 타입을 패키지 태스크의 입력으로 바꾼다.
///
/// 패키지는 `AchievementMemoSnapshot` 을 알면 안 되므로 경계에서 앱이 변환한다.
/// 아이콘 기본값처럼 **앱이 정하는 값**도 여기서 채운다.
extension AchievementMemoSnapshot {
    var taskMemo: WeeklyGoalTask.Memo {
        WeeklyGoalTask.Memo(
            id: id,
            content: content,
            icon: icon ?? MemoIcon.defaultIcon,
            date: date,
            startDate: startDate,
            deadline: deadline,
            isCompleted: isCompleted
        )
    }
}

/// 패키지가 만든 초안을 앱 도메인 값으로 바꾼다.
///
/// `reason` 을 여기서 줄이는 이유는 72자 제한이 **화면 사정**이기 때문이다 — 파서가 정할 일이 아니다.
/// 추천 카드가 이유를 2줄까지만 보여준다(`AchievementViews.swift` 의 `lineLimit(2)`).
extension GoalSuggestionDraft {
    func suggestion(cadence: AchievementGoalCadence, runID: String? = nil) -> AchievementGoalSuggestion {
        AchievementGoalSuggestion(
            title: title,
            reason: AchievementDataBuilder.shortText(reason, limit: 72),
            memoIDs: memoIDs,
            childGoalIDs: childGoalIDs,
            scheduleText: scheduleText,
            criterion: criterion,
            targetValueText: targetValueText,
            emoji: emoji,
            cadence: cadence,
            source: .foundationModel,
            runID: runID
        )
    }
}

extension AchievementGoalSnapshot {
    var taskGoal: MonthlyGoalTask.Goal {
        MonthlyGoalTask.Goal(
            id: id,
            title: title,
            emoji: emoji,
            rule: rule,
            done: done,
            total: total,
            sourceMemoIDs: sourceMemoIDs,
            roleName: roleName,
            vision: vision
        )
    }
}
