import SwiftUI

/// 미리알림 목록 색. 칩 전체를 칠하지 않고 점 + 연한 배경만 써서 호롱 톤을 유지한다.
enum ReminderListSwatch: String, CaseIterable, Identifiable {
    case clay
    case amber
    case moss
    case teal
    case rose
    case sand
    case cocoa
    case slate

    var id: String { rawValue }

    var label: String {
        switch self {
        case .clay: return "흙"
        case .amber: return "호박"
        case .moss: return "이끼"
        case .teal: return "청록"
        case .rose: return "장미"
        case .sand: return "모래"
        case .cocoa: return "밤"
        case .slate: return "먹"
        }
    }

    var dot: Color {
        Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    var wash: Color {
        dot.opacity(0.18)
    }

    var ink: Color {
        Color(red: rgb.0 * 0.62, green: rgb.1 * 0.55, blue: rgb.2 * 0.48)
    }

    private var rgb: (Double, Double, Double) {
        switch self {
        case .clay: return (0.72, 0.42, 0.28)
        case .amber: return (0.78, 0.55, 0.22)
        case .moss: return (0.46, 0.58, 0.34)
        case .teal: return (0.32, 0.54, 0.52)
        case .rose: return (0.70, 0.40, 0.42)
        case .sand: return (0.70, 0.58, 0.40)
        case .cocoa: return (0.52, 0.36, 0.28)
        case .slate: return (0.42, 0.46, 0.52)
        }
    }

    static func automatic(for id: String) -> ReminderListSwatch {
        let cases = allCases
        let index = id.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        return cases[(index & Int.max) % cases.count]
    }
}

@MainActor
final class ReminderListColorStore: ObservableObject {
    static let shared = ReminderListColorStore()

    @Published private var overrides: [String: String]

    private init() {
        overrides = Self.load()
    }

    func swatch(for id: String) -> ReminderListSwatch {
        if let raw = overrides[id], let swatch = ReminderListSwatch(rawValue: raw) {
            return swatch
        }
        return ReminderListSwatch.automatic(for: id)
    }

    func set(_ swatch: ReminderListSwatch, for id: String) {
        overrides[id] = swatch.rawValue
        save()
    }

    func reset(_ id: String) {
        overrides.removeValue(forKey: id)
        save()
    }

    func isOverridden(_ id: String) -> Bool {
        overrides[id] != nil
    }

    private func save() {
        if let data = try? JSONEncoder().encode(overrides) {
            UserDefaults.standard.set(data, forKey: Constants.AppStorageKey.todoReminderListColors)
        }
    }

    private static func load() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: Constants.AppStorageKey.todoReminderListColors),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return map
    }
}
