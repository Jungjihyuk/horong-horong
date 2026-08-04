import Foundation
import SwiftData

struct FocusNudgeSettingsSnapshot: Equatable {
    let detectionMode: FocusNudgeDetectionMode
    let requiredFeedbackCount: Int
    let manualRule: FocusNudgeDetectionRule
    let frequencyMode: FocusNudgeFrequencyMode
    let maximumNudgesPerSession: Int

    var configuredMaximumNudges: Int? {
        frequencyMode == .unlimited ? nil : max(1, maximumNudgesPerSession)
    }
}

/// 집중 넛지 설정을 읽는 단일 경계. SwiftUI의 `@AppStorage`와 모니터가 같은 기본값·보정을 쓴다.
enum FocusNudgeSettingsStore {
    static func snapshot(defaults: UserDefaults = .standard) -> FocusNudgeSettingsSnapshot {
        let detectionMode = defaults.string(
            forKey: Constants.AppStorageKey.companionFocusNudgeDetectionMode
        ).flatMap(FocusNudgeDetectionMode.init(rawValue:)) ?? Constants.defaultFocusNudgeDetectionMode
        let frequencyMode = defaults.string(
            forKey: Constants.AppStorageKey.companionFocusNudgeFrequencyMode
        ).flatMap(FocusNudgeFrequencyMode.init(rawValue:)) ?? Constants.defaultFocusNudgeFrequencyMode
        let requiredFeedbackCount = clampedFeedbackCount(
            defaults.object(
                forKey: Constants.AppStorageKey.companionFocusNudgeRequiredFeedbackCount
            ) as? Int ?? Constants.defaultFocusNudgeRequiredFeedbackCount
        )
        let focusPercent = min(
            95,
            max(
                5,
                defaults.object(
                    forKey: Constants.AppStorageKey.companionFocusNudgeManualFocusPercent
                ) as? Int ?? Constants.defaultFocusNudgeManualFocusPercent
            )
        )
        let maximumAppSwitches = min(
            FocusNudgeDetectionRule.appSwitchRange.upperBound,
            max(
                FocusNudgeDetectionRule.appSwitchRange.lowerBound,
                defaults.object(
                    forKey: Constants.AppStorageKey.companionFocusNudgeManualMaxAppSwitches
                ) as? Int ?? Constants.defaultFocusNudgeManualMaxAppSwitches
            )
        )
        let maximumNudges = min(
            10,
            max(
                1,
                defaults.object(
                    forKey: Constants.AppStorageKey.companionFocusNudgeMaximumPerSession
                ) as? Int ?? Constants.defaultFocusNudgeMaximumPerSession
            )
        )
        return FocusNudgeSettingsSnapshot(
            detectionMode: detectionMode,
            requiredFeedbackCount: requiredFeedbackCount,
            manualRule: FocusNudgeDetectionRule(
                minimumFocusRatio: Double(focusPercent) / 100,
                maximumAppSwitches: maximumAppSwitches
            ),
            frequencyMode: frequencyMode,
            maximumNudgesPerSession: maximumNudges
        )
    }

    static func clampedFeedbackCount(_ value: Int) -> Int {
        min(100, max(10, value))
    }
}

enum FocusPersonalizationLabel: Equatable {
    case focused
    case distracted
}

/// 회고가 붙은 한 세션에서 실시간과 동일한 최근 10분 창들을 훑어 얻은 대표값.
struct FocusPersonalizationSample: Equatable {
    let label: FocusPersonalizationLabel
    /// 세션 안에서 측정 가능한 최근 10분 창 중 가장 낮았던 몰입 비율.
    let minimumFocusRatio: Double
    /// 세션 안에서 측정 가능한 최근 10분 창 중 가장 많았던 앱 전환 횟수.
    let maximumAppSwitches: Int
}

struct FocusPersonalizationEvidence: Equatable {
    let focusedAverageFocusRatio: Double?
    let distractedAverageFocusRatio: Double?
    let focusedAverageAppSwitches: Double?
    let distractedAverageAppSwitches: Double?
    let maximumObservedAppSwitches: Int
}

struct FocusPersonalizationAnalysis: Equatable {
    /// 집중 잘함과 흐트러짐에서 각각 비교할 최근 회고 수.
    let requiredFeedbackCount: Int
    let focusedFeedbackCount: Int
    let distractedFeedbackCount: Int
    let suggestedRule: FocusNudgeDetectionRule?
    let evidence: FocusPersonalizationEvidence

    var hasEnoughFeedback: Bool {
        focusedFeedbackCount >= requiredFeedbackCount
            && distractedFeedbackCount >= requiredFeedbackCount
    }

    var isReady: Bool {
        hasEnoughFeedback && suggestedRule != nil
    }
}

enum FocusPersonalizationLearner {
    /// 잘한 세션을 잘못 잡는 비율을 20% 이하로 제한한 뒤, 흐트러진 세션을 가장 많이 찾는
    /// 몰입 비율·앱 전환 경계 조합을 고른다. 동률이면 더 느슨한 조합을 택한다.
    static func analyze(
        samples: [FocusPersonalizationSample],
        requiredFeedbackCount: Int
    ) -> FocusPersonalizationAnalysis {
        let requiredCount = FocusNudgeSettingsStore.clampedFeedbackCount(requiredFeedbackCount)
        // 전체 최근 N개가 아니라 결과별 최근 N개를 따로 고른다. 최근 회고가 한쪽 결과에
        // 몰려도 다른 결과의 이전 회고를 찾아 같은 개수끼리 비교하기 위해서다.
        let focused = Array(
            samples.lazy.filter { $0.label == .focused }.prefix(requiredCount)
        )
        let distracted = Array(
            samples.lazy.filter { $0.label == .distracted }.prefix(requiredCount)
        )
        let compared = focused + distracted
        let evidence = FocusPersonalizationEvidence(
            focusedAverageFocusRatio: average(focused.map(\.minimumFocusRatio)),
            distractedAverageFocusRatio: average(distracted.map(\.minimumFocusRatio)),
            focusedAverageAppSwitches: average(focused.map { Double($0.maximumAppSwitches) }),
            distractedAverageAppSwitches: average(distracted.map { Double($0.maximumAppSwitches) }),
            maximumObservedAppSwitches: compared.map(\.maximumAppSwitches).max() ?? 0
        )

        guard focused.count >= requiredCount,
              distracted.count >= requiredCount else {
            return FocusPersonalizationAnalysis(
                requiredFeedbackCount: requiredCount,
                focusedFeedbackCount: focused.count,
                distractedFeedbackCount: distracted.count,
                suggestedRule: nil,
                evidence: evidence
            )
        }

        let maximumObservedSwitches = min(
            FocusNudgeDetectionRule.appSwitchRange.upperBound,
            compared.map(\.maximumAppSwitches).max() ?? 0
        )
        let allowedFalsePositives = Int(floor(Double(focused.count) * 0.20))
        var best: (rule: FocusNudgeDetectionRule, truePositives: Int, falsePositives: Int)?

        for focusPercent in 5...95 {
            // 높은 전환 허용값부터 훑어, 성능이 같으면 덜 엄격한 규칙을 남긴다.
            for switchMaximum in (0...maximumObservedSwitches).reversed() {
                let rule = FocusNudgeDetectionRule(
                    minimumFocusRatio: Double(focusPercent) / 100,
                    maximumAppSwitches: switchMaximum
                )
                let truePositives = distracted.filter { violates($0, rule: rule) }.count
                let falsePositives = focused.filter { violates($0, rule: rule) }.count
                let focusTruePositives = distracted.filter {
                    $0.minimumFocusRatio < rule.minimumFocusRatio
                }.count
                let focusFalsePositives = focused.filter {
                    $0.minimumFocusRatio < rule.minimumFocusRatio
                }.count
                let switchTruePositives = distracted.filter {
                    $0.maximumAppSwitches > rule.maximumAppSwitches
                }.count
                let switchFalsePositives = focused.filter {
                    $0.maximumAppSwitches > rule.maximumAppSwitches
                }.count
                guard falsePositives <= allowedFalsePositives,
                      focusTruePositives > 0,
                      switchTruePositives > 0,
                      Double(focusTruePositives) / Double(distracted.count)
                        > Double(focusFalsePositives) / Double(focused.count),
                      Double(switchTruePositives) / Double(distracted.count)
                        > Double(switchFalsePositives) / Double(focused.count) else {
                    continue
                }

                if let best {
                    guard truePositives > best.truePositives
                            || (truePositives == best.truePositives
                                && falsePositives < best.falsePositives) else {
                        continue
                    }
                }
                best = (rule, truePositives, falsePositives)
            }
        }

        let usefulRule: FocusNudgeDetectionRule?
        if let best, best.truePositives > 0 {
            let truePositiveRate = Double(best.truePositives) / Double(distracted.count)
            let falsePositiveRate = Double(best.falsePositives) / Double(focused.count)
            usefulRule = truePositiveRate > falsePositiveRate ? best.rule : nil
        } else {
            usefulRule = nil
        }

        return FocusPersonalizationAnalysis(
            requiredFeedbackCount: requiredCount,
            focusedFeedbackCount: focused.count,
            distractedFeedbackCount: distracted.count,
            suggestedRule: usefulRule,
            evidence: evidence
        )
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func violates(
        _ sample: FocusPersonalizationSample,
        rule: FocusNudgeDetectionRule
    ) -> Bool {
        sample.minimumFocusRatio < rule.minimumFocusRatio
            || sample.maximumAppSwitches > rule.maximumAppSwitches
    }
}

@MainActor
enum FocusPersonalizationTrainer {
    static func analyze(
        requiredFeedbackCount: Int,
        modelContext: ModelContext
    ) -> FocusPersonalizationAnalysis {
        let requiredCount = FocusNudgeSettingsStore.clampedFeedbackCount(requiredFeedbackCount)
        let reflectionDescriptor = FetchDescriptor<PomodoroReflection>(
            sortBy: [SortDescriptor(\.answeredAt, order: .reverse)]
        )
        let reflections = (try? modelContext.fetch(reflectionDescriptor)) ?? []
        let labeledReflections = reflections.compactMap { reflection -> (
            reflection: PomodoroReflection,
            label: FocusPersonalizationLabel
        )? in
            switch reflection.focusExperience {
            case .deeplyFocused, .mostlyFocused:
                return (reflection, .focused)
            case .frequentlyDistracted, .difficultToFocus:
                return (reflection, .distracted)
            case .unsure, .none:
                return nil
            }
        }

        // 결과별로 후보를 먼저 고르면 최근 회고가 모두 "집중 잘함"이어도 더 과거의
        // "흐트러짐" 회고를 별도로 가져올 수 있다. 측정 불가 세션을 건너뛸 여유도 둔다.
        let candidateLimit = max(40, requiredCount * 4)
        let candidateReflections = Array(
            labeledReflections.lazy.filter { $0.label == .focused }.prefix(candidateLimit)
        ) + Array(
            labeledReflections.lazy.filter { $0.label == .distracted }.prefix(candidateLimit)
        )

        let targetIDs = Set(candidateReflections.map { $0.reflection.focusSessionID })
        let sessions = ((try? modelContext.fetch(FetchDescriptor<FocusSession>())) ?? [])
            .filter { targetIDs.contains($0.id) && FocusScoreHistory.isCompletedPomodoro($0) }
        let sessionByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })

        guard let firstStart = sessions.map(\.startedAt).min(),
              let lastEnd = sessions.compactMap(\.endedAt).max() else {
            return FocusPersonalizationLearner.analyze(
                samples: [],
                requiredFeedbackCount: requiredCount
            )
        }
        let segments = (try? modelContext.fetch(
            FetchDescriptor<AppUsageSegment>(
                predicate: #Predicate { $0.startTime < lastEnd && $0.endTime > firstStart },
                sortBy: [SortDescriptor(\.startTime)]
            )
        )) ?? []

        var samples: [FocusPersonalizationSample] = []
        for item in candidateReflections {
            guard let session = sessionByID[item.reflection.focusSessionID] else { continue }
            let intervals = FocusScoreHistory.focusIntervals(for: session)
            let sessionSegments = segments.filter {
                guard let end = session.endedAt else { return false }
                return $0.startTime < end && $0.endTime > session.startedAt
            }
            let category = session.category ?? Constants.defaultFocusCategory
            let windows = FocusScoreHistory.sessionWindowMetrics(
                activeIntervals: intervals,
                segments: sessionSegments,
                focusCategory: category
            ).filter { $0.score.isMeasurable }
            guard let minimumFocusRatio = windows.map({ $0.score.value }).min(),
                  let maximumAppSwitches = windows.map(\.appSwitchCount).max() else {
                continue
            }
            samples.append(
                FocusPersonalizationSample(
                    label: item.label,
                    minimumFocusRatio: minimumFocusRatio,
                    maximumAppSwitches: maximumAppSwitches
                )
            )
        }

        return FocusPersonalizationLearner.analyze(
            samples: samples,
            requiredFeedbackCount: requiredCount
        )
    }
}

enum FocusNudgePolicyResolver {
    static func resolve(
        settings: FocusNudgeSettingsSnapshot,
        personalization: FocusPersonalizationAnalysis?
    ) -> FocusNudgePolicy {
        let personalizedRule: FocusNudgeDetectionRule? = {
            guard settings.detectionMode == .personalized,
                  personalization?.isReady == true,
                  let suggested = personalization?.suggestedRule else { return nil }
            return suggested
        }()
        return FocusNudgePolicy(
            source: personalizedRule == nil ? .ruleBased : .personalized,
            rule: personalizedRule ?? settings.manualRule,
            maximumNudgesPerSession: settings.configuredMaximumNudges
        )
    }
}
