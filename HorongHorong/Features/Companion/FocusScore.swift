import Foundation

/// 집중 세션 한 건의 몰입도.
///
/// 정의는 한 줄이다 — **하기로 한 일에 쓴 시간 ÷ 세션 전체 시간**.
/// 자리를 비웠거나 기록되지 않은 시간도 분모에 남는다. 포모도로 25분은 책상에 있기로 한 시간이므로
/// 자리를 비운 것도 몰입하지 않은 것으로 센다.
struct FocusScore: Equatable {
    /// 집중 카테고리 + 짝 카테고리에 쓴 시간.
    let focusSeconds: Int
    /// 세션 전체 시간.
    let totalSeconds: Int

    static let zero = FocusScore(focusSeconds: 0, totalSeconds: 0)

    /// 0...1. 잴 시간이 없으면 0.
    var value: Double {
        guard totalSeconds > 0 else { return 0 }
        return min(1, max(0, Double(focusSeconds) / Double(totalSeconds)))
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
    /// 기준선을 낮추는 것으로 덮지 말고 짝으로 묶어 지표 자체를 바로잡게 안내한다.
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
            .filter { $0.key != category && !isPaired(category, $0.key) }
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
    /// 전체 보기에서도 보여줘야 한다. 어긋난 카테고리 하나가 전체 기준선을 바닥까지 끌어내리는데,
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
        let focusSeconds = observation.categories
            .filter { $0.category == focusCategory || isPaired(focusCategory, $0.category) }
            .reduce(0) { $0 + max(0, $1.durationSeconds) }

        return FocusScore(
            focusSeconds: focusSeconds,
            totalSeconds: max(0, observation.sessionSeconds)
        )
    }
}

enum FocusScoreThreshold {
    /// 과거 기록이 없을 때 쓸 기준선.
    static let fallback = 0.60
    /// 선이 그래프 밖으로 나가면 다시 잡을 수 없다. 위아래로 여백을 남긴다.
    static let range: ClosedRange<Double> = 0.05...0.95

    static func clamped(_ value: Double) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }

    /// 첫 기준선. 과거 몰입도의 하위 25% 지점을 잡아 "평소보다 안 되는 날" 만 걸리게 한다.
    /// 평균을 쓰면 절반이 걸려 잔소리가 일상이 된다.
    static func percentileDefault(_ scores: [Double]) -> Double {
        guard !scores.isEmpty else { return fallback }
        let sorted = scores.sorted()
        // nearest-rank. 표본이 하나면 그 값이 그대로 기준이 된다.
        let rank = Int((0.25 * Double(sorted.count)).rounded(.up))
        let index = min(sorted.count - 1, max(0, rank - 1))
        return clamped(sorted[index])
    }

    /// 이 기준이었다면 몇 번 걸렸을지. 선 위에 정확히 걸친 값은 세지 않는다.
    static func belowCount(_ scores: [Double], threshold: Double) -> Int {
        scores.filter { $0 < threshold }.count
    }
}

/// 판정에 필요한 전부. 조건이 이 다섯 줄을 넘지 않아야 사용자가 설명을 듣고 납득한다.
struct FocusScoreNudgeInput: Equatable {
    let isFocusing: Bool
    let elapsedSeconds: TimeInterval
    let score: Double
    let threshold: Double
    /// 이번 세션에서 이미 말을 걸었는지.
    let hasNudgedThisSession: Bool
}

enum FocusScoreDetector {
    /// 세션 초반에는 분모가 작아 앱 하나만 잘못 잡아도 0% 가 된다. 그때까지는 보지 않는다.
    static let warmUpSeconds: TimeInterval = 5 * 60

    /// 규칙은 하나다 — 5분이 지난 뒤 몰입도가 기준선 아래로 떨어지면, 세션당 한 번.
    static func shouldNudge(_ input: FocusScoreNudgeInput) -> Bool {
        guard input.isFocusing else { return false }
        guard !input.hasNudgedThisSession else { return false }
        guard input.elapsedSeconds >= warmUpSeconds else { return false }
        return input.score < input.threshold
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
}
