import Foundation
import SwiftData

/// `StatsRecordRepository` 의 SwiftData 구현.
@MainActor
final class SwiftDataStatsRecordRepository: StatsRecordRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func recordCount(start: Date, end: Date) -> Int {
        count(FetchDescriptor<AppUsageRecord>(predicate: #Predicate { $0.date >= start && $0.date < end }))
            + count(FetchDescriptor<AppUsageSegment>(predicate: #Predicate { $0.startTime >= start && $0.startTime < end }))
            + count(FetchDescriptor<FocusSession>(predicate: #Predicate { $0.startedAt >= start && $0.startedAt < end }))
            + count(FetchDescriptor<AttentionEvent>(predicate: #Predicate { $0.occurredAt >= start && $0.occurredAt < end }))
            + count(FetchDescriptor<AttentionDaySummary>(predicate: #Predicate { $0.day >= start && $0.day < end }))
    }

    func deleteRecords(start: Date, end: Date) throws {
        do {
            for record in try context.fetch(
                FetchDescriptor<AppUsageRecord>(predicate: #Predicate { $0.date >= start && $0.date < end })
            ) {
                context.delete(record)
            }
            for segment in try context.fetch(
                FetchDescriptor<AppUsageSegment>(predicate: #Predicate { $0.startTime >= start && $0.startTime < end })
            ) {
                context.delete(segment)
            }

            // 집중 세션을 지우면 그 세션이 완료로 찍어 둔 할 일도 되돌려야 한다.
            // 같은 할 일이 여러 세션에 걸릴 수 있어 id 로 모은다.
            var affectedMemosByID: [UUID: Todo] = [:]
            for session in try context.fetch(
                FetchDescriptor<FocusSession>(predicate: #Predicate { $0.startedAt >= start && $0.startedAt < end })
            ) {
                if let record = try PomodoroSessionDeletion.delete(session, modelContext: context) {
                    affectedMemosByID[record.id] = record
                }
            }

            for event in try context.fetch(
                FetchDescriptor<AttentionEvent>(predicate: #Predicate { $0.occurredAt >= start && $0.occurredAt < end })
            ) {
                context.delete(event)
            }
            for summary in try context.fetch(
                FetchDescriptor<AttentionDaySummary>(predicate: #Predicate { $0.day >= start && $0.day < end })
            ) {
                context.delete(summary)
            }

            try context.save()
            NotificationCenter.default.post(name: .pomodoroReflectionDidChange, object: nil)
            for record in affectedMemosByID.values {
                PomodoroTaskCompletionRecorder.applyPostSaveEffects(to: record, modelContext: context)
            }
        } catch {
            // 다섯 종류 중 일부만 지워진 상태를 만들지 않는다.
            context.rollback()
            throw error
        }
    }

    func focusPersonalization(requiredFeedbackCount: Int) -> FocusPersonalizationAnalysis? {
        FocusPersonalizationTrainer.analyze(
            requiredFeedbackCount: requiredFeedbackCount,
            modelContext: context
        )
    }

    func focusScoreSamples() -> [FocusScoreSample] {
        FocusScoreHistory.samples(modelContext: context)
    }

    func focusScoreSamples(days: Int) -> [FocusScoreSample] {
        FocusScoreHistory.samples(days: days, modelContext: context)
    }

    func nudgeFiredDates(days: Int) -> [Date] {
        guard let periodStart = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else {
            return []
        }
        let descriptor = FetchDescriptor<FocusNudgeEvent>(
            predicate: #Predicate { $0.firedAt >= periodStart },
            sortBy: [SortDescriptor(\.firedAt)]
        )
        return ((try? context.fetch(descriptor)) ?? []).map(\.firedAt)
    }

    @discardableResult
    func resetSessionMarkerColors(for category: String) -> Int {
        (try? FocusSession.resetMarkerColors(for: category, in: context)) ?? 0
    }

    private func count<T>(_ descriptor: FetchDescriptor<T>) -> Int {
        (try? context.fetchCount(descriptor)) ?? 0
    }
}
