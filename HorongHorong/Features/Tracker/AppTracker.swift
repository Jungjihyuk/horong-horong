import AppKit
import SwiftData

@Observable
final class AppTracker: @unchecked Sendable {
    private var currentApp: NSRunningApplication?
    private var currentAppStartTime: Date?
    // 집중도 분석용 세그먼트 구간 시작 (앱 전환/슬립 복귀 시에만 리셋 — 5초 폴링으로는 리셋되지 않음)
    private var currentSegmentStart: Date?
    private var pollTimer: Timer?
    private var trackingContext: ModelContext?
    var isTracking: Bool = false

    // 세그먼트 최소 길이(초). 깜빡 포커스 이동은 저장하지 않음
    static let minimumSegmentSeconds: TimeInterval = 3

    static func shouldPersistSegment(
        elapsed: TimeInterval,
        hasPreviousSegment: Bool
    ) -> Bool {
        guard elapsed >= 0 else { return false }
        return hasPreviousSegment || elapsed >= minimumSegmentSeconds
    }

    // MARK: - 유휴(자리 비움 후보) 세그먼트
    private struct PendingIdleSegment {
        let bundleIdentifier: String
        let appName: String
        let category: String
        let date: Date        // startOfDay — AppUsageRecord 조회용
        let startedAt: Date   // 유휴가 시작된 순간 (= 마지막 입력 시각)
    }

    private var pendingIdleSegment: PendingIdleSegment?
    private var lastIdleSeconds: TimeInterval = 0

    func setModelContainer(_ container: ModelContainer) {
        trackingContext = ModelContext(container)
        trackingContext?.autosaveEnabled = false
        CategoryManager.shared.loadUserRules(from: trackingContext!)
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
        saveCurrentAppUsage(endedAt: endedAt)
        saveCurrentSegment(endedAt: endedAt)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        pollTimer?.invalidate()
        pollTimer = nil
        isTracking = false
    }

    @objc private func appDidActivate(_ notification: Notification) {
        let transitionedAt = Date()
        saveCurrentAppUsage(endedAt: transitionedAt)
        // 직전 앱의 세그먼트를 먼저 저장한 뒤에 포커스 앱을 교체
        saveCurrentSegment(endedAt: transitionedAt)

        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            currentApp = app
            currentAppStartTime = transitionedAt
            currentSegmentStart = transitionedAt
        }

        // 앱 전환은 클릭/단축키 등 사용자 입력 → 유휴 상태에서 돌아온 신호일 수 있음
        checkIdleState()
    }

    @objc private func systemWillSleep() {
        let endedAt = Date()
        saveCurrentAppUsage(endedAt: endedAt)
        saveCurrentSegment(endedAt: endedAt)

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
        saveCurrentAppUsage(endedAt: endedAt)
        saveCurrentSegment(endedAt: endedAt)
        checkIdleState()
    }

    private func saveCurrentAppUsage(endedAt: Date) {
        guard let app = currentApp,
              let startTime = currentAppStartTime,
              let bundleId = app.bundleIdentifier,
              let appName = app.localizedName,
              let trackingContext else { return }

        // 추적이 꺼져있거나(민감 작업/휴가) 비활성 기간이면 저장 건너뛰고 타이머만 리셋.
        guard TrackerStateStore.shared.shouldRecord() else {
            currentAppStartTime = endedAt
            return
        }

        let elapsed = Int(endedAt.timeIntervalSince(startTime))
        guard elapsed > 0 else { return }

        // 카테고리/대상 결정: 브라우저 엔터 URL 은 pseudo bundleId 로 분리 저장
        // (예: com.google.Chrome.youtube → "Google Chrome (YouTube)")
        guard let target = resolveTarget(bundleId: bundleId, appName: appName) else {
            // 추적 대상 아님: 타이머만 리셋하고 저장은 건너뜀
            currentAppStartTime = endedAt
            return
        }

        let today = Calendar.current.startOfDay(for: endedAt)
        let targetBundleId = target.bundleId
        let targetDate = today

        let descriptor = FetchDescriptor<AppUsageRecord>(
            predicate: #Predicate {
                $0.bundleIdentifier == targetBundleId && $0.date == targetDate
            }
        )

        if let existing = try? trackingContext.fetch(descriptor).first {
            existing.durationSeconds += elapsed
            // 브라우저는 URL 에 따라 카테고리가 매 번 달라질 수 있으므로 갱신
            if existing.category != target.category {
                existing.category = target.category
            }
        } else {
            let record = AppUsageRecord(
                appName: target.appName,
                bundleIdentifier: target.bundleId,
                category: target.category,
                date: today
            )
            record.durationSeconds = elapsed
            trackingContext.insert(record)
        }

        try? trackingContext.save()
        currentAppStartTime = endedAt
    }

    // MARK: - 타임라인 세그먼트 저장

    /// 현재 앱의 세그먼트(진입~현재)를 AppUsageSegment 로 기록한다.
    /// - 폴링/전환/슬립/종료 시점에 호출된다.
    /// - 같은 앱에 머무는 동안에는 직전 세그먼트를 연장해 `AppUsageSegment` 를 통계 원천으로 유지한다.
    /// - `Self.minimumSegmentSeconds` 미만의 새 앱 깜빡 전환은 저장하지 않는다.
    /// - 이미 저장 중인 앱의 짧은 마지막 조각은 실제 종료 시각까지 연장한다.
    private func saveCurrentSegment(endedAt: Date) {
        guard let app = currentApp,
              let start = currentSegmentStart,
              let bundleId = app.bundleIdentifier,
              let appName = app.localizedName,
              let trackingContext else { return }

        // 추적 비활성(민감/휴가) 시 세그먼트 저장도 건너뛴다.
        guard TrackerStateStore.shared.shouldRecord() else {
            currentSegmentStart = endedAt
            return
        }

        let elapsed = endedAt.timeIntervalSince(start)
        guard let target = resolveTarget(bundleId: bundleId, appName: appName) else {
            currentSegmentStart = endedAt
            return
        }

        let targetBundleId = target.bundleId
        let targetCategory = target.category
        let mergeLowerBound = start.addingTimeInterval(-1)
        let mergeUpperBound = start.addingTimeInterval(1)
        let descriptor = FetchDescriptor<AppUsageSegment>(
            predicate: #Predicate {
                $0.bundleIdentifier == targetBundleId &&
                $0.category == targetCategory &&
                $0.endTime >= mergeLowerBound &&
                $0.endTime <= mergeUpperBound
            },
            sortBy: [SortDescriptor(\.endTime, order: .reverse)]
        )

        let previous = try? trackingContext.fetch(descriptor).first
        let isProductivityManagementApp =
            Constants.isProductivityManagementCategory(targetCategory)
        guard (isProductivityManagementApp && elapsed > 0) || Self.shouldPersistSegment(
            elapsed: elapsed,
            hasPreviousSegment: previous != nil
        ) else {
            currentSegmentStart = endedAt
            return
        }

        if let previous {
            previous.appName = target.appName
            previous.endTime = endedAt
        } else {
            let segment = AppUsageSegment(
                appName: target.appName,
                bundleIdentifier: target.bundleId,
                category: target.category,
                startTime: start,
                endTime: endedAt
            )
            trackingContext.insert(segment)
        }
        try? trackingContext.save()
        currentSegmentStart = endedAt
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

    static func entertainmentLabel(for url: String) -> String? {
        guard !url.isEmpty else { return nil }
        let lower = url.lowercased()
        return Constants.entertainmentURLHosts.first { lower.contains($0.host) }?.label
    }

    static func researchLabel(for url: String) -> String? {
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

    private func resolveTarget(bundleId: String, appName: String) -> ResolvedTarget? {
        if CategoryManager.shared.trackingClassification(for: bundleId) == .excluded {
            return nil
        }

        let isKnownBrowser = Constants.browserBundleIds.contains(bundleId)
        let url = isKnownBrowser || CategoryManager.shared.hasWebsiteRules
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
            if let label = Self.entertainmentLabel(for: url) {
                return ResolvedTarget(
                    category: Constants.categoryName("엔터"),
                    bundleId: "\(bundleId).\(label.lowercased())",
                    appName: "\(appName) (\(label))"
                )
            } else if let label = Self.researchLabel(for: url) {
                return ResolvedTarget(
                    category: Constants.categoryName("조사"),
                    bundleId: "\(bundleId).research.\(label.lowercased().replacingOccurrences(of: " ", with: "-"))",
                    appName: "\(appName) (\(label))"
                )
            } else {
                return ResolvedTarget(category: Constants.categoryName("기타"), bundleId: bundleId, appName: appName)
            }
        } else {
            let category: String
            switch CategoryManager.shared.trackingClassification(for: bundleId) {
            case let .category(mappedCategory):
                category = mappedCategory
            case .unclassified:
                category = Constants.unclassifiedAppCategory
            case .excluded:
                return nil
            }
            return ResolvedTarget(category: category, bundleId: bundleId, appName: appName)
        }
    }

    // MARK: - 유휴(자리 비움) 감지

    private func currentIdleSeconds() -> TimeInterval {
        // 모든 입력 이벤트(~0 = kCGAnyInputEventType)를 대상으로 마지막 입력 후 경과 시간을 조회
        guard let anyType = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyType)
    }

    private func checkIdleState() {
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
        guard let app = currentApp,
              let bundleId = app.bundleIdentifier,
              let appName = app.localizedName else { return }

        guard let target = resolveTarget(bundleId: bundleId, appName: appName) else { return }

        let thresholdSeconds = IdleThresholdStore.shared.seconds(for: target.category)
        if idleSeconds >= TimeInterval(thresholdSeconds) {
            let startedAt = Date().addingTimeInterval(-idleSeconds)
            pendingIdleSegment = PendingIdleSegment(
                bundleIdentifier: target.bundleId,
                appName: target.appName,
                category: target.category,
                date: Calendar.current.startOfDay(for: startedAt),
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
        guard let trackingContext else { return }
        let idleStart = segment.startedAt
        let idleEnd = endedAt
        let idleSeconds = Int(idleEnd.timeIntervalSince(idleStart))
        guard idleSeconds > 0 else { return }

        // (1) 일일 총사용 시간 차감
        let bundleId = segment.bundleIdentifier
        let date = segment.date
        let recordDescriptor = FetchDescriptor<AppUsageRecord>(
            predicate: #Predicate {
                $0.bundleIdentifier == bundleId && $0.date == date
            }
        )
        if let record = try? trackingContext.fetch(recordDescriptor).first {
            record.durationSeconds = max(0, record.durationSeconds - idleSeconds)
        }

        // (2) 타임라인 세그먼트 보정 — idle 구간과 겹치는 세그먼트를 잘라내거나 삭제
        let segDescriptor = FetchDescriptor<AppUsageSegment>(
            predicate: #Predicate { seg in
                seg.startTime < idleEnd && seg.endTime > idleStart
            }
        )
        let overlapping = (try? trackingContext.fetch(segDescriptor)) ?? []
        let minSec = Self.minimumSegmentSeconds

        for seg in overlapping {
            let origStart = seg.startTime
            let origEnd = seg.endTime

            if origStart >= idleStart && origEnd <= idleEnd {
                // 세그먼트가 idle 구간에 완전히 포함됨 → 삭제
                trackingContext.delete(seg)
            } else if origStart < idleStart && origEnd <= idleEnd {
                // 세그먼트 뒷부분이 idle 에 걸림 → endTime 을 idleStart 로 축소
                seg.endTime = idleStart
                if seg.endTime.timeIntervalSince(seg.startTime) < minSec {
                    trackingContext.delete(seg)
                }
            } else if origStart >= idleStart && origEnd > idleEnd {
                // 세그먼트 앞부분이 idle 에 걸림 → startTime 을 idleEnd 로 이동
                seg.startTime = idleEnd
                if seg.endTime.timeIntervalSince(seg.startTime) < minSec {
                    trackingContext.delete(seg)
                }
            } else {
                // idle 이 세그먼트 중간에 들어가 있음 → 앞뒤로 분할
                let frontDuration = idleStart.timeIntervalSince(origStart)
                let backDuration = origEnd.timeIntervalSince(idleEnd)
                let app = seg.appName
                let bundle = seg.bundleIdentifier
                let cat = seg.category
                let isManual = seg.isManual
                let isUserModified = seg.isUserModified || seg.isManual

                if frontDuration >= minSec {
                    seg.endTime = idleStart
                } else {
                    trackingContext.delete(seg)
                }
                if backDuration >= minSec {
                    let tail = AppUsageSegment(
                        appName: app,
                        bundleIdentifier: bundle,
                        category: cat,
                        startTime: idleEnd,
                        endTime: origEnd,
                        isManual: isManual,
                        isUserModified: isUserModified
                    )
                    trackingContext.insert(tail)
                }
            }
        }

        try? trackingContext.save()
    }
}
