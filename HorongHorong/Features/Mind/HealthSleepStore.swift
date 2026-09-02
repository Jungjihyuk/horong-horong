import Foundation
import HealthKit

@MainActor
final class HealthSleepStore {
    static let shared = HealthSleepStore()

    private let store = HKHealthStore()

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func sleepHours(on day: Date, calendar: Calendar = .current) async -> Double? {
        guard isAvailable,
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return nil
        }

        do {
            try await store.requestAuthorization(toShare: [], read: [sleepType])
        } catch {
            return nil
        }

        let window = HealthSleepMath.window(forDay: day, calendar: calendar)
        let predicate = HKQuery.predicateForSamples(
            withStart: window.start,
            end: window.end,
            options: .strictStartDate
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )

        do {
            let samples = try await descriptor.result(for: store)
            let mapped = samples.map {
                (start: $0.startDate, end: $0.endDate, value: $0.value)
            }
            return HealthSleepMath.hours(from: mapped, window: window)
        } catch {
            return nil
        }
    }
}
