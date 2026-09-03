import Foundation

@Observable
final class IdleThresholdStore: @unchecked Sendable {
    static let shared = IdleThresholdStore()

    private var secondsByCategory: [String: Int] = [:]

    private init() {
        for category in Constants.allCategories {
            let key = Self.userDefaultsKey(for: category)
            let stored = UserDefaults.standard.integer(forKey: key)
            if stored > 0 {
                secondsByCategory[category] = stored
            } else {
                secondsByCategory[category] = Self.defaultSeconds(for: category)
            }
        }
    }

    static func userDefaultsKey(for category: String) -> String {
        Constants.idleThresholdUserDefaultsPrefix + category
    }

    func seconds(for category: String) -> Int {
        secondsByCategory[category] ?? Self.defaultSeconds(for: category)
    }

    func minutes(for category: String) -> Int {
        max(1, seconds(for: category) / 60)
    }

    func setMinutes(_ minutes: Int, for category: String) {
        let clamped = max(1, min(minutes, 180))
        let seconds = clamped * 60
        secondsByCategory[category] = seconds
        UserDefaults.standard.set(seconds, forKey: Self.userDefaultsKey(for: category))
    }

    func resetToDefault(category: String) {
        let defaultSeconds = Self.defaultSeconds(for: category)
        secondsByCategory[category] = defaultSeconds
        UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey(for: category))
    }

    private static func defaultSeconds(for category: String) -> Int {
        let defaultName = Constants.defaultName(forCategory: category)
        return Constants.defaultIdleThresholdSeconds[defaultName]
            ?? Constants.defaultIdleThresholdSeconds[category]
            ?? Constants.fallbackIdleThresholdSeconds
    }
}
