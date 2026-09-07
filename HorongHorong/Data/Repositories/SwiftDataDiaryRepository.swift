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
        return try entries(from: range.start, to: range.end)
    }

    func entries(from start: Date, to end: Date) throws -> [DiaryDay] {
        let descriptor = FetchDescriptor<Diary>(
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
    func setMood(on day: Date, slot: DiaryMoodSlot, mood: DiaryMood?) throws -> DiaryDay {
        try upsert(day) { entry in
            entry.setMood(mood, in: slot)
            // 감정을 지우면 그 칸의 나머지도 함께 비운다. 화면이 두 번 나눠 지우게 하면
            // 그 사이에 «감정 없는 원인» 이 남는 순간이 생긴다.
            guard mood == nil else { return }
            entry.setCause(nil, in: slot)
            entry.setIntensity(nil, in: slot)
        }
    }

    @discardableResult
    func setCause(on day: Date, slot: DiaryMoodSlot, cause: DiaryCause?) throws -> DiaryDay {
        try upsert(day) { $0.setCause(cause, in: slot) }
    }

    @discardableResult
    func setIntensity(on day: Date, slot: DiaryMoodSlot, intensity: Int?) throws -> DiaryDay {
        try upsert(day) { $0.setIntensity(intensity, in: slot) }
    }

    @discardableResult
    func setStress(on day: Date, stress: Int?) throws -> DiaryDay {
        try upsert(day) { $0.stress = stress }
    }

    @discardableResult
    func setSleep(on day: Date, window: DiarySleepWindow?, source: DiarySleepSource) throws -> DiaryDay {
        try upsert(day) {
            // 넷은 항상 함께 움직인다. 하나만 남으면 «시각 없는 길이» 나 «길이 없는 시각» 이 생겨
            // 그래프가 어느 쪽을 믿어야 할지 알 수 없다.
            $0.sleepHours = window?.hours
            $0.sleepStart = window?.start
            $0.sleepEnd = window?.end
            $0.sleepSource = window == nil ? nil : source
        }
    }

    // MARK: - 내부

    /// **저장 직전에 저장소에 다시 물어본다.** 화면이 들고 있던 값은 방금 만든 항목을
    /// 아직 모를 수 있고, 그 틈에 같은 날짜를 또 만들면 중복이 생긴다.
    /// 이미 생긴 중복은 실행 시 `mergeDuplicateDiaryEntries` 가 정리한다.
    private func upsert(_ day: Date, _ change: (Diary) -> Void) throws -> DiaryDay {
        let normalized = calendar.startOfDay(for: day)
        let entry: Diary
        if let existing = try find(normalized) {
            entry = existing
        } else {
            entry = Diary(day: normalized, calendar: calendar)
            context.insert(entry)
        }
        change(entry)
        entry.updatedAt = Date()
        try context.save()
        return Self.toDay(entry)
    }

    private func find(_ day: Date) throws -> Diary? {
        var descriptor = FetchDescriptor<Diary>(predicate: #Predicate { $0.day == day })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func monthRange(of date: Date) -> (start: Date, end: Date)? {
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let start = calendar.date(from: components),
              let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
        return (start, end)
    }

    private static func toDay(_ entry: Diary) -> DiaryDay {
        DiaryDay(
            day: entry.day,
            body: entry.body,
            stress: entry.stress,
            sleepHours: entry.sleepHours,
            sleepSource: entry.sleepSource,
            moodRecords: entry.moodRecords,
            sleepStart: entry.sleepStart,
            sleepEnd: entry.sleepEnd
        )
    }
}
