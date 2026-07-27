import Foundation
import SwiftData

@Model
final class AppUsageRecord {
    var id: UUID
    var appName: String
    var bundleIdentifier: String
    var category: String
    var date: Date
    var durationSeconds: Int

    init(appName: String, bundleIdentifier: String, category: String, date: Date) {
        self.id = UUID()
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.category = category
        self.date = Calendar.current.startOfDay(for: date)
        self.durationSeconds = 0
    }
}

enum AppUsageRecordStore {
    static func applyDelta(
        bundleIdentifier: String,
        appName: String,
        category: String,
        date: Date,
        deltaSeconds: Int,
        modelContext: ModelContext
    ) throws {
        guard deltaSeconds != 0 else { return }

        let dayStart = Calendar.current.startOfDay(for: date)
        let targetBundleIdentifier = bundleIdentifier
        let targetCategory = category
        let descriptor = FetchDescriptor<AppUsageRecord>(
            predicate: #Predicate {
                $0.bundleIdentifier == targetBundleIdentifier
                    && $0.category == targetCategory
                    && $0.date == dayStart
            }
        )
        let matchingRecords = try modelContext.fetch(descriptor)
        let newTotal = max(
            0,
            matchingRecords.reduce(0) { $0 + $1.durationSeconds } + deltaSeconds
        )

        guard newTotal > 0 else {
            for record in matchingRecords {
                modelContext.delete(record)
            }
            return
        }

        if let primaryRecord = matchingRecords.first {
            primaryRecord.appName = appName
            primaryRecord.durationSeconds = newTotal
            for duplicate in matchingRecords.dropFirst() {
                modelContext.delete(duplicate)
            }
        } else {
            let record = AppUsageRecord(
                appName: appName,
                bundleIdentifier: bundleIdentifier,
                category: category,
                date: dayStart
            )
            record.durationSeconds = newTotal
            modelContext.insert(record)
        }
    }
}
