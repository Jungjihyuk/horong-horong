import Foundation

/// `SleepGateway` 의 건강 앱 구현. `HealthSleepStore` 를 감싸기만 한다.
///
/// 얇은 것이 목적이다 — 여기에 규칙을 두면 다시 테스트할 수 없는 자리로 돌아간다.
@MainActor
struct HealthSleepGateway: SleepGateway {
    private let store: HealthSleepStore

    init(store: HealthSleepStore = .shared) {
        self.store = store
    }

    var isAvailable: Bool { store.isAvailable }

    func sleepHours(on day: Date, calendar: Calendar) async -> Double? {
        await store.sleepHours(on: day, calendar: calendar)
    }
}
