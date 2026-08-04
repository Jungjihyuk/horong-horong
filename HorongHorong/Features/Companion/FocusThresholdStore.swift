import Foundation
import Observation

/// 카테고리별 몰입 기준선.
///
/// 일의 성격에 따라 몰입도가 구조적으로 다르다. 한 앱에 오래 머무는 개발은 높게 나오고,
/// 여러 앱을 오가는 조사나 기록은 낮게 나온다. 기준선이 하나뿐이면 한쪽은 늘 걸리고
/// 다른 쪽은 영영 걸리지 않는다.
///
/// 카테고리 값이 없으면 전체 기준선으로 내려간다. 처음 쓰는 카테고리에도 무언가는 적용돼야 한다.
@Observable
final class FocusThresholdStore: @unchecked Sendable {
    static let shared = FocusThresholdStore()

    private static let categoryKeyPrefix = "companion.focusScoreThreshold."

    private init() {}

    static func userDefaultsKey(for category: String) -> String {
        categoryKeyPrefix + category
    }

    /// 모든 카테고리가 함께 쓰는 기준선.
    var overall: Double {
        get {
            let key = Constants.AppStorageKey.companionFocusScoreThreshold
            guard UserDefaults.standard.object(forKey: key) != nil else {
                return FocusScoreThreshold.fallback
            }
            return FocusScoreThreshold.clamped(UserDefaults.standard.double(forKey: key))
        }
        set {
            UserDefaults.standard.set(
                FocusScoreThreshold.clamped(newValue),
                forKey: Constants.AppStorageKey.companionFocusScoreThreshold
            )
        }
    }

    /// 이 카테고리에 적용할 기준선. 따로 정한 값이 없으면 전체 기준선.
    func threshold(for category: String?) -> Double {
        guard let category, hasCustomThreshold(for: category) else { return overall }
        return FocusScoreThreshold.clamped(
            UserDefaults.standard.double(forKey: Self.userDefaultsKey(for: category))
        )
    }

    func hasCustomThreshold(for category: String) -> Bool {
        UserDefaults.standard.object(forKey: Self.userDefaultsKey(for: category)) != nil
    }

    func setThreshold(_ value: Double, for category: String) {
        UserDefaults.standard.set(
            FocusScoreThreshold.clamped(value),
            forKey: Self.userDefaultsKey(for: category)
        )
    }

    /// 이 카테고리만 전체 기준선을 따르도록 되돌린다.
    func resetThreshold(for category: String) {
        UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey(for: category))
    }

    /// 카테고리 이름이 바뀌면 기준선도 따라가야 한다.
    func renameCategory(from oldName: String, to newName: String) {
        guard hasCustomThreshold(for: oldName) else { return }
        let value = UserDefaults.standard.double(forKey: Self.userDefaultsKey(for: oldName))
        UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey(for: oldName))
        UserDefaults.standard.set(value, forKey: Self.userDefaultsKey(for: newName))
    }

    func removeCategory(_ category: String) {
        UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey(for: category))
    }
}
