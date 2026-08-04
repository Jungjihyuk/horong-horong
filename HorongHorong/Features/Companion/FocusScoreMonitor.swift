import Foundation
import OSLog
import SwiftData

/// 진행 중인 집중 세션의 최근 10분을 보고, 규칙 위반이 새로 시작될 때 이유와 함께 말한다.
@MainActor
final class FocusScoreMonitor {
    private let appState: AppState
    private let modelContainer: ModelContainer
    /// 말풍선을 실제로 띄웠으면 true. 대화 중이라 건너뛴 경우에는 다음 폴에서 다시 시도한다.
    private let onNudge: (String) -> Bool

    private static let pollInterval: TimeInterval = 30
    private static let staleSessionSlackSeconds: TimeInterval = 5 * 60

    private struct CurrentSession {
        let id: UUID
        let startedAt: Date
        let category: String
        let focusMinutes: Int
        let hasPauseIntervalTracking: Bool
        let pauseIntervals: [FocusSessionPauseInterval]
        let settings: FocusNudgeSettingsSnapshot
        let policy: FocusNudgePolicy
        var nudgeCount: Int
        var isViolationLatched: Bool
    }

    private struct PendingNudgeEvent: Codable {
        let id: UUID
        let firedAt: Date
        let category: String
        let focusSessionID: UUID
        let observedFocusRatio: Double?
        let minimumFocusRatio: Double?
        let observedAppSwitches: Int?
        let maximumAppSwitches: Int?
        let policySourceRawValue: String

        init(
            firedAt: Date,
            category: String,
            focusSessionID: UUID,
            violation: FocusNudgeViolation,
            policy: FocusNudgePolicy
        ) {
            self.id = UUID()
            self.firedAt = firedAt
            self.category = category
            self.focusSessionID = focusSessionID
            self.observedFocusRatio = violation.focusRatio?.observed
            self.minimumFocusRatio = violation.focusRatio?.minimum
            self.observedAppSwitches = violation.appSwitches?.observed
            self.maximumAppSwitches = violation.appSwitches?.maximum
            self.policySourceRawValue = policy.source.rawValue
        }
    }

    /// 앱이 집중 세션 도중 다시 열려도 같은 위반은 중복하지 않고, 이미 회복한 뒤의 새 위반은 놓치지 않는다.
    private struct PersistedSessionState: Codable {
        let sessionID: UUID
        let isViolationLatched: Bool
    }

    private var pollTimer: Timer?
    private var current: CurrentSession?

    private static let log = Logger(subsystem: "com.horonghorong.app", category: "FocusScore")

    init(
        appState: AppState,
        modelContainer: ModelContainer,
        onNudge: @escaping (String) -> Bool
    ) {
        self.appState = appState
        self.modelContainer = modelContainer
        self.onNudge = onNudge
    }

    func start() {
        guard pollTimer == nil else { return }
        flushPendingEvents()
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        flushPendingEvents()
        current = nil
    }

    func poll(at now: Date = Date()) {
        flushPendingEvents()

        switch appState.timerState {
        case .paused:
            return
        case .idle, .breaking, .breakAlert:
            current = nil
            clearPersistedSessionState()
            return
        case .focusing:
            break
        }
        guard Self.isEnabled else { return }

        current = loadCurrentSession(at: now)
        guard let session = current else {
            Self.log.info("건너뜀: 진행 중인 세션을 찾지 못함")
            return
        }

        let plannedSessionSeconds = max(0, session.focusMinutes) * 60
        let remainingSeconds = min(plannedSessionSeconds, max(0, appState.remainingSeconds))
        let activeElapsedSeconds = plannedSessionSeconds - remainingSeconds
        let elapsed = TimeInterval(activeElapsedSeconds)

        let activeIntervals: [DateInterval]
        if session.hasPauseIntervalTracking {
            activeIntervals = FocusSessionActivityIntervals.make(
                startedAt: session.startedAt,
                endedAt: now,
                excluding: session.pauseIntervals,
                maximumActiveSeconds: elapsed
            )
        } else {
            let end = min(now, session.startedAt.addingTimeInterval(elapsed))
            activeIntervals = end > session.startedAt
                ? [DateInterval(start: session.startedAt, end: end)]
                : []
        }

        guard let metrics = FocusScoreHistory.liveWindowMetrics(
            activeIntervals: activeIntervals,
            focusCategory: session.category,
            modelContext: modelContainer.mainContext
        ) else {
            Self.log.info(
                "건너뜀: 최근 10분을 모으는 중 (활동 \(Int(elapsed))초 / 600초)"
            )
            return
        }

        let violation = FocusNudgeDetector.violation(
            metrics: metrics,
            rule: session.policy.rule
        )
        Self.log.info("""
            판정: 카테고리 \(session.category, privacy: .public) · 최근 10분 몰입도 \
            \(Int(metrics.score.value * 100))% / 기준 \
            \(Int(session.policy.rule.minimumFocusRatio * 100))% · 앱 전환 \
            \(metrics.appSwitchCount)회 / 기준 \(session.policy.rule.maximumAppSwitches)회 · \
            출처 \(session.policy.source.rawValue, privacy: .public) · 잴 수 있음 \
            \(metrics.score.isMeasurable)
            """)

        guard !violation.isEmpty else {
            current?.isViolationLatched = false
            savePersistedSessionState(sessionID: session.id, isViolationLatched: false)
            return
        }
        guard FocusNudgeDetector.shouldNudge(
            isFocusing: true,
            violation: violation,
            isViolationLatched: session.isViolationLatched,
            nudgeCount: session.nudgeCount,
            maximumNudgesPerSession: session.policy.maximumNudgesPerSession
        ) else {
            // 횟수 상한에 닿은 상태도 같은 위반이 계속되는 동안 반복해서 판정하지 않는다.
            current?.isViolationLatched = true
            savePersistedSessionState(sessionID: session.id, isViolationLatched: true)
            Self.log.info("건너뜀: 같은 위반이 계속 중이거나 세션 최대 횟수에 도달함")
            return
        }

        guard let baseMessage = FocusScoreMessages.next(
            from: Self.registeredMessages,
            previous: Self.lastMessage
        ) else {
            Self.log.error("건너뜀: 할 말을 고르지 못함")
            return
        }
        let message = FocusScoreMessages.explained(
            baseMessage: baseMessage,
            violation: violation,
            source: session.policy.source
        )

        guard onNudge(message) else {
            Self.log.info("건너뜀: 말풍선을 띄우지 못함 (컴패니언 꺼짐·대화 중·메뉴 열림·온보딩 중)")
            return
        }

        current?.isViolationLatched = true
        current?.nudgeCount += 1
        savePersistedSessionState(sessionID: session.id, isViolationLatched: true)
        UserDefaults.standard.set(
            baseMessage,
            forKey: Constants.AppStorageKey.companionFocusNudgeLastMessage
        )
        recordNudgeEvent(
            category: session.category,
            sessionID: session.id,
            violation: violation,
            policy: session.policy,
            at: now
        )
        Self.log.info("말함: \(message, privacy: .public)")
    }

    private func loadCurrentSession(at now: Date) -> CurrentSession? {
        var descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let session = try? modelContainer.mainContext.fetch(descriptor).first else {
            return nil
        }

        let limit = TimeInterval(max(0, session.focusMinutes) * 60) + Self.staleSessionSlackSeconds
        let activeAge: TimeInterval
        if session.hasPauseIntervalTracking {
            var pauses = session.pauseIntervals
            if let pauseStartedAt = session.pauseStartedAt, now > pauseStartedAt {
                pauses.append(
                    FocusSessionPauseInterval(startedAt: pauseStartedAt, endedAt: now)
                )
            }
            activeAge = FocusSessionActivityIntervals.make(
                startedAt: session.startedAt,
                endedAt: now,
                excluding: pauses
            ).reduce(0) { $0 + $1.duration }
        } else {
            activeAge = now.timeIntervalSince(session.startedAt)
        }
        guard activeAge < limit else { return nil }

        let settings = FocusNudgeSettingsStore.snapshot()
        let policy: FocusNudgePolicy
        let nudgeCount: Int
        let isViolationLatched: Bool
        if let current, current.id == session.id, current.settings == settings {
            policy = current.policy
            nudgeCount = current.nudgeCount
            isViolationLatched = current.isViolationLatched
        } else {
            let analysis = settings.detectionMode == .personalized
                ? FocusPersonalizationTrainer.analyze(
                    requiredFeedbackCount: settings.requiredFeedbackCount,
                    modelContext: modelContainer.mainContext
                )
                : nil
            policy = FocusNudgePolicyResolver.resolve(
                settings: settings,
                personalization: analysis
            )
            nudgeCount = recordedNudgeCount(
                sessionID: session.id,
                sessionStart: session.startedAt,
                now: now
            )
            // 새 버전에서 저장한 위반 상태를 우선 쓴다. 상태가 없던 구버전 세션은 중복 방지를 우선한다.
            isViolationLatched = persistedSessionState(for: session.id)?.isViolationLatched
                ?? (nudgeCount > 0)
        }

        return CurrentSession(
            id: session.id,
            startedAt: session.startedAt,
            category: session.category ?? Constants.defaultFocusCategory,
            focusMinutes: session.focusMinutes,
            hasPauseIntervalTracking: session.hasPauseIntervalTracking,
            pauseIntervals: session.pauseIntervals,
            settings: settings,
            policy: policy,
            nudgeCount: nudgeCount,
            isViolationLatched: isViolationLatched
        )
    }

    private func recordedNudgeCount(
        sessionID: UUID,
        sessionStart: Date,
        now: Date
    ) -> Int {
        let events = (try? modelContainer.mainContext.fetch(
            FetchDescriptor<FocusNudgeEvent>(
                predicate: #Predicate { $0.firedAt >= sessionStart && $0.firedAt <= now }
            )
        )) ?? []
        return events.filter {
            $0.focusSessionID == sessionID || $0.focusSessionID == nil
        }.count
    }

    // MARK: - 실제 표시 기록

    /// 화면 표시는 DB 저장과 원자적으로 묶을 수 없다. 먼저 UserDefaults에 작은 보류 큐를 남긴 뒤
    /// SwiftData에 옮겨, 저장 실패나 직후 종료가 있어도 실제 들은 횟수를 잃지 않는다.
    private func recordNudgeEvent(
        category: String,
        sessionID: UUID,
        violation: FocusNudgeViolation,
        policy: FocusNudgePolicy,
        at date: Date
    ) {
        var pending = pendingEvents()
        pending.append(
            PendingNudgeEvent(
                firedAt: date,
                category: category,
                focusSessionID: sessionID,
                violation: violation,
                policy: policy
            )
        )
        savePendingEvents(pending)
        flushPendingEvents()
    }

    private func flushPendingEvents() {
        let pending = pendingEvents()
        guard !pending.isEmpty else { return }
        // 앱의 다른 편집 중 변경과 저장/롤백이 섞이지 않도록 기록 전용 컨텍스트를 쓴다.
        let context = ModelContext(modelContainer)

        do {
            for item in pending {
                let eventID = item.id
                var descriptor = FetchDescriptor<FocusNudgeEvent>(
                    predicate: #Predicate { $0.id == eventID }
                )
                descriptor.fetchLimit = 1
                guard try context.fetch(descriptor).isEmpty else { continue }
                context.insert(
                    FocusNudgeEvent(
                        id: item.id,
                        firedAt: item.firedAt,
                        category: item.category,
                        focusSessionID: item.focusSessionID,
                        observedFocusRatio: item.observedFocusRatio,
                        minimumFocusRatio: item.minimumFocusRatio,
                        observedAppSwitches: item.observedAppSwitches,
                        maximumAppSwitches: item.maximumAppSwitches,
                        policySource: FocusNudgePolicySource(
                            rawValue: item.policySourceRawValue
                        )
                    )
                )
            }
            try context.save()
            savePendingEvents([])
        } catch {
            context.rollback()
            Self.log.error("잔소리 기록 저장 실패, 다음 폴에서 재시도: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func pendingEvents() -> [PendingNudgeEvent] {
        guard let data = UserDefaults.standard.data(
            forKey: Constants.AppStorageKey.companionFocusNudgePendingEvents
        ) else { return [] }
        return (try? JSONDecoder().decode([PendingNudgeEvent].self, from: data)) ?? []
    }

    private func savePendingEvents(_ events: [PendingNudgeEvent]) {
        let key = Constants.AppStorageKey.companionFocusNudgePendingEvents
        guard !events.isEmpty else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: - 세션 재시작 상태

    private func persistedSessionState(for sessionID: UUID) -> PersistedSessionState? {
        guard let data = UserDefaults.standard.data(
            forKey: Constants.AppStorageKey.companionFocusNudgeSessionState
        ),
        let state = try? JSONDecoder().decode(PersistedSessionState.self, from: data),
        state.sessionID == sessionID else {
            return nil
        }
        return state
    }

    private func savePersistedSessionState(
        sessionID: UUID,
        isViolationLatched: Bool
    ) {
        let state = PersistedSessionState(
            sessionID: sessionID,
            isViolationLatched: isViolationLatched
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(
            data,
            forKey: Constants.AppStorageKey.companionFocusNudgeSessionState
        )
    }

    private func clearPersistedSessionState() {
        UserDefaults.standard.removeObject(
            forKey: Constants.AppStorageKey.companionFocusNudgeSessionState
        )
    }

    // MARK: - 설정 값

    private static var isEnabled: Bool {
        UserDefaults.standard.object(
            forKey: Constants.AppStorageKey.companionFocusNudgeEnabled
        ) as? Bool ?? Constants.defaultCompanionFocusNudgeEnabled
    }

    private static var registeredMessages: [String] {
        FocusScoreMessages.parse(
            UserDefaults.standard.string(
                forKey: Constants.AppStorageKey.companionFocusNudgeMessages
            ) ?? ""
        )
    }

    private static var lastMessage: String? {
        UserDefaults.standard.string(
            forKey: Constants.AppStorageKey.companionFocusNudgeLastMessage
        )
    }
}
