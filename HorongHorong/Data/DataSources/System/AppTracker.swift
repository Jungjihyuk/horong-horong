import AppKit

/// **`@MainActor` 인 이유**: 5초 폴링 타이머로 앱 전환을 보고 화면 상태를 고친다.
/// 원래도 메인 스레드에서만 돌던 것을 이제 컴파일러가 지킨다(`TimerManager` 와 같은 사정).
@MainActor
@Observable
final class AppTracker {
    private var currentApp: NSRunningApplication?
    private var currentAppStartTime: Date?
    // 집중도 분석용 세그먼트 구간 시작 (앱 전환/슬립 복귀 시에만 리셋 — 5초 폴링으로는 리셋되지 않음)
    private var currentSegmentStart: Date?
    private var pollTimer: Timer?
    private var repository: AppUsageRepository?
    var isTracking: Bool = false

    // 앱 방문 최소 길이(초). 이보다 짧은 포커스 이동은 일일/세션 기록 모두에서 제외한다.
    /// 값이라 액터와 무관하다. 통계 화면도 같은 기준으로 짧은 구간을 거른다.
    nonisolated static let minimumSegmentSeconds: TimeInterval = 5

    nonisolated static func shouldPersistSegment(
        elapsed: TimeInterval,
        hasPreviousSegment: Bool
    ) -> Bool {
        guard elapsed >= 0 else { return false }
        return hasPreviousSegment || elapsed >= minimumSegmentSeconds
    }

    typealias DailyDurationSlice = AppUsageDaySlicer.Slice

    /// 규칙은 `AppUsageDaySlicer` 에 있다. 호출부가 많아 이름을 남겨 둔다.
    nonisolated static func dailyDurationSlices(
        from start: Date,
        to end: Date,
        calendar: Calendar = .current
    ) -> [DailyDurationSlice] {
        AppUsageDaySlicer.slices(from: start, to: end, calendar: calendar)
    }

    // MARK: - 유휴(자리 비움 후보) 세그먼트
    private struct PendingIdleSegment {
        let bundleIdentifier: String
        let appName: String
        let category: String
        let startedAt: Date   // 유휴가 시작된 순간 (= 마지막 입력 시각)
    }

    private var pendingIdleSegment: PendingIdleSegment?
    private var lastIdleSeconds: TimeInterval = 0

    @MainActor
    func setRepository(_ repository: AppUsageRepository) {
        self.repository = repository
        CategoryManager.shared.loadUserRules(from: repository)
    }

    func startTracking() {
        guard !isTracking else { return }
        isTracking = true

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.onPoll()
        }

        if let frontmost = NSWorkspace.shared.frontmostApplication {
            currentApp = frontmost
            currentAppStartTime = Date()
            currentSegmentStart = Date()
        }
    }

    func stopTracking() {
        let endedAt = Date()
        let target = resolveCurrentTarget()
        saveCurrentUsage(endedAt: endedAt, target: target)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        pollTimer?.invalidate()
        pollTimer = nil
        isTracking = false
    }

    @objc private func appDidActivate(_ notification: Notification) {
        let transitionedAt = Date()
        let previousTarget = resolveCurrentTarget()
        // 직전 앱의 일일 기록과 세션 세그먼트를 같은 기준으로 저장한 뒤 포커스 앱을 교체
        saveCurrentUsage(endedAt: transitionedAt, target: previousTarget)

        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            currentApp = app
            currentAppStartTime = transitionedAt
            currentSegmentStart = transitionedAt
        }

        // 앱 전환은 클릭/단축키 등 사용자 입력 → 유휴 상태에서 돌아온 신호일 수 있음
        checkIdleState(target: resolveCurrentTarget())
    }

    @objc private func systemWillSleep() {
        let endedAt = Date()
        let target = resolveCurrentTarget()
        saveCurrentUsage(endedAt: endedAt, target: target)

        // 슬립은 확실한 자리 비움 → 프롬프트 없이 pending 구간 자동 차감
        if let pending = pendingIdleSegment {
            subtractIdleTime(from: pending, endedAt: endedAt)
            pendingIdleSegment = nil
        }

        pollTimer?.invalidate()
        pollTimer = nil
    }

    @objc private func systemDidWake() {
        currentAppStartTime = Date()
        currentSegmentStart = Date()
        lastIdleSeconds = 0
        pendingIdleSegment = nil
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.onPoll()
        }
    }

    private func onPoll() {
        let endedAt = Date()
        let target = resolveCurrentTarget()
        saveCurrentUsage(endedAt: endedAt, target: target)
        checkIdleState(target: target)
    }

    private func saveCurrentUsage(
        endedAt: Date,
        target: ResolvedTarget?
    ) {
        guard repository != nil,
              TrackerStateStore.shared.shouldRecord(),
              let target else {
            currentAppStartTime = endedAt
            currentSegmentStart = endedAt
            return
        }

        // 새 앱 방문은 누적 5초가 되었을 때 처음부터 기록하고,
        // 이미 시작된 방문의 마지막 짧은 조각은 실제 종료 시각까지 함께 반영한다.
        guard saveCurrentSegment(endedAt: endedAt, target: target) else {
            return
        }
        saveCurrentAppUsage(endedAt: endedAt, target: target)
    }

    private func saveCurrentAppUsage(
        endedAt: Date,
        target: ResolvedTarget
    ) {
        guard let startTime = currentAppStartTime,
              let repository else { return }

        let elapsed = Int(endedAt.timeIntervalSince(startTime))
        guard elapsed > 0 else {
            currentAppStartTime = endedAt
            return
        }

        repository.applyUsageDelta(
            bundleIdentifier: target.bundleId,
            appName: target.appName,
            category: target.category,
            date: endedAt,
            deltaSeconds: elapsed
        )
        currentAppStartTime = endedAt
    }

    // MARK: - 타임라인 세그먼트 저장

    /// 현재 앱의 세그먼트(진입~현재)를 AppUsageSegment 로 기록한다.
    /// - 폴링/전환/슬립/종료 시점에 호출된다.
    /// - 같은 앱에 머무는 동안에는 직전 세그먼트를 연장해 `AppUsageSegment` 를 통계 원천으로 유지한다.
    /// - `Self.minimumSegmentSeconds` 미만의 새 앱 깜빡 전환은 저장하지 않는다.
    /// - 이미 저장 중인 앱의 짧은 마지막 조각은 실제 종료 시각까지 연장한다.
    private func saveCurrentSegment(
        endedAt: Date,
        target: ResolvedTarget
    ) -> Bool {
        guard let start = currentSegmentStart,
              let repository else { return false }

        // 이어붙이기·너무 짧은 구간 버리기는 저장소가 판단한다.
        let recorded = repository.recordSegment(
            appName: target.appName,
            bundleIdentifier: target.bundleId,
            category: target.category,
            from: start,
            to: endedAt,
            minimumSeconds: Self.minimumSegmentSeconds
        )
        guard recorded else { return false }
        currentSegmentStart = endedAt
        return true
    }

    // MARK: - 브라우저 URL 조회 (AppleScript)

    private func currentBrowserURL(for bundleId: String) -> String? {
        let source: String?
        switch bundleId {
        case "com.apple.Safari", "com.apple.SafariTechnologyPreview":
            source = """
            tell application id "\(bundleId)"
                if (count of windows) is 0 then return ""
                try
                    return URL of current tab of front window
                on error
                    return ""
                end try
            end tell
            """
        case let identifier where Constants.browserBundleIds.contains(identifier)
            && identifier != "org.mozilla.firefox"
            && identifier != "org.mozilla.firefoxdeveloperedition":
            source = """
            tell application id "\(identifier)"
                if (count of windows) is 0 then return ""
                try
                    return URL of active tab of front window
                on error
                    return ""
                end try
            end tell
            """
        default:
            source = nil
        }

        if let source,
           let script = NSAppleScript(source: source) {
            var errorDict: NSDictionary?
            let descriptor = script.executeAndReturnError(&errorDict)
            if errorDict == nil,
               let url = validWebURL(descriptor.stringValue) {
                return url
            }
        }

        guard let app = currentApp,
              app.bundleIdentifier == bundleId else {
            return nil
        }
        return accessibilityDocumentURL(for: app)
    }

    private func accessibilityDocumentURL(for app: NSRunningApplication) -> String? {
        let applicationElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedWindowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        ) == .success,
              let focusedWindowValue else {
            return nil
        }

        let focusedWindow = focusedWindowValue as! AXUIElement
        var documentValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedWindow,
            kAXDocumentAttribute as CFString,
            &documentValue
        ) == .success,
              let documentValue else {
            return nil
        }

        if let url = documentValue as? URL {
            return validWebURL(url.absoluteString)
        }
        return validWebURL(documentValue as? String)
    }

    private func validWebURL(_ value: String?) -> String? {
        guard let value,
              let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host != nil else {
            return nil
        }
        return value
    }

    nonisolated static func researchLabel(for url: String) -> String? {
        guard let components = URLComponents(string: url),
              let host = components.host?.lowercased() else {
            return nil
        }
        let path = components.path.lowercased()

        return Constants.researchURLRules.first { rule in
            let matchesHost = host == rule.host || host.hasSuffix(".\(rule.host)")
            guard matchesHost else { return false }
            guard let pathContains = rule.pathContains else { return true }
            return path.contains(pathContains)
        }?.label
    }

    private struct ResolvedTarget {
        let category: String
        let bundleId: String
        let appName: String
    }

    nonisolated static func shouldInspectWebsiteURL(
        isKnownBrowser: Bool,
        classification: CategoryManager.TrackingClassification,
        hasWebsiteRules: Bool
    ) -> Bool {
        guard classification != .excluded else { return false }
        return isKnownBrowser
            || (classification == .unclassified && hasWebsiteRules)
    }

    nonisolated static func categoryForNonBrowserApp(
        classification: CategoryManager.TrackingClassification,
        unmappedAppHandling: Constants.UnmappedAppHandling
    ) -> String? {
        switch classification {
        case let .category(mappedCategory):
            return mappedCategory
        case .unclassified:
            switch unmappedAppHandling {
            case .pendingClassification:
                return Constants.unclassifiedAppCategory
            case .recordAsOther:
                return Constants.categoryName("기타")
            case .doNotRecord:
                return nil
            }
        case .excluded:
            return nil
        }
    }

    private func resolveCurrentTarget() -> ResolvedTarget? {
        guard let app = currentApp,
              let bundleId = app.bundleIdentifier,
              let appName = app.localizedName else {
            return nil
        }
        return resolveTarget(bundleId: bundleId, appName: appName)
    }

    private func resolveTarget(bundleId: String, appName: String) -> ResolvedTarget? {
        let classification = CategoryManager.shared.trackingClassification(
            for: bundleId
        )
        guard classification != .excluded else { return nil }
        let isKnownBrowser = Constants.browserBundleIds.contains(bundleId)
        let shouldInspectWebsiteURL = Self.shouldInspectWebsiteURL(
            isKnownBrowser: isKnownBrowser,
            classification: classification,
            hasWebsiteRules: CategoryManager.shared.hasWebsiteRules
        )
        let url = shouldInspectWebsiteURL
            ? currentBrowserURL(for: bundleId) ?? ""
            : ""

        if let match = CategoryManager.shared.websiteMatch(for: url) {
            return ResolvedTarget(
                category: match.category,
                bundleId: "\(bundleId).website.\(match.domain)",
                appName: "\(appName) (\(match.domain))"
            )
        }

        if isKnownBrowser {
            if let label = Self.researchLabel(for: url) {
                return ResolvedTarget(
                    category: Constants.categoryName("조사"),
                    bundleId: "\(bundleId).research.\(label.lowercased().replacingOccurrences(of: " ", with: "-"))",
                    appName: "\(appName) (\(label))"
                )
            } else {
                return ResolvedTarget(category: Constants.categoryName("기타"), bundleId: bundleId, appName: appName)
            }
        } else {
            guard let category = Self.categoryForNonBrowserApp(
                classification: classification,
                unmappedAppHandling: Constants.storedUnmappedAppHandling()
            ) else { return nil }
            return ResolvedTarget(category: category, bundleId: bundleId, appName: appName)
        }
    }

    // MARK: - 유휴(자리 비움) 감지

    private func currentIdleSeconds() -> TimeInterval {
        // 모든 입력 이벤트(~0 = kCGAnyInputEventType)를 대상으로 마지막 입력 후 경과 시간을 조회
        guard let anyType = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyType)
    }

    private func checkIdleState(target: ResolvedTarget?) {
        let idleSeconds = currentIdleSeconds()
        defer { lastIdleSeconds = idleSeconds }

        if TrackerStateStore.shared.manualAwayStartedAt != nil {
            pendingIdleSegment = nil
            if idleSeconds < Constants.idleActiveReturnThresholdSeconds {
                TrackerStateStore.shared.clearManualAway()
                currentAppStartTime = Date()
                currentSegmentStart = Date()
            }
            return
        }

        // 이미 pending 상태 → 복귀 감지
        if let pending = pendingIdleSegment {
            if idleSeconds < Constants.idleActiveReturnThresholdSeconds {
                let endedAt = Date()
                pendingIdleSegment = nil
                presentIdlePrompt(for: pending, endedAt: endedAt)
            }
            return
        }

        // 프롬프트가 열려있는 동안엔 새 pending 만들지 않음 (사용자가 결정할 때까지 대기)
        if MainActor.assumeIsolated({ IdlePromptPanel.shared.isShowing }) {
            return
        }

        // pending 아님 → 임계 초과 시 생성
        guard let target else { return }

        let thresholdSeconds = IdleThresholdStore.shared.seconds(for: target.category)
        if idleSeconds >= TimeInterval(thresholdSeconds) {
            let startedAt = Date().addingTimeInterval(-idleSeconds)
            pendingIdleSegment = PendingIdleSegment(
                bundleIdentifier: target.bundleId,
                appName: target.appName,
                category: target.category,
                startedAt: startedAt
            )
        }
    }

    private func presentIdlePrompt(for segment: PendingIdleSegment, endedAt: Date) {
        let emoji = Constants.categoryEmoji(for: segment.category)
        MainActor.assumeIsolated {
            IdlePromptPanel.shared.show(
                appName: segment.appName,
                categoryEmoji: emoji,
                category: segment.category,
                startedAt: segment.startedAt,
                endedAt: endedAt,
                onConfirm: {
                    // 유지: 이미 저장된 durationSeconds 그대로 사용
                },
                onAway: { [weak self] in
                    self?.subtractIdleTime(from: segment, endedAt: endedAt)
                }
            )
        }
    }

    private func subtractIdleTime(from segment: PendingIdleSegment, endedAt: Date) {
        repository?.subtractIdleTime(
            appName: segment.appName,
            bundleIdentifier: segment.bundleIdentifier,
            category: segment.category,
            from: segment.startedAt,
            to: endedAt,
            minimumSeconds: Self.minimumSegmentSeconds
        )
    }
}
