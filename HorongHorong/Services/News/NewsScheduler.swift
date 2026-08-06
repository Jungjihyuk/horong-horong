import AppKit
import Foundation
import SwiftData

// MARK: - 순수 스케줄 계산

/// 자동 수집 격자(grid)를 계산하는 순수 함수 모음.
///
/// 핵심 규칙은 **슬롯이 실행 여부와 무관하게 전진한다**는 것이다.
/// 12:00 에 3시간 간격으로 시작했으면 15:00 · 18:00 · 21:00 은 그대로 유지되고,
/// 사용자가 중간에 `리포트 생성` 을 눌러도 격자가 밀리지 않는다.
enum NewsSchedulePlan {
    /// 유예 창의 상한. `.dailyAt` 은 간격이 24시간이라 절반이 12시간이 되어 과하므로 여기서 잘린다.
    static let graceCap: TimeInterval = 2 * 3600

    static func normalizedIntervalHours(_ hours: Int) -> Int {
        min(max(hours, 1), 24)
    }

    /// 모드나 설정이 바뀌었을 때 격자를 처음 세운다.
    ///
    /// `.interval` 은 **시작 시각을 기준점으로 삼은 격자** 위에서 `now` 이후 첫 슬롯을 고른다.
    /// 시작 12:00 · 3시간이면 격자는 12·15·18·21… 이고, 16:47 에 켜도 다음은 18:00 이다.
    /// 버튼을 누른 시각에 따라 격자가 우연히 정해지지 않는다.
    ///
    /// 24로 나누어떨어지지 않는 간격(예: 5시간)은 날짜를 넘어가며 계속 이어진다 —
    /// 12 → 17 → 22 → 03 → 08. 매일 시작 시각으로 되돌아오지 않는다.
    static func initialSlot(
        from now: Date,
        mode: Constants.NewsScheduleMode,
        dailyHour: Int,
        dailyMinute: Int,
        intervalHours: Int,
        intervalStartHour: Int = Constants.defaultNewsScheduleIntervalStartHour,
        intervalStartMinute: Int = Constants.defaultNewsScheduleIntervalStartMinute,
        calendar: Calendar = .current
    ) -> Date? {
        switch mode {
        case .manual:
            return nil
        case .dailyAt:
            return CompanionBriefingSchedule.nextFireDate(
                after: now,
                hour: dailyHour,
                minute: dailyMinute,
                calendar: calendar
            )
        case .interval:
            let step = TimeInterval(normalizedIntervalHours(intervalHours) * 3600)
            var components = calendar.dateComponents([.year, .month, .day], from: now)
            components.hour = CompanionBriefingSchedule.normalizedHour(intervalStartHour)
            components.minute = CompanionBriefingSchedule.normalizedMinute(intervalStartMinute)
            components.second = 0
            guard let anchor = calendar.date(from: components) else {
                return now.addingTimeInterval(step)
            }
            guard anchor <= now else { return anchor }
            // 기준점이 이미 지났으면 격자 위에서 다음 미래 지점으로 건너뛴다.
            let steps = (now.timeIntervalSince(anchor) / step).rounded(.down) + 1
            return anchor.addingTimeInterval(steps * step)
        }
    }

    /// 다음 수집 시각을 사람이 읽는 문구로. "오늘 18:00" / "내일 09:00" / "8월 9일 18:00".
    static func displayText(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = DateFormatter()
        time.locale = Locale(identifier: "ko_KR")
        time.dateFormat = "HH:mm"
        let clock = time.string(from: date)

        if calendar.isDate(date, inSameDayAs: now) { return "오늘 \(clock)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "내일 \(clock)"
        }
        let day = DateFormatter()
        day.locale = Locale(identifier: "ko_KR")
        day.dateFormat = "M월 d일"
        return "\(day.string(from: date)) \(clock)"
    }

    /// 슬롯 하나를 다음 칸으로 전진시킨다.
    static func advance(
        slot: Date,
        mode: Constants.NewsScheduleMode,
        intervalHours: Int,
        calendar: Calendar = .current
    ) -> Date {
        switch mode {
        case .manual:
            return slot
        case .dailyAt:
            // 캘린더로 더해야 서머타임 구간에서도 벽시계 시각이 유지된다.
            return calendar.date(byAdding: .day, value: 1, to: slot) ?? slot.addingTimeInterval(86_400)
        case .interval:
            return slot.addingTimeInterval(TimeInterval(normalizedIntervalHours(intervalHours) * 3600))
        }
    }

    /// `slot` 이 이미 지났으면 미래가 될 때까지 전진시킨다.
    ///
    /// - Returns: `next` 는 **항상 `now` 보다 미래**다. 이 불변식 덕분에 타이머가 과거 시각으로
    ///   재예약되어 즉시 다시 울리는 바쁜 루프가 생기지 않는다.
    ///   `missedSlot` 은 지나간 슬롯 중 **가장 마지막** 것이며, 지나간 슬롯이 없으면 `nil` 이다.
    ///   며칠을 놓쳤더라도 하나만 돌려주므로 몰아서 실행되지 않는다.
    static func catchUp(
        slot: Date,
        now: Date,
        mode: Constants.NewsScheduleMode,
        intervalHours: Int,
        calendar: Calendar = .current
    ) -> (next: Date, missedSlot: Date?) {
        guard mode != .manual, slot <= now else { return (slot, nil) }

        switch mode {
        case .manual:
            return (slot, nil)

        case .interval:
            let step = TimeInterval(normalizedIntervalHours(intervalHours) * 3600)
            let steps = (now.timeIntervalSince(slot) / step).rounded(.down) + 1
            let next = slot.addingTimeInterval(steps * step)
            return (next, next.addingTimeInterval(-step))

        case .dailyAt:
            var next = slot
            var missed: Date?
            while next <= now {
                missed = next
                let advanced = advance(slot: next, mode: mode, intervalHours: intervalHours, calendar: calendar)
                // 캘린더 계산이 전진하지 못하는 병리적 경우의 안전장치.
                guard advanced > next else { return (next.addingTimeInterval(86_400), missed) }
                next = advanced
            }
            return (next, missed)
        }
    }

    /// 슬롯 시각 기준 유예 창 이내에 이미 수집했으면 `true`.
    ///
    /// 3시간 간격에서 15:00 슬롯이라면 13:30 이후에 수집한 적이 있는지를 본다.
    /// 사용자가 14:58 에 직접 눌렀다면 그 슬롯은 건너뛰고 18:00 을 기다린다.
    static func shouldSkip(
        slot: Date,
        lastRunAt: Date?,
        mode: Constants.NewsScheduleMode,
        intervalHours: Int
    ) -> Bool {
        guard let lastRunAt else { return false }
        let window = grace(mode: mode, intervalHours: intervalHours)
        guard window > 0 else { return false }
        return lastRunAt > slot.addingTimeInterval(-window)
    }

    /// 슬롯 앞쪽 유예 창의 길이. 간격의 절반을 쓰되 `graceCap` 에서 자른다.
    static func grace(mode: Constants.NewsScheduleMode, intervalHours: Int) -> TimeInterval {
        switch mode {
        case .manual:
            return 0
        case .dailyAt:
            return graceCap
        case .interval:
            let step = TimeInterval(normalizedIntervalHours(intervalHours) * 3600)
            return min(step / 2, graceCap)
        }
    }
}

// MARK: - 스케줄러

/// 설정한 주기마다 뉴스 파이프라인을 자동으로 돌린다.
///
/// 파이프라인은 앱이 띄운 자식 프로세스라 앱이 살아 있는 동안에만 동작한다.
/// 잠자기·시계 변경으로 슬롯을 놓치는 경우는 `observeSystemTimeChanges()` 가 복구한다.
@Observable
@MainActor
final class NewsScheduler {
    static let shared = NewsScheduler()

    /// 지금 도는 잡이 자동 수집으로 시작된 것인지. 팝오버 버튼 라벨이 이 값을 읽는다.
    private(set) var isAutoRunInFlight = false

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var pipelineService: NewsPipelineService?
    private var modelContext: ModelContext?
    private var appliedSignature: String?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func start(pipelineService: NewsPipelineService, modelContext: ModelContext) {
        self.pipelineService = pipelineService
        self.modelContext = modelContext

        migrateLegacyScheduleIfNeeded()
        // 시작 시점의 설정을 이미 반영한 것으로 기록해 둔다.
        // 그래야 기존 격자를 초기화하지 않고 그대로 이어받는다.
        appliedSignature = currentSignature()
        // 이 기능이 붙기 전부터 쓰던 사용자에게는 확정 시각이 없다. 지금을 기준으로 삼는다.
        if date(forKey: Constants.NewsStorageKey.scheduleConfiguredAt) == nil {
            markScheduleConfigured()
        }

        observeDefaultsChanges()
        observeSystemTimeChanges()
        observeJobCompletion()

        evaluate()
    }

    // MARK: - 핵심 진입점

    /// 격자를 현재 시각에 맞춰 정리하고, 지나간 슬롯이 있으면 실행을 시도한 뒤 타이머를 다시 건다.
    ///
    /// 타이머 발화 · 앱 시작 · 잠자기 복귀 · 시계 변경이 모두 이 한 곳으로 들어온다.
    /// **슬롯 전진을 실행 판정보다 먼저 하는 것이 중요하다.** 어떤 경로로 빠져나가든 격자가
    /// 반드시 한 칸 나아가므로 같은 슬롯에서 맴도는 일이 생기지 않는다.
    private func evaluate() {
        let mode = currentMode
        guard mode != .manual else {
            invalidateTimer()
            defaults.removeObject(forKey: Constants.NewsStorageKey.scheduleNextSlotAt)
            return
        }

        guard let slot = nextSlotAt ?? NewsSchedulePlan.initialSlot(
            from: Date(),
            mode: mode,
            dailyHour: dailyHour,
            dailyMinute: dailyMinute,
            intervalHours: intervalHours,
            intervalStartHour: intervalStartHour,
            intervalStartMinute: intervalStartMinute
        ) else {
            invalidateTimer()
            return
        }

        let result = NewsSchedulePlan.catchUp(
            slot: slot,
            now: Date(),
            mode: mode,
            intervalHours: intervalHours
        )
        setNextSlotAt(result.next)
        scheduleTimer(at: result.next)

        if let missedSlot = result.missedSlot {
            runIfAllowed(slot: missedSlot, mode: mode)
        }
    }

    /// 슬롯이 도래했을 때 실제로 돌릴지 판정한다.
    private func runIfAllowed(slot: Date, mode: Constants.NewsScheduleMode) {
        guard let service = pipelineService, let modelContext else { return }
        // 수동이든 자동이든 이미 도는 중이면 건너뛴다. `startJob` 자체도 `guard !isRunning` 이라
        // 중복 실행은 애초에 불가능하지만, 여기서 걸러야 헛되이 알림을 보내지 않는다.
        guard !service.isRunning else { return }
        guard !NewsSchedulePlan.shouldSkip(
            slot: slot,
            lastRunAt: lastRunAtForGrace,
            mode: mode,
            intervalHours: intervalHours
        ) else { return }

        let configuration = NewsPipelineLaunchConfiguration.current(defaults: defaults)
        guard configuration.provider == "ollama" else {
            performLaunch(configuration, service: service, context: modelContext)
            return
        }
        // 수동 경로는 모델이 없으면 다운로드할지 물어보지만, 자동 경로에는 답할 사람이 없다.
        Task { [weak self] in
            await self?.launchWithOllamaPreflight(configuration, service: service, context: modelContext)
        }
    }

    private func launchWithOllamaPreflight(
        _ configuration: NewsPipelineLaunchConfiguration,
        service: NewsPipelineService,
        context: ModelContext
    ) async {
        let model = configuration.providerOptions?.model ?? Constants.defaultNewsOllamaModel
        let endpoint = configuration.providerOptions?.endpoint ?? Constants.defaultNewsOllamaEndpoint
        do {
            guard try await service.isOllamaModelInstalled(model: model, endpoint: endpoint) else {
                notify(title: "자동 수집을 건너뛰었습니다", body: "Ollama 모델 '\(model)'이(가) 설치되어 있지 않습니다.")
                return
            }
        } catch {
            notify(title: "자동 수집을 건너뛰었습니다", body: "Ollama 서버에 연결하지 못했습니다.")
            return
        }
        guard !service.isRunning else { return }
        performLaunch(configuration, service: service, context: context)
    }

    private func performLaunch(
        _ configuration: NewsPipelineLaunchConfiguration,
        service: NewsPipelineService,
        context: ModelContext
    ) {
        isAutoRunInFlight = true
        configuration.launch(on: service, context: context, defaults: defaults)
        // `startJob` 의 사전 점검(E_ENV / E_PROVIDER_CLI / E_CONFIG)은 프로세스를 띄우기 전에
        // 동기적으로 실패하므로, 이 시점에 이미 끝나 있을 수 있다.
        if !service.isRunning {
            isAutoRunInFlight = false
            notify(title: "자동 수집 실패", body: service.lastErrorMessage ?? "뉴스 파이프라인을 시작하지 못했습니다.")
        }
    }

    private func handleJobFinished() {
        guard isAutoRunInFlight else { return }
        isAutoRunInFlight = false
        guard let service = pipelineService else { return }
        switch service.lastJobStatus {
        case "success", "partial_success":
            notify(title: "뉴스 리포트가 준비됐습니다", body: "자동 수집이 끝났습니다. 팝오버에서 확인해보세요.")
        case "cancelled":
            break
        default:
            notify(title: "자동 수집 실패", body: service.lastErrorMessage ?? "뉴스 수집에 실패했습니다.")
        }
    }

    private func notify(title: String, body: String) {
        NotificationManager.shared.send(title: title, body: body)
    }

    // MARK: - 타이머

    private func scheduleTimer(at date: Date) {
        invalidateTimer()
        // `catchUp` 이 미래 시각을 보장하지만, 경계에서 0초 타이머가 되지 않도록 한 번 더 민다.
        let fireDate = max(date, Date().addingTimeInterval(1))
        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.evaluate()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func invalidateTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - 관찰

    private func observeDefaultsChanges() {
        observers.append(
            NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: defaults,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.applySettings() }
            }
        )
    }

    /// 잠자기에서 깨어나거나 시계·시간대가 바뀌면 예약이 어긋난다.
    private func observeSystemTimeChanges() {
        let handler: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange, .NSCalendarDayChanged] {
            observers.append(
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main, using: handler)
            )
        }
        workspaceObservers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: handler
            )
        )
    }

    private func observeJobCompletion() {
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .newsPipelineJobFinished,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleJobFinished() }
            }
        )
    }

    /// 스케줄 설정이 실제로 바뀌었을 때만 격자를 새로 세운다.
    ///
    /// `UserDefaults.didChangeNotification` 은 무관한 키가 바뀌어도 오고, 이 클래스가
    /// `nextSlotAt` 을 쓸 때도 온다. 서명을 비교해 걸러내지 않으면 되먹임이 생긴다.
    private func applySettings() {
        let signature = currentSignature()
        guard signature != appliedSignature else { return }
        appliedSignature = signature
        markScheduleConfigured()

        setNextSlotAt(NewsSchedulePlan.initialSlot(
            from: Date(),
            mode: currentMode,
            dailyHour: dailyHour,
            dailyMinute: dailyMinute,
            intervalHours: intervalHours,
            intervalStartHour: intervalStartHour,
            intervalStartMinute: intervalStartMinute
        ))
        evaluate()
    }

    /// 예전 값(`hourly` / `daily`)을 새 모드 체계로 한 번 옮긴다.
    /// 레거시 값은 다시 선택될 수 없으므로 별도 마이그레이션 플래그가 필요 없다.
    private func migrateLegacyScheduleIfNeeded() {
        switch defaults.string(forKey: Constants.NewsStorageKey.schedule) {
        case "hourly":
            defaults.set(Constants.NewsScheduleMode.interval.rawValue, forKey: Constants.NewsStorageKey.schedule)
            defaults.set(1, forKey: Constants.NewsStorageKey.scheduleIntervalHours)
        case "daily":
            defaults.set(Constants.NewsScheduleMode.dailyAt.rawValue, forKey: Constants.NewsStorageKey.schedule)
            defaults.set(Constants.defaultNewsScheduleDailyHour, forKey: Constants.NewsStorageKey.scheduleDailyHour)
            defaults.set(Constants.defaultNewsScheduleDailyMinute, forKey: Constants.NewsStorageKey.scheduleDailyMinute)
        default:
            break
        }
    }

    // MARK: - 설정 읽기

    private func currentSignature() -> String {
        "\(currentMode.rawValue)|\(dailyHour)|\(dailyMinute)|\(intervalHours)|\(intervalStartHour)|\(intervalStartMinute)"
    }

    private var currentMode: Constants.NewsScheduleMode {
        Constants.NewsScheduleMode.normalized(
            rawValue: defaults.string(forKey: Constants.NewsStorageKey.schedule) ?? Constants.defaultNewsSchedule
        )
    }

    private var dailyHour: Int {
        defaults.object(forKey: Constants.NewsStorageKey.scheduleDailyHour) as? Int
            ?? Constants.defaultNewsScheduleDailyHour
    }

    private var dailyMinute: Int {
        defaults.object(forKey: Constants.NewsStorageKey.scheduleDailyMinute) as? Int
            ?? Constants.defaultNewsScheduleDailyMinute
    }

    private var intervalHours: Int {
        defaults.object(forKey: Constants.NewsStorageKey.scheduleIntervalHours) as? Int
            ?? Constants.defaultNewsScheduleIntervalHours
    }

    private var intervalStartHour: Int {
        defaults.object(forKey: Constants.NewsStorageKey.scheduleIntervalStartHour) as? Int
            ?? Constants.defaultNewsScheduleIntervalStartHour
    }

    private var intervalStartMinute: Int {
        defaults.object(forKey: Constants.NewsStorageKey.scheduleIntervalStartMinute) as? Int
            ?? Constants.defaultNewsScheduleIntervalStartMinute
    }

    private var nextSlotAt: Date? {
        date(forKey: Constants.NewsStorageKey.scheduleNextSlotAt)
    }

    private var lastRunAt: Date? {
        date(forKey: Constants.NewsStorageKey.scheduleLastRunAt)
    }

    /// 유예 창 판정에 쓸 마지막 수집 시각.
    ///
    /// 지금 스케줄을 확정하기 *전* 의 수집은 이 스케줄과 무관하므로 세지 않는다.
    /// 그렇지 않으면 18:18 에 한 번 돌린 뒤 20:00 부터 6시간 간격을 새로 설정했을 때,
    /// 첫 회차인 20:00 이 옛 기록에 걸려 조용히 사라진다.
    private var lastRunAtForGrace: Date? {
        guard let lastRunAt else { return nil }
        guard let configuredAt = date(forKey: Constants.NewsStorageKey.scheduleConfiguredAt) else {
            return lastRunAt
        }
        return lastRunAt >= configuredAt ? lastRunAt : nil
    }

    private func date(forKey key: String) -> Date? {
        let raw = defaults.double(forKey: key)
        return raw > 0 ? Date(timeIntervalSince1970: raw) : nil
    }

    private func markScheduleConfigured() {
        defaults.set(Date().timeIntervalSince1970, forKey: Constants.NewsStorageKey.scheduleConfiguredAt)
    }

    private func setNextSlotAt(_ date: Date?) {
        guard let date else {
            defaults.removeObject(forKey: Constants.NewsStorageKey.scheduleNextSlotAt)
            return
        }
        defaults.set(date.timeIntervalSince1970, forKey: Constants.NewsStorageKey.scheduleNextSlotAt)
    }
}
