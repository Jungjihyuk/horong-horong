import Foundation
import Observation

@MainActor
@Observable
final class StatsRecordEditorViewModel {
    private(set) var segments: [StatsEditableSegment] = []
    private(set) var focusSessions: [StatsEditableFocusSession] = []
    var editError: String?

    private let repository: StatsRecordEditorRepository

    init(repository: StatsRecordEditorRepository) {
        self.repository = repository
    }

    func load(date: Date) {
        do {
            let snapshot = try repository.snapshot(on: date)
            segments = snapshot.segments
            focusSessions = snapshot.focusSessions
        } catch {
            segments = []
            focusSessions = []
            editError = "기록을 불러오지 못했습니다. 잠시 후 다시 시도해 주세요."
        }
    }

    func addSegment(_ draft: SegmentDraft, date: Date) -> Bool {
        guard validateSegment(existingID: nil, draft: draft) else { return false }
        return perform(date: date) {
            try repository.addSegment(segmentDraft(from: draft))
        }
    }

    func updateSegment(id: UUID, draft: SegmentDraft, date: Date) -> Bool {
        guard validateSegment(existingID: id, draft: draft) else { return false }
        return perform(date: date) {
            try repository.updateSegment(id: id, draft: segmentDraft(from: draft))
        }
    }

    func deleteSegment(id: UUID, date: Date) {
        _ = perform(date: date) {
            try repository.deleteSegment(id: id)
        }
    }

    func updateFocusSession(id: UUID, draft: PomodoroDraft, date: Date) -> Bool {
        guard validateFocusSession(id: id, draft: draft) else { return false }
        return perform(date: date) {
            try repository.updateFocusSession(
                id: id,
                draft: StatsFocusSessionDraft(
                    category: draft.category,
                    start: draft.start,
                    end: draft.end
                )
            )
        }
    }

    func deleteFocusSession(id: UUID, date: Date) {
        _ = perform(date: date) {
            try repository.deleteFocusSession(id: id)
        }
    }

    func childSegments(for session: StatsEditableFocusSession) -> [StatsEditableSegment] {
        segments.filter { overlaps($0.start, $0.end, session.start, session.end) }
    }

    private func validateSegment(existingID: UUID?, draft: SegmentDraft) -> Bool {
        let affectedSessions = focusSessions.filter { session in
            let overlapsDraft = overlaps(draft.start, draft.end, session.start, session.end)
            let overlapsExisting = segments.first(where: { $0.id == existingID }).map {
                overlaps($0.start, $0.end, session.start, session.end)
            } ?? false
            return overlapsDraft || overlapsExisting
        }

        for session in affectedSessions {
            let sessionSeconds = Int(session.end.timeIntervalSince(session.start))
            let existingChildSeconds = segments.reduce(0) { total, segment in
                guard segment.id != existingID else { return total }
                return total + overlapSeconds(segment.start, segment.end, session.start, session.end)
            }
            let childSeconds = existingChildSeconds
                + overlapSeconds(draft.start, draft.end, session.start, session.end)
            if childSeconds > sessionSeconds {
                editError = "포모도로 '\(session.category)'의 하위 앱 기록 합계가 집중 시간 \(formatDuration(sessionSeconds))을 넘을 수 없습니다."
                return false
            }
        }
        return true
    }

    private func validateFocusSession(id: UUID, draft: PomodoroDraft) -> Bool {
        guard draft.isValid else {
            editError = "포모도로 종료 시간은 시작 시간보다 늦어야 합니다."
            return false
        }
        if let overlapping = focusSessions.first(where: {
            $0.id != id && overlaps(draft.start, draft.end, $0.start, $0.end)
        }) {
            editError = "다른 포모도로 '\(overlapping.category)' 기록과 시간이 겹칩니다."
            return false
        }

        let sessionSeconds = Int(draft.end.timeIntervalSince(draft.start))
        let childSeconds = segments.reduce(0) {
            $0 + overlapSeconds($1.start, $1.end, draft.start, draft.end)
        }
        if childSeconds > sessionSeconds {
            editError = "하위 앱 기록 합계 \(formatDuration(childSeconds))가 포모도로 시간 \(formatDuration(sessionSeconds))을 넘을 수 없습니다."
            return false
        }
        return true
    }

    private func perform(date: Date, operation: () throws -> Void) -> Bool {
        do {
            try operation()
            load(date: date)
            return true
        } catch StatsRecordEditorError.missingFocusEnd {
            editError = "종료 시간이 없는 포모도로 기록은 수정할 수 없습니다."
        } catch {
            editError = "기록을 저장하지 못했습니다. 잠시 후 다시 시도해 주세요."
        }
        return false
    }

    private func segmentDraft(from draft: SegmentDraft) -> StatsSegmentDraft {
        StatsSegmentDraft(
            appName: draft.appName,
            category: draft.category,
            start: draft.start,
            end: draft.end
        )
    }

    private func overlaps(_ lhsStart: Date, _ lhsEnd: Date, _ rhsStart: Date, _ rhsEnd: Date) -> Bool {
        lhsStart < rhsEnd && lhsEnd > rhsStart
    }

    private func overlapSeconds(_ lhsStart: Date, _ lhsEnd: Date, _ rhsStart: Date, _ rhsEnd: Date) -> Int {
        let start = max(lhsStart, rhsStart)
        let end = min(lhsEnd, rhsEnd)
        return end > start ? Int(end.timeIntervalSince(start)) : 0
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(remainder)s"
    }
}
