import Foundation
import SwiftData

extension Notification.Name {
    static let pomodoroReflectionDidChange = Notification.Name(
        "app.horonghorong.pomodoroReflectionDidChange"
    )
    static let pomodoroSessionDidChange = Notification.Name(
        "app.horonghorong.pomodoroSessionDidChange"
    )
    static let pomodoroLinkedTaskDidComplete = Notification.Name(
        "app.horonghorong.pomodoroLinkedTaskDidComplete"
    )
}

@Model
final class FocusSession {
    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var focusMinutes: Int
    var breakMinutes: Int
    var completed: Bool
    // 사용자가 선택한 통계 카테고리 (nil 이면 미지정 — 과거 기록 호환용)
    var category: String?
    // 성취 목표에 연결된 할 일. 관계 대신 UUID와 제목 스냅샷을 저장해 삭제된 Memo도 설명할 수 있게 한다.
    var linkedMemoID: UUID?
    var taskTitleSnapshot: String?
    /// 집중(focusing) 동안 키보드·마우스 입력이 있었던 초. 유휴(입력 없음) 시간은 빼고 센다.
    /// nil = 이 기능 도입 이전에 만들어진 기록(입력 데이터 없음).
    var inputActiveSeconds: Int?
    /// 일시정지를 제외하고 카운트다운이 실제 진행된 초.
    /// nil = 이 기능 도입 이전에 만들어진 기록.
    var actualFocusSeconds: Int?
    /// 닫힌 일시정지 구간을 JSON 으로 저장한다. nil 은 이 기능 도입 이전 세션이다.
    var pauseIntervalsData: Data?
    /// 현재 일시정지가 시작된 시각. 재개하거나 세션을 끝내면 닫힌 구간으로 옮긴다.
    var pauseStartedAt: Date?
    /// 타이머 만료와 사용자의 기록 후 종료를 구분한다.
    var endKindRawValue: String?
    /// 몰입 지도에서 이 세션 점에 쓸 사용자 지정 색 키. nil = 카테고리 기본색.
    var markerColorKey: String?
    /// 완료 직후 회고를 나중에 작성하기로 한 시각. 회고가 저장되면 nil로 되돌린다.
    var reflectionDeferredAt: Date?

    init(
        focusMinutes: Int,
        breakMinutes: Int,
        category: String? = nil,
        linkedMemoID: UUID? = nil,
        taskTitleSnapshot: String? = nil
    ) {
        self.id = UUID()
        self.startedAt = Date()
        self.focusMinutes = focusMinutes
        self.breakMinutes = breakMinutes
        self.completed = false
        self.category = category
        self.linkedMemoID = linkedMemoID
        self.taskTitleSnapshot = linkedMemoID == nil ? nil : Self.normalizedText(taskTitleSnapshot)
        self.inputActiveSeconds = nil
        self.actualFocusSeconds = nil
        self.pauseIntervalsData = try? JSONEncoder().encode([FocusSessionPauseInterval]())
        self.pauseStartedAt = nil
        self.endKindRawValue = nil
        self.markerColorKey = nil
        self.reflectionDeferredAt = nil
    }

    private static func normalizedText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    @MainActor
    static func updateTaskLink(
        sessionID: UUID,
        memo: Memo?,
        modelContext: ModelContext
    ) throws {
        guard !modelContext.hasChanges else {
            throw FocusSessionTaskLinkUpdateError.pendingChanges
        }

        let targetID = sessionID
        var descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.id == targetID }
        )
        descriptor.fetchLimit = 1
        guard let session = try modelContext.fetch(descriptor).first else {
            throw FocusSessionTaskLinkUpdateError.sessionNotFound
        }
        guard try PomodoroTaskCompletionRecorder.completion(
            focusSessionID: sessionID,
            modelContext: modelContext
        ) == nil else {
            throw FocusSessionTaskLinkUpdateError.taskCompletionExists
        }

        session.linkedMemoID = memo?.id
        session.taskTitleSnapshot = memo.map { taskTitle(from: $0.content) }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    @MainActor
    static func updateTaskLink(
        sessionID: UUID,
        record: SecondBrainRecord?,
        modelContext: ModelContext
    ) throws {
        guard !modelContext.hasChanges else {
            throw FocusSessionTaskLinkUpdateError.pendingChanges
        }

        let targetID = sessionID
        var descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.id == targetID }
        )
        descriptor.fetchLimit = 1
        guard let session = try modelContext.fetch(descriptor).first else {
            throw FocusSessionTaskLinkUpdateError.sessionNotFound
        }
        guard try PomodoroTaskCompletionRecorder.completion(
            focusSessionID: sessionID,
            modelContext: modelContext
        ) == nil else {
            throw FocusSessionTaskLinkUpdateError.taskCompletionExists
        }

        session.linkedMemoID = record?.id
        session.taskTitleSnapshot = record.map { taskTitle(from: $0.content) }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private static func taskTitle(from content: String) -> String {
        let title = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? content.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "제목 없는 할 일" : title
    }
}

extension FocusSession {
    /// nil 과 빈 배열을 구분해 과거 세션에는 기존 단일 구간 계산을 유지한다.
    var hasPauseIntervalTracking: Bool {
        pauseIntervalsData != nil
    }

    var pauseIntervals: [FocusSessionPauseInterval] {
        guard let pauseIntervalsData else { return [] }
        return (try? JSONDecoder().decode(
            [FocusSessionPauseInterval].self,
            from: pauseIntervalsData
        )) ?? []
    }

    func recordPauseStarted(at date: Date = Date()) {
        guard pauseStartedAt == nil else { return }
        pauseStartedAt = max(startedAt, date)
    }

    func recordPauseEnded(at date: Date = Date()) {
        guard let pauseStartedAt else { return }
        let pauseEnd = max(pauseStartedAt, date)
        var intervals = pauseIntervals
        if pauseEnd > pauseStartedAt {
            intervals.append(
                FocusSessionPauseInterval(startedAt: pauseStartedAt, endedAt: pauseEnd)
            )
            pauseIntervalsData = try? JSONEncoder().encode(intervals)
        }
        self.pauseStartedAt = nil
    }

    /// 사용자가 시작·종료 시각을 직접 고친 세션은 편집된 범위 전체를 하나의 집중 구간으로 본다.
    func resetPauseIntervalsForContinuousSession() {
        pauseIntervalsData = try? JSONEncoder().encode([FocusSessionPauseInterval]())
        pauseStartedAt = nil
    }

    var endKind: FocusSessionEndKind? {
        get { endKindRawValue.flatMap(FocusSessionEndKind.init(rawValue:)) }
        set { endKindRawValue = newValue?.rawValue }
    }

    var recordedFocusSeconds: Int {
        let plannedSeconds = max(0, focusMinutes * 60)
        guard plannedSeconds > 0 else { return 0 }
        if let actualFocusSeconds {
            return min(plannedSeconds, max(0, actualFocusSeconds))
        }
        guard let endedAt else { return 0 }
        return min(
            plannedSeconds,
            max(0, Int(endedAt.timeIntervalSince(startedAt)))
        )
    }

    @MainActor
    @discardableResult
    static func resetMarkerColors(
        for category: String,
        in modelContext: ModelContext
    ) throws -> Int {
        guard !modelContext.hasChanges else {
            throw CategoryBehaviorConditionSetValidationError.pendingChanges
        }

        do {
            let sessions = try modelContext.fetch(FetchDescriptor<FocusSession>())
            let customizedSessions = sessions.filter {
                $0.category == category && $0.markerColorKey != nil
            }
            for session in customizedSessions {
                session.markerColorKey = nil
            }
            if !customizedSessions.isEmpty {
                try modelContext.save()
            }
            return customizedSessions.count
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
