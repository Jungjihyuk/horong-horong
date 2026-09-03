import Foundation
import SwiftData

/// `DiaryRepository` 의 SwiftData 구현.
@MainActor
final class SwiftDataDiaryRepository: DiaryRepository {
    private let context: ModelContext
    private let calendar: Calendar

    init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    func entries(inMonthOf date: Date) throws -> [DiaryDay] {
        guard let range = monthRange(of: date) else { return [] }
        let start = range.start
        let end = range.end
        let descriptor = FetchDescriptor<DiaryEntry>(
            predicate: #Predicate { $0.day >= start && $0.day < end },
            sortBy: [SortDescriptor(\.day, order: .reverse)]
        )
        return try context.fetch(descriptor).map(Self.toDay)
    }

    func entry(on day: Date) throws -> DiaryDay? {
        try find(calendar.startOfDay(for: day)).map(Self.toDay)
    }

    @discardableResult
    func setBody(on day: Date, body: String) throws -> DiaryDay {
        try upsert(day) { $0.body = body }
    }

    @discardableResult
    func setMood(on day: Date, mood: DiaryMood?) throws -> DiaryDay {
        try upsert(day) { $0.mood = mood }
    }

    @discardableResult
    func setStress(on day: Date, stress: Int?) throws -> DiaryDay {
        try upsert(day) { $0.stress = stress }
    }

    @discardableResult
    func setSleep(on day: Date, hours: Double, source: DiarySleepSource) throws -> DiaryDay {
        try upsert(day) {
            $0.sleepHours = hours
            $0.sleepSource = source
        }
    }

    // MARK: - 내부

    /// **저장 직전에 저장소에 다시 물어본다.** 화면이 들고 있던 값은 방금 만든 항목을
    /// 아직 모를 수 있고, 그 틈에 같은 날짜를 또 만들면 중복이 생긴다.
    /// 이미 생긴 중복은 실행 시 `mergeDuplicateDiaryEntries` 가 정리한다.
    private func upsert(_ day: Date, _ change: (DiaryEntry) -> Void) throws -> DiaryDay {
        let normalized = calendar.startOfDay(for: day)
        let entry: DiaryEntry
        if let existing = try find(normalized) {
            entry = existing
        } else {
            entry = DiaryEntry(day: normalized, calendar: calendar)
            context.insert(entry)
        }
        change(entry)
        entry.updatedAt = Date()
        try context.save()
        return Self.toDay(entry)
    }

    private func find(_ day: Date) throws -> DiaryEntry? {
        var descriptor = FetchDescriptor<DiaryEntry>(predicate: #Predicate { $0.day == day })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func monthRange(of date: Date) -> (start: Date, end: Date)? {
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let start = calendar.date(from: components),
              let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
        return (start, end)
    }

    private static func toDay(_ entry: DiaryEntry) -> DiaryDay {
        DiaryDay(
            day: entry.day,
            body: entry.body,
            mood: entry.mood,
            stress: entry.stress,
            sleepHours: entry.sleepHours,
            sleepSource: entry.sleepSource
        )
    }
}
