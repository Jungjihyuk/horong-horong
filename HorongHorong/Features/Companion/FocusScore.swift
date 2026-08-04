import Foundation

/// 집중 세션 한 건의 몰입도.
///
/// 정의는 한 줄이다 — **하기로 한 일에 쓴 시간 ÷ 무슨 일인지 알 수 있는 시간**.
///
/// 자리를 비웠거나 기록되지 않은 시간은 분모에 남는다. 포모도로 25분은 책상에 있기로 한 시간이므로
/// 자리를 비운 것도 몰입하지 않은 것으로 센다.
/// 반면 **매핑하지 않은 앱(미분류)에 쓴 시간은 분자·분모 양쪽에서 뺀다.** 그건 딴짓이라는 사실이
/// 아니라 아직 모른다는 뜻이라, 딴짓으로 세면 처음 쓰는 업무 앱을 켠 사람을 몰아세우게 된다.
struct FocusScore: Equatable {
    /// 집중 카테고리 + 짝 카테고리에 쓴 시간.
    let focusSeconds: Int
    /// 무슨 일인지 알 수 있는 시간. 세션 전체에서 미분류 앱 시간을 뺀 값.
    let measuredSeconds: Int
    /// 세션 전체 시간.
    let totalSeconds: Int
    /// 실제 앱 사용 기록 중 카테고리를 아는 시간.
    let classifiedAppSeconds: Int
    /// 카테고리 판정이 가능한 앱 사용 기록 전체 시간. 겹쳐서 귀속할 수 없는 시간은 제외한다.
    let recordedAppSeconds: Int

    /// 기록된 앱 사용의 이만큼은 카테고리를 알아야 몰입도를 말한다.
    static let minimumClassifiedAppRatio = 0.5

    init(
        focusSeconds: Int,
        measuredSeconds: Int,
        totalSeconds: Int,
        classifiedAppSeconds: Int? = nil,
        recordedAppSeconds: Int? = nil
    ) {
        self.focusSeconds = max(0, focusSeconds)
        self.measuredSeconds = max(0, measuredSeconds)
        self.totalSeconds = max(0, totalSeconds)
        // 기존 호출부는 종전의 measured / total 판정을 그대로 유지한다. 실제 관측 계산은 아래 두 값을 넘긴다.
        self.classifiedAppSeconds = max(0, classifiedAppSeconds ?? measuredSeconds)
        self.recordedAppSeconds = max(0, recordedAppSeconds ?? totalSeconds)
    }

    /// 0...1. 잴 시간이 없으면 0. 이 값을 쓰기 전에 `isMeasurable` 을 먼저 봐야 한다.
    var value: Double {
        guard measuredSeconds > 0 else { return 0 }
        return min(1, max(0, Double(focusSeconds) / Double(measuredSeconds)))
    }

    /// 기록된 앱 사용의 카테고리를 몰입도를 말할 만큼 알고 있는가.
    ///
    /// 매핑하지 않은 앱으로 세션 내내 일한 경우 `value` 는 0 이 되지만 그건 딴짓해서가 아니다.
    /// 그 세션은 판정하지 않고 넘어간다.
    var isMeasurable: Bool {
        guard totalSeconds > 0 else { return false }
        // 앱 기록이 전혀 없는 시간은 기존 정책대로 미기록(비집중)으로 다룬다.
        guard recordedAppSeconds > 0 else { return true }
        return Double(classifiedAppSeconds) / Double(recordedAppSeconds)
            >= Self.minimumClassifiedAppRatio
    }
}

/// 그래프에 찍을 세션 한 점.
struct FocusScoreSample: Identifiable, Equatable {
    let id: UUID
    let startedAt: Date
    /// 이 포모도로를 시작할 때 고른 카테고리.
    let category: String
    let score: FocusScore
    /// 이 세션에서 카테고리별로 실제 쓴 시간. 짝 제안 후보를 찾는 데 쓴다.
    let categorySeconds: [String: Int]
}

/// "이 카테고리로 집중할 때 사실은 저 카테고리 앱을 쓰고 있다" 는 관찰.
struct FocusPairSuggestion: Equatable {
    let category: String
    let partner: String
    /// 그 카테고리가 차지한 비율(0...1).
    let share: Double
}

enum FocusPairSuggester {
    /// 이만큼은 차지해야 "사실상 같이 하는 일" 로 본다.
    static let minimumShare = 0.20

    /// 집중 카테고리와 실제 쓰는 앱의 카테고리가 어긋나면 몰입도는 낮게 나오지만 딴짓이 아니다.
    /// (예: 공부로 포모도로를 걸고 에디터로 공부하기)
    /// 판정 기준을 느슨하게 만드는 것으로 덮지 말고 짝으로 묶어 지표 자체를 바로잡게 안내한다.
    static func suggestion(
        category: String,
        samples: [FocusScoreSample],
        isPaired: (String, String) -> Bool
    ) -> FocusPairSuggestion? {
        var secondsByCategory: [String: Int] = [:]
        for sample in samples where sample.category == category {
            for (name, seconds) in sample.categorySeconds {
                secondsByCategory[name, default: 0] += max(0, seconds)
            }
        }

        let total = secondsByCategory.values.reduce(0, +)
        guard total > 0 else { return nil }

        let candidate = secondsByCategory
            // 미분류·생산성 관리 같은 예약 카테고리는 짝이 될 수 없다.
            // 짝 편집 화면은 사용자 카테고리에서만 고르게 해 이걸 막는데, 자동 제안이 그 관문을
            // 우회하면 "업무 ↔ 미분류" 가 묶여 앞으로 매핑 안 된 앱이 전부 몰입으로 계산된다.
            .filter {
                $0.key != category
                    && !Constants.reservedCategoryNames.contains($0.key)
                    && !isPaired(category, $0.key)
            }
            // 같은 시간이면 이름순으로 골라 실행할 때마다 제안이 바뀌지 않게 한다.
            .max { lhs, rhs in
                lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key
            }
        guard let candidate else { return nil }

        let share = Double(candidate.value) / Double(total)
        guard share >= minimumShare else { return nil }
        return FocusPairSuggestion(category: category, partner: candidate.key, share: share)
    }

    /// 가장 크게 어긋난 카테고리 하나.
    ///
    /// 전체 보기에서도 보여줘야 한다. 어긋난 카테고리 하나가 전체 몰입도를 바닥까지 끌어내리는데,
    /// 그 사실이 카테고리를 골라봐야만 드러나면 사용자는 원인을 영영 못 찾는다.
    static func strongestSuggestion(
        samples: [FocusScoreSample],
        isPaired: (String, String) -> Bool
    ) -> FocusPairSuggestion? {
        Set(samples.map(\.category))
            .compactMap { suggestion(category: $0, samples: samples, isPaired: isPaired) }
            .max { lhs, rhs in
                lhs.share != rhs.share ? lhs.share < rhs.share : lhs.category > rhs.category
            }
    }
}

enum FocusScoreCalculator {
    /// 세션 관측 한 장에서 몰입도를 뽑는다.
    ///
    /// 짝 판정을 주입받는 이유는 `CategoryPairStore` 싱글턴 없이 테스트하기 위해서다.
    static func score(
        observation: PomodoroSessionObservation,
        focusCategory: String,
        isPaired: (String, String) -> Bool
    ) -> FocusScore {
        var focusSeconds = 0
        var unknownSeconds = 0
        for entry in observation.categories {
            let seconds = max(0, entry.durationSeconds)
            if entry.category == Constants.unclassifiedAppCategory {
                unknownSeconds += seconds
            } else if entry.category == focusCategory || isPaired(focusCategory, entry.category) {
                focusSeconds += seconds
            }
        }

        let totalSeconds = max(0, observation.sessionSeconds)
        return FocusScore(
            focusSeconds: focusSeconds,
            measuredSeconds: max(0, totalSeconds - unknownSeconds),
            totalSeconds: totalSeconds,
            classifiedAppSeconds: observation.classifiedAppSeconds,
            recordedAppSeconds: observation.attributedSeconds
        )
    }
}

enum FocusNudgeDetectionMode: String {
    case personalized
    case ruleBased
}

enum FocusNudgeFrequencyMode: String {
    case unlimited
    case limited
}

/// 최근 10분 한 창에 적용할 설명 가능한 규칙.
///
/// 두 조건은 OR 이다. 몰입 시간이 부족하거나 앱을 너무 자주 옮겨 다닌 경우 중 하나만
/// 만족해도 위반으로 본다.
struct FocusNudgeDetectionRule: Equatable {
    static let focusRatioRange: ClosedRange<Double> = 0.05...0.95
    static let appSwitchRange: ClosedRange<Int> = 0...100

    let minimumFocusRatio: Double
    let maximumAppSwitches: Int

    init(minimumFocusRatio: Double, maximumAppSwitches: Int) {
        self.minimumFocusRatio = min(
            Self.focusRatioRange.upperBound,
            max(Self.focusRatioRange.lowerBound, minimumFocusRatio)
        )
        self.maximumAppSwitches = min(
            Self.appSwitchRange.upperBound,
            max(Self.appSwitchRange.lowerBound, maximumAppSwitches)
        )
    }
}

enum FocusNudgePolicySource: String, Equatable {
    case ruleBased
    case personalized

    var thresholdLabel: String {
        switch self {
        case .ruleBased: return "설정 기준"
        case .personalized: return "개인 기준"
        }
    }
}

struct FocusNudgePolicy: Equatable {
    let source: FocusNudgePolicySource
    let rule: FocusNudgeDetectionRule
    /// nil 이면 세션당 상한이 없다. 같은 위반 상태에서는 한 번만 말하고 회복해야 재활성화된다.
    let maximumNudgesPerSession: Int?
}

/// 최근 10분의 실제 관측값. 창이 온전히 쌓이지 않았으면 이 값 자체를 만들지 않는다.
struct FocusNudgeWindowMetrics: Equatable {
    let score: FocusScore
    let appSwitchCount: Int
}

struct FocusRatioViolation: Equatable {
    let observed: Double
    let minimum: Double
}

struct FocusAppSwitchViolation: Equatable {
    let observed: Int
    let maximum: Int
}

struct FocusNudgeViolation: Equatable {
    let focusRatio: FocusRatioViolation?
    let appSwitches: FocusAppSwitchViolation?

    var isEmpty: Bool { focusRatio == nil && appSwitches == nil }
}

enum FocusNudgeDetector {
    /// 최근 창의 관측값이 어느 기준을 넘었는지 사실만 돌려준다.
    static func violation(
        metrics: FocusNudgeWindowMetrics,
        rule: FocusNudgeDetectionRule
    ) -> FocusNudgeViolation {
        let focusViolation = metrics.score.isMeasurable
            && metrics.score.value < rule.minimumFocusRatio
            ? FocusRatioViolation(
                observed: metrics.score.value,
                minimum: rule.minimumFocusRatio
            )
            : nil
        let switchViolation = metrics.appSwitchCount > rule.maximumAppSwitches
            ? FocusAppSwitchViolation(
                observed: metrics.appSwitchCount,
                maximum: rule.maximumAppSwitches
            )
            : nil
        return FocusNudgeViolation(
            focusRatio: focusViolation,
            appSwitches: switchViolation
        )
    }

    /// 위반이 계속되는 동안은 다시 말하지 않는다. 정상 창을 한 번 확인해야 다음 위반이 새로 열린다.
    static func shouldNudge(
        isFocusing: Bool,
        violation: FocusNudgeViolation,
        isViolationLatched: Bool,
        nudgeCount: Int,
        maximumNudgesPerSession: Int?
    ) -> Bool {
        guard isFocusing, !violation.isEmpty, !isViolationLatched else { return false }
        guard let maximumNudgesPerSession else { return true }
        return nudgeCount < max(1, maximumNudgesPerSession)
    }
}

enum FocusScoreMessages {
    /// 등록한 멘트가 없을 때 쓰는 문구. 다그치지 않고 부드럽게 묻는다.
    static let fallback = [
        "지금 하려던 일, 아직 그거 맞아요?",
        "잠깐만요. 원래 하던 일로 돌아가 볼까요?",
        "집중이 조금 흩어진 것 같아요. 괜찮아요?",
    ]

    /// 설정에 적어둔 멘트를 한 줄에 하나씩 끊는다.
    static func parse(_ raw: String) -> [String] {
        raw
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// 직전에 쓴 문구 다음 것을 고른다. 같은 말이 연달아 나오면 잔소리로 들린다.
    static func next(from messages: [String], previous: String?) -> String? {
        let pool = messages.isEmpty ? fallback : messages
        guard let first = pool.first else { return nil }
        guard pool.count > 1,
              let previous,
              let index = pool.firstIndex(of: previous) else {
            return first
        }
        return pool[(index + 1) % pool.count]
    }

    /// 무엇이 얼마만큼 기준을 넘었는지 먼저 말하고 사용자가 고른 문구를 이어 붙인다.
    static func explained(
        baseMessage: String,
        violation: FocusNudgeViolation,
        source: FocusNudgePolicySource
    ) -> String {
        var reasons: [String] = []
        if let focusRatio = violation.focusRatio {
            reasons.append(
                "최근 10분 몰입 시간이 \(Int((focusRatio.observed * 100).rounded()))%로 "
                    + "\(source.thresholdLabel) \(Int((focusRatio.minimum * 100).rounded()))%보다 낮아요."
            )
        }
        if let appSwitches = violation.appSwitches {
            reasons.append(
                "최근 10분 앱 전환이 \(appSwitches.observed)회로 "
                    + "\(source.thresholdLabel) \(appSwitches.maximum)회를 넘었어요."
            )
        }
        return (reasons + [baseMessage]).joined(separator: " ")
    }
}
