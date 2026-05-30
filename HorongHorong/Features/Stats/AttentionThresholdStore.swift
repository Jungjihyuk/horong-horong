import Foundation
import Observation

enum AttentionSensitivity: String, CaseIterable, Identifiable {
    case lenient
    case standard
    case sensitive

    var id: String { rawValue }
}

struct AttentionThresholds: Equatable {
    var distractionMinSeconds: TimeInterval
    var returnDelaySeconds: TimeInterval
    var earlyStopRatio: Double
    var sensitivity: AttentionSensitivity

    static let standard = AttentionThresholds(
        distractionMinSeconds: 30,
        returnDelaySeconds: 10 * 60,
        earlyStopRatio: 0.70,
        sensitivity: .standard
    )

    static func defaults(for sensitivity: AttentionSensitivity) -> AttentionThresholds {
        switch sensitivity {
        case .lenient:
            return AttentionThresholds(
                distractionMinSeconds: 60,
                returnDelaySeconds: 15 * 60,
                earlyStopRatio: 0.50,
                sensitivity: sensitivity
            )
        case .standard:
            return .standard
        case .sensitive:
            return AttentionThresholds(
                distractionMinSeconds: 10,
                returnDelaySeconds: 5 * 60,
                earlyStopRatio: 0.85,
                sensitivity: sensitivity
            )
        }
    }
}

@Observable
final class AttentionThresholdStore: @unchecked Sendable {
    static let shared = AttentionThresholdStore()

    private let sensitivityKey = "attention.sensitivity"
    private let distractionMinSecondsKey = "attention.distractionMinSeconds"
    private let returnDelaySecondsKey = "attention.returnDelaySeconds"
    private let earlyStopRatioKey = "attention.earlyStopRatio"
    private let distractionCategoriesKey = "attention.distractionDefaultCategories"

    var sensitivity: AttentionSensitivity {
        didSet {
            UserDefaults.standard.set(sensitivity.rawValue, forKey: sensitivityKey)
            applyDefaults(for: sensitivity)
        }
    }

    var distractionMinSeconds: TimeInterval {
        didSet { UserDefaults.standard.set(distractionMinSeconds, forKey: distractionMinSecondsKey) }
    }

    var returnDelaySeconds: TimeInterval {
        didSet { UserDefaults.standard.set(returnDelaySeconds, forKey: returnDelaySecondsKey) }
    }

    var earlyStopRatio: Double {
        didSet { UserDefaults.standard.set(earlyStopRatio, forKey: earlyStopRatioKey) }
    }

    private(set) var distractionDefaultCategoryNames: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(distractionDefaultCategoryNames).sorted(), forKey: distractionCategoriesKey)
        }
    }

    var thresholds: AttentionThresholds {
        AttentionThresholds(
            distractionMinSeconds: distractionMinSeconds,
            returnDelaySeconds: returnDelaySeconds,
            earlyStopRatio: earlyStopRatio,
            sensitivity: sensitivity
        )
    }

    private init() {
        let defaults = UserDefaults.standard
        let rawSensitivity = defaults.string(forKey: sensitivityKey)
        let resolvedSensitivity = rawSensitivity.flatMap(AttentionSensitivity.init(rawValue:)) ?? .standard
        let fallback = AttentionThresholds.defaults(for: resolvedSensitivity)

        sensitivity = resolvedSensitivity
        distractionMinSeconds = defaults.object(forKey: distractionMinSecondsKey) as? TimeInterval ?? fallback.distractionMinSeconds
        returnDelaySeconds = defaults.object(forKey: returnDelaySecondsKey) as? TimeInterval ?? fallback.returnDelaySeconds
        earlyStopRatio = defaults.object(forKey: earlyStopRatioKey) as? Double ?? fallback.earlyStopRatio
        if let saved = defaults.array(forKey: distractionCategoriesKey) as? [String], !saved.isEmpty {
            distractionDefaultCategoryNames = Set(saved)
        } else {
            distractionDefaultCategoryNames = ["소통", "엔터"]
        }
    }

    private func applyDefaults(for sensitivity: AttentionSensitivity) {
        let defaults = AttentionThresholds.defaults(for: sensitivity)
        distractionMinSeconds = defaults.distractionMinSeconds
        returnDelaySeconds = defaults.returnDelaySeconds
        earlyStopRatio = defaults.earlyStopRatio
    }

    func isDistractionCategory(_ category: String) -> Bool {
        let defaultName = Constants.defaultName(forCategory: category)
        return distractionDefaultCategoryNames.contains(defaultName)
    }

    func setDistractionCategory(_ category: String, isEnabled: Bool) {
        let defaultName = Constants.defaultName(forCategory: category)
        if isEnabled {
            distractionDefaultCategoryNames.insert(defaultName)
        } else {
            distractionDefaultCategoryNames.remove(defaultName)
        }
    }

    func resetDistractionCategories() {
        distractionDefaultCategoryNames = ["소통", "엔터"]
    }
}
