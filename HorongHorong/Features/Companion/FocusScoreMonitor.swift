import Foundation
import SwiftData

/// 진행 중인 집중 세션의 몰입도를 지켜보다가, 기준선 아래로 떨어지면 한 번 말을 건다.
///
/// 판정은 `FocusScoreDetector` 가 하고 이 타입은 재료를 모으는 일만 한다.
/// 문구는 모델을 거치지 않고 사용자가 등록한 그대로 나간다 — 온디바이스 모델에 맡기면
/// 말투가 옮고 조건과 무관하게 아무 때나 튀어나온다(이슈 #113).
@MainActor
final class FocusScoreMonitor {
    private let appState: AppState
    private let modelContainer: ModelContainer
    /// 말풍선을 실제로 띄웠으면 true. 대화 중이라 건너뛴 경우와 구분해야 다음 폴에서 다시 시도한다.
    private let onNudge: (String) -> Bool

    /// 몰입도는 5분 넘게 쌓인 비율이라 초 단위로 볼 이유가 없다. 성기게 봐도 판정이 달라지지 않는다.
    private static let pollInterval: TimeInterval = 30
    /// 타이머가 끝난 뒤에도 세션 행이 잠깐 남아 있을 수 있어 여유를 둔다.
    private static let staleSessionSlackSeconds: TimeInterval = 5 * 60

    /// 진행 중인 세션에서 붙잡아 두는 것. 세션이 끝나면 통째로 버린다.
    private struct CurrentSession {
        let startedAt: Date
        let category: String
        let focusMinutes: Int
        var hasNudged = false
    }

    private var pollTimer: Timer?
    private var current: CurrentSession?

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
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        current = nil
    }

    private func poll() {
        switch appState.timerState {
        case .paused:
            // 멈춘 동안은 보지도, 지금까지 붙잡은 것을 버리지도 않는다.
            return
        case .idle, .breaking, .breakAlert:
            current = nil
            return
        case .focusing:
            break
        }

        guard Self.isEnabled else { return }

        if current == nil {
            current = loadCurrentSession()
        }
        guard let session = current, !session.hasNudged else { return }

        let now = Date()
        // 창은 과거 그래프와 같은 기준으로 자른다. 계획한 시간을 넘겨 세면 분모가 부풀어 몰입도가 낮게 나온다.
        let plannedEnd = session.startedAt.addingTimeInterval(
            TimeInterval(max(0, session.focusMinutes) * 60)
        )
        let windowEnd = min(now, plannedEnd)
        let elapsed = windowEnd.timeIntervalSince(session.startedAt)

        // 워밍업 전에는 조회조차 하지 않는다. 한 포모도로에서 실제로 도는 건 몇십 번뿐이다.
        guard elapsed >= FocusScoreDetector.warmUpSeconds else { return }

        let score = FocusScoreHistory.liveScore(
            sessionStart: session.startedAt,
            windowEnd: windowEnd,
            focusCategory: session.category,
            modelContext: modelContainer.mainContext
        )

        guard FocusScoreDetector.shouldNudge(
            FocusScoreNudgeInput(
                isFocusing: true,
                elapsedSeconds: elapsed,
                score: score.value,
                threshold: FocusThresholdStore.shared.threshold(for: session.category),
                hasNudgedThisSession: session.hasNudged
            )
        ) else { return }

        guard let message = FocusScoreMessages.next(
            from: Self.registeredMessages,
            previous: Self.lastMessage
        ) else { return }

        // 대화 중이라 말풍선을 띄우지 못했으면 이번 세션의 한 번을 쓴 것으로 치지 않는다.
        guard onNudge(message) else { return }
        current?.hasNudged = true
        UserDefaults.standard.set(
            message,
            forKey: Constants.AppStorageKey.companionFocusNudgeLastMessage
        )
        recordNudgeEvent(session: session, score: score.value, at: now)
    }

    /// 잔소리가 줄고 있는지 나중에 볼 수 있도록 발동 당시의 값을 남긴다.
    private func recordNudgeEvent(session: CurrentSession, score: Double, at date: Date) {
        let context = modelContainer.mainContext
        context.insert(
            FocusNudgeEvent(
                firedAt: date,
                category: session.category,
                score: score,
                threshold: FocusThresholdStore.shared.threshold(for: session.category)
            )
        )
        try? context.save()
    }

    /// 진행 중인 세션을 저장소에서 직접 읽는다.
    /// 과거 그래프가 쓰는 `startedAt`·`category` 와 같은 출처여야 두 숫자가 어긋나지 않는다.
    private func loadCurrentSession() -> CurrentSession? {
        var descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let session = try? modelContainer.mainContext.fetch(descriptor).first else {
            return nil
        }

        // 끝맺지 못하고 남은 옛 행을 진행 중인 세션으로 오인하지 않게 막는다.
        let limit = TimeInterval(max(0, session.focusMinutes) * 60) + Self.staleSessionSlackSeconds
        guard Date().timeIntervalSince(session.startedAt) < limit else { return nil }

        return CurrentSession(
            startedAt: session.startedAt,
            category: session.category ?? Constants.defaultFocusCategory,
            focusMinutes: session.focusMinutes
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
        UserDefaults.standard.string(forKey: Constants.AppStorageKey.companionFocusNudgeLastMessage)
    }
}
