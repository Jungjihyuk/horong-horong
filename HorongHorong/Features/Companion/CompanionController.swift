import HorongAI
import AppKit
import Combine
import SwiftData
import SwiftUI

/// 루미롱 컴패니언의 생명주기 담당.
/// 설정·포모도로 상태를 보고 오버레이를 띄우거나 숨기고, 활동 반경 안에서 걷게 하며,
/// 정해진 시각에 오늘 일정 브리핑을 띄운다.
@MainActor
final class CompanionController {
    private enum Mode: Equatable {
        case hidden
        case roaming
        case breakTime
    }

    private let appState: AppState
    private let state: CompanionPresentationState
    private let overlay: CompanionOverlayPanel

    private var modelContainer: ModelContainer?
    private var tickTimer: Timer?
    private var briefingTimer: Timer?
    private var systemTimeObservers: [NSObjectProtocol] = []
    private var onboardingRequestObserver: NSObjectProtocol?
    private var defaultsObserver: NSObjectProtocol?
    private var timerStateObservationTask: Task<Void, Never>?
    private var bubbleDismissTask: Task<Void, Never>?

    private var chatProviderCache: CompanionChatProvider?
    private var isOllamaReachable = false
    private var chatSession: CompanionChatSession?
    private var appliedUserProfile: CompanionUserProfile?
    private var appliedChatProvider: String?
    private var appliedOllamaModel: String?
    private var appliedMLXModel: String?
    private var appliedBubbleSize: String?
    private var chatReplyTask: Task<Void, Never>?
    private var moodResetTask: Task<Void, Never>?
    private let memoStore = CompanionMemoStore()
    private var onboardingSteps: [CompanionOnboardingStep] = []
    private var onboardingIndex = 0

    /// 감정 동작을 보여줄 시간. 이후에는 듣는 자세로 돌아온다.
    private static let moodReactionSeconds: Double = 2.5

    /// 집중 넛지를 띄워두는 시간. 집중을 깨지 않을 만큼만 머문다.
    private static let focusNudgeSeconds: Double = 6

    private var focusScoreMonitor: FocusScoreMonitor?
    /// 마지막으로 띄운 집중 넛지 문구. 자동 소멸 예약이 자기가 띄운 말풍선만 지우도록 표시해 둔다.
    private var focusNudgeMessage: String?

    private var engine: CompanionRoamingEngine?
    private var mode: Mode = .hidden
    private var appliedRoamingRegion: CGRect?
    private var lastTickAt: Date?
    private var animationElapsed: Double = 0
    private var generator = SystemRandomNumberGenerator()

    /// 화면 갱신 주기. 애니메이션이 자연스러운 선에서 가장 성긴 값으로 둬 CPU·배터리 부담을 줄인다.
    private static let tickInterval: TimeInterval = 1.0 / 20.0

    init(appState: AppState) {
        self.appState = appState
        let character = CompanionRegistry.character(for: Self.selectedIdentifier)
        self.state = CompanionPresentationState(character: character)
        self.overlay = CompanionOverlayPanel(state: state)

        state.onCharacterTap = { [weak self] in self?.toggleChat() }
        state.onCloseChat = { [weak self] in self?.endChat() }
        state.onSendMessage = { [weak self] message in self?.send(message) }
        state.onSaveMessageAsMemo = { [weak self] messageID, icon, isTodayTask in
            self?.saveChatMessageAsMemo(
                messageID: messageID,
                icon: icon,
                isTodayTask: isTodayTask
            )
        }
        state.onOpenMemoTab = {
            CompanionOnboardingPresenter.showMemoTab()
        }
        state.onDragBegan = { [weak self] in self?.beginDrag() }
        state.onDragChanged = { [weak self] in self?.updateDrag() }
        state.onDragEnded = { [weak self] in self?.endDrag() }
        state.onTurnOff = { [weak self] in self?.turnOff() }
        state.onDismissBubble = { [weak self] in self?.dismissBubble() }
        state.onShowSchedule = { [weak self] in self?.showScheduleOnDemand() }
        state.onRequestMenu = { [weak self] in self?.toggleMenu() }
        state.onDismissMenu = { [weak self] in self?.hideMenu() }
        state.onAdvanceOnboarding = { [weak self] in self?.advanceOnboarding() }
        state.onFinishOnboarding = { [weak self] in self?.finishOnboarding() }
        state.onStartOnboarding = { [weak self] in self?.startOnboarding() }
    }

    func start(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer

        let monitor = FocusScoreMonitor(
            appState: appState,
            modelContainer: modelContainer
        ) { [weak self] message in
            self?.presentFocusNudge(message) ?? false
        }
        focusScoreMonitor = monitor
        monitor.start()

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applySettings()
            }
        }

        onboardingRequestObserver = NotificationCenter.default.addObserver(
            forName: .companionStartOnboarding,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.startOnboarding() }
        }

        observeTimerState()
        observeSystemTimeChanges()
        applySettings()
        startOnboardingIfNeeded()
    }

    func stop() {
        CompanionOnboardingDemoStore.shared.stop()
        focusScoreMonitor?.stop()
        focusScoreMonitor = nil
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
        defaultsObserver = nil
        timerStateObservationTask?.cancel()
        timerStateObservationTask = nil
        bubbleDismissTask?.cancel()
        bubbleDismissTask = nil
        chatReplyTask?.cancel()
        chatReplyTask = nil
        moodResetTask?.cancel()
        moodResetTask = nil
        briefingTimer?.invalidate()
        briefingTimer = nil
        CompanionSpotlight.shared.hide()
        for observer in systemTimeObservers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        systemTimeObservers.removeAll()
        if let onboardingRequestObserver {
            NotificationCenter.default.removeObserver(onboardingRequestObserver)
        }
        onboardingRequestObserver = nil
        stopTicking()
        overlay.hide()
        mode = .hidden
    }

    /// 설정한 시각에 정확히 한 번 깨어나도록 예약한다.
    ///
    /// 브리핑을 쓰지 않으면 타이머를 걸지 않는다.
    /// 잠자기·시계 변경으로 예약이 어긋나는 경우는 `observeSystemTimeChanges()` 가 다시 잡는다.
    private func updateBriefingSchedule() {
        briefingTimer?.invalidate()
        briefingTimer = nil
        guard Self.isEnabled, Self.isBriefingEnabled else { return }

        let fireDate = CompanionBriefingSchedule.nextFireDate(
            after: Date(),
            hour: Self.briefingHour,
            minute: Self.briefingMinute
        )
        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.deliverBriefingIfDue()
                // 다음 날치를 다시 예약한다.
                self.updateBriefingSchedule()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        briefingTimer = timer
    }

    /// 잠자기에서 깨어나거나 시계·시간대가 바뀌면 예약이 어긋난다.
    /// 다시 예약하고, 자는 사이에 지나가 버린 브리핑이 있으면 그 자리에서 전달한다.
    private func observeSystemTimeChanges() {
        let handler: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.updateBriefingSchedule()
                self.deliverBriefingIfDue()
            }
        }
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange, .NSCalendarDayChanged] {
            systemTimeObservers.append(
                NotificationCenter.default.addObserver(
                    forName: name, object: nil, queue: .main, using: handler
                )
            )
        }
        systemTimeObservers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: handler
            )
        )
    }

    // MARK: - 설정 반영

    private func applySettings() {
        updateBriefingSchedule()

        // 말풍선 크기를 바꾸면 창도 같이 커져야 늘어난 내용이 잘리지 않는다.
        let bubbleSize = UserDefaults.standard.string(
            forKey: Constants.AppStorageKey.companionBubbleSize
        ) ?? Constants.defaultCompanionBubbleSize
        if bubbleSize != appliedBubbleSize {
            appliedBubbleSize = bubbleSize
            overlay.refreshSize()
        }

        let selectedProvider = UserDefaults.standard.string(
            forKey: Constants.AppStorageKey.companionChatProvider
        ) ?? Constants.defaultCompanionChatProvider
        
        let ollamaModel = UserDefaults.standard.string(
            forKey: Constants.AppStorageKey.companionOllamaModel
        ) ?? Constants.defaultCompanionOllamaModel
        
        let mlxModel = UserDefaults.standard.string(
            forKey: Constants.AppStorageKey.companionMLXModel
        ) ?? Constants.defaultCompanionMLXModel

        if selectedProvider != appliedChatProvider || ollamaModel != appliedOllamaModel || mlxModel != appliedMLXModel {
            appliedChatProvider = selectedProvider
            appliedOllamaModel = ollamaModel
            appliedMLXModel = mlxModel
            
            chatProviderCache = nil
            chatSession = nil
            if selectedProvider == Constants.CompanionChatProviderKind.ollama.rawValue {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isOllamaReachable = await OllamaChatClient.isReachable(
                        endpoint: UserDefaults.standard.string(
                            forKey: Constants.NewsStorageKey.ollamaEndpoint
                        ) ?? Constants.defaultNewsOllamaEndpoint
                    )
                    self.chatProviderCache = nil
                }
            }
        }

        let character = CompanionRegistry.character(for: Self.selectedIdentifier)
        if character != state.character {
            state.character = character
        }

        let desiredMode = resolveMode()
        guard desiredMode != mode else {
            // UserDefaults 는 앱 곳곳에서 자주 바뀌므로, 활동 영역이 실제로 달라졌을 때만
            // 무대를 다시 잡는다. (매번 다시 잡으면 마우스가 있는 화면으로 순간이동한다)
            let region = Self.roamingRegion
            if desiredMode != .hidden, region != appliedRoamingRegion {
                appliedRoamingRegion = region
                rebuildEngine(force: true)
            }
            return
        }
        transition(to: desiredMode)
    }

    private func resolveMode() -> Mode {
        guard Self.isEnabled else { return .hidden }
        switch appState.timerState {
        case .focusing, .paused:
            return Self.hidesDuringFocus ? .hidden : .roaming
        case .breaking, .breakAlert:
            return .breakTime
        case .idle:
            return .roaming
        }
    }

    private func transition(to newMode: Mode) {
        let previousMode = mode
        mode = newMode

        // 숨거나 상태가 바뀌면 대화는 먼저 정리한다.
        if newMode != previousMode, state.isChatting {
            endChat()
        }

        switch newMode {
        case .hidden:
            // 집중을 시작해 숨는 경우에는 인사를 남기고 사라진다.
            if previousMode != .hidden, Self.isEnabled {
                presentFarewellThenHide()
            } else {
                bubbleDismissTask?.cancel()
                stopTicking()
                overlay.hide()
            }

        case .roaming:
            showOverlayIfNeeded()
            if previousMode == .hidden {
                presentTemporaryBubble(
                    CompanionBubble(message: line(\.greeting)),
                    animation: .waving,
                    seconds: 3
                )
            } else {
                state.bubble = nil
            }
            deliverBriefingIfDue()

        case .breakTime:
            showOverlayIfNeeded()
            presentBreakMenu()
        }
    }

    private func showOverlayIfNeeded() {
        appliedRoamingRegion = Self.roamingRegion
        rebuildEngine(force: !overlay.isVisible)
        overlay.show()
        startTicking()
    }

    // MARK: - 이동

    /// 지정한 활동 영역(없으면 마우스가 놓인 화면 전체)을 무대로 삼는다.
    /// 영역은 항상 실제 화면 안으로 잘라내므로, 영역을 그렸던 디스플레이를 빼도 화면 밖으로 나가지 않는다.
    private func rebuildEngine(force: Bool = false) {
        let region = Self.roamingRegion
        let screens = NSScreen.screens.map(\.visibleFrame)
        guard let stage = CompanionRoamingRegion.stage(
            for: region,
            fallbackPoint: NSEvent.mouseLocation,
            screens: screens,
            mainScreen: NSScreen.main?.visibleFrame
        ) else {
            engine = nil
            return
        }

        let bounds = CompanionRoamingRegion.bounds(
            region: region,
            stage: stage,
            spriteSize: Constants.companionSpriteSize
        )

        if !force, let engine, engine.bounds == bounds {
            return
        }

        let start = engine?.position ?? CGPoint(x: bounds.midX, y: bounds.midY)
        engine = CompanionRoamingEngine(bounds: bounds, start: start)
        moveOverlay()
    }

    private func moveOverlay() {
        guard let engine else { return }
        overlay.move(spriteOrigin: engine.position)
    }

    private func moveOverlayToFocusNudgeCenter() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        guard let stage = screen?.visibleFrame else {
            moveOverlay()
            return
        }
        overlay.move(
            spriteOrigin: CompanionRoamingRegion.centeredSpriteOrigin(
                stage: stage,
                spriteSize: Constants.companionSpriteSize
            )
        )
    }

    private func startTicking() {
        guard tickTimer == nil else { return }
        lastTickAt = Date()
        animationElapsed = 0
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        // 스크롤·드래그 중에도 애니메이션이 멈추지 않도록 common 모드에 등록한다.
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func stopTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
        lastTickAt = nil
    }

    private func tick() {
        let now = Date()
        let delta = lastTickAt.map { now.timeIntervalSince($0) } ?? Self.tickInterval
        lastTickAt = now

        // 대화·말풍선이 떠 있는 동안에는 그쪽 동작을 유지한다.
        if mode == .roaming, !state.isChatting, state.bubble == nil {
            if state.isMenuVisible || state.isHovering {
                // 커서를 올리거나 메뉴를 열면 멈춰 선다.
                // 위치만 고정하고 걷는 애니메이션을 그대로 두면 제자리에서 출렁인다.
                setAnimation(.idle)
            } else if engine != nil {
                engine?.advance(by: delta, using: &generator)
                moveOverlay()
                setAnimation(engine?.animation ?? .idle)
            }
        }

        advanceFrame(by: delta)
    }

    private func setAnimation(_ animation: CompanionAnimation) {
        guard state.animation != animation else { return }
        state.animation = animation
        state.frameIndex = 0
        animationElapsed = 0
    }

    private func advanceFrame(by delta: Double) {
        let animation = state.animation
        let frameCount = CompanionSpriteLoader.shared.frames(
            for: state.character,
            animation: animation
        ).count
        guard frameCount > 1 else { return }

        animationElapsed += delta
        let rawIndex = Int(animationElapsed / animation.frameDuration)
        let index = animation.loops ? rawIndex % frameCount : min(rawIndex, frameCount - 1)
        if index != state.frameIndex {
            state.frameIndex = index
        }
    }

    // MARK: - 포모도로 연동

    /// `AppState` 는 `@Observable` 이므로 타이머 상태 변화만 골라 추적한다.
    /// (TimerManager 를 건드리지 않고 생명주기를 붙이기 위한 최소 연결)
    private func observeTimerState() {
        timerStateObservationTask?.cancel()
        timerStateObservationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = self.appState.timerState
                    } onChange: {
                        continuation.resume()
                    }
                }
                guard !Task.isCancelled else { return }
                self.applySettings()
            }
        }
    }

    private func presentFarewellThenHide() {
        state.bubble = CompanionBubble(message: line(\.focusFarewell))
        setAnimation(.waving)
        overlay.show()
        startTicking()

        bubbleDismissTask?.cancel()
        bubbleDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled, self.mode == .hidden else { return }
            self.state.bubble = nil
            self.stopTicking()
            self.overlay.hide()
        }
    }

    // MARK: - 쉬는 시간 상호작용

    private func presentBreakMenu() {
        bubbleDismissTask?.cancel()
        setAnimation(.waiting)
        state.bubble = CompanionBubble(
            headline: "쉬는 시간",
            message: line(\.breakInvitation),
            actions: [
                CompanionBubbleAction(title: "놀기") { [weak self] in
                    guard let self else { return }
                    self.presentTemporaryBubble(
                        CompanionBubble(message: self.line(\.play)),
                        animation: .jumping,
                        seconds: 4,
                        thenRestoreBreakMenu: true
                    )
                },
                CompanionBubbleAction(title: "쉬기") { [weak self] in
                    guard let self else { return }
                    self.presentTemporaryBubble(
                        CompanionBubble(message: self.line(\.rest)),
                        animation: .idle,
                        seconds: 4,
                        thenRestoreBreakMenu: true
                    )
                },
                CompanionBubbleAction(title: "대화하기") { [weak self] in
                    self?.beginChat()
                },
            ]
        )
    }

    // MARK: - 온보딩

    /// 아직 본 적 없고 쓴 흔적도 없을 때만 저절로 시작한다.
    private func startOnboardingIfNeeded() {
        if ProcessInfo.processInfo.environment["HORONG_FORCE_ONBOARDING"] == "1" {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                self?.startOnboarding()
            }
            return
        }
        guard CompanionOnboardingTrigger.shouldStartAutomatically(
            hasSeenOnboarding: UserDefaults.standard.bool(
                forKey: Constants.AppStorageKey.companionOnboardingSeen
            ),
            memoCount: storedCount(of: Memo.self),
            focusSessionCount: storedCount(of: FocusSession.self)
        ) else { return }

        // 앱이 막 뜬 직후라 팝오버가 준비될 시간을 준다.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.startOnboarding()
        }
    }

    private func storedCount<T: PersistentModel>(of type: T.Type) -> Int {
        guard let modelContainer else { return 0 }
        return (try? modelContainer.mainContext.fetchCount(FetchDescriptor<T>())) ?? 0
    }

    /// 설정에서 직접 시작할 때도 이 경로를 쓴다.
    func startOnboarding() {
        let scenarios = CompanionOnboardingScript.loadFromBundle()
        let steps = scenarios.flatMap(\.steps)
        guard !steps.isEmpty else { return }

        CompanionOnboardingDemoStore.shared.startIfNeeded(
            memoCount: storedCount(of: Memo.self),
            focusSessionCount: storedCount(of: FocusSession.self),
            achievementGoalCount: storedCount(of: AchievementGoalRecord.self)
        )

        // 컴패니언이 꺼져 있으면 켜야 호로롱이 설명할 수 있다.
        if !Self.isEnabled {
            UserDefaults.standard.set(true, forKey: Constants.AppStorageKey.companionEnabled)
            applySettings()
        }

        endChat()
        hideMenu()
        onboardingSteps = steps
        onboardingIndex = 0
        CompanionSpotlight.shared.show()
        presentCurrentOnboardingStep()
    }

    private var isOnboarding: Bool { !onboardingSteps.isEmpty }

    private func presentCurrentOnboardingStep() {
        guard onboardingIndex < onboardingSteps.count else {
            finishOnboarding()
            return
        }
        let step = onboardingSteps[onboardingIndex]
        if let screen = step.screen {
            CompanionOnboardingPresenter.show(screen)
        }
        if let action = step.action {
            // 화면이 뜬 뒤에 눌러야 한다.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                CompanionOnboardingPresenter.perform(action)
            }
        }
        // 화면이 그려진 뒤에 강조해야 테두리가 제자리에 붙는다.
        let highlight = step.highlight ?? step.screen.flatMap(Self.defaultHighlight)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            CompanionHighlightCenter.shared.highlight(highlight)
        }

        let isFirst = onboardingIndex == 0
        let isLast = onboardingIndex == onboardingSteps.count - 1
        var actions: [CompanionBubbleAction] = []
        if !isFirst {
            actions.append(
                CompanionBubbleAction(title: "이전") { [weak self] in
                    self?.rewindOnboarding()
                }
            )
        }
        actions.append(
            CompanionBubbleAction(title: isLast ? "다 봤어요" : "다음") { [weak self] in
                self?.advanceOnboarding()
            }
        )

        // 앞서 걸린 자동 삭제 예약(인사 말풍선 등)이 온보딩 말풍선을 지우지 않게 끊는다.
        bubbleDismissTask?.cancel()
        bubbleDismissTask = nil
        state.bubble = CompanionBubble(
            headline: "\(onboardingIndex + 1)/\(onboardingSteps.count) · \(step.title)",
            message: isFirst && CompanionOnboardingDemoStore.shared.isActive
                ? step.line + " 안내 중에는 실제 기록에 저장되지 않는 예시 데이터도 보여드릴게요."
                : step.line,
            isDismissible: true,
            actions: actions
        )
        overlay.setPresentation(expanded: false, acceptsInput: false)
        setAnimation(onboardingIndex == 0 ? .waving : .review)
    }

    /// 화면만 지정하고 강조 대상을 안 적었으면 그 화면의 대표 요소를 가리킨다.
    private static func defaultHighlight(for screen: CompanionOnboardingScreen) -> String? {
        switch screen {
        case .popoverTimer: return "tab.timer"
        case .popoverMemo: return "tab.memo"
        case .popoverStats: return "tab.stats"
        case .popoverAchievement: return "tab.achievement"
        case .windowStats, .settingsCompanion, .settingsMemo: return nil
        }
    }

    private func rewindOnboarding() {
        guard isOnboarding, onboardingIndex > 0 else { return }
        onboardingIndex -= 1
        presentCurrentOnboardingStep()
    }

    private func advanceOnboarding() {
        guard isOnboarding else { return }
        onboardingIndex += 1
        presentCurrentOnboardingStep()
    }

    /// 끝까지 봤든 중간에 닫았든, 다시 자동으로 뜨지는 않게 표시해 둔다.
    private func finishOnboarding() {
        guard isOnboarding else { return }
        onboardingSteps = []
        onboardingIndex = 0
        UserDefaults.standard.set(true, forKey: Constants.AppStorageKey.companionOnboardingSeen)
        CompanionOnboardingDemoStore.shared.stop()
        CompanionHighlightCenter.shared.highlight(nil)
        CompanionSpotlight.shared.hide()
        CompanionOnboardingPresenter.closeAll()
        state.bubble = nil
        overlay.setPresentation(expanded: false, acceptsInput: false)
        setAnimation(.idle)
    }

    // MARK: - 끌어서 옮기기 / 끄기

    private var dragGrabOffset: CGSize?

    /// 드래그 중에는 SwiftUI 의 translation 대신 전역 마우스 좌표를 쓴다.
    /// 창 자체가 커서를 따라 움직여 제스처 좌표계가 같이 흔들리기 때문이다.
    private func beginDrag() {
        guard let engine else { return }
        let mouse = NSEvent.mouseLocation
        dragGrabOffset = CGSize(
            width: mouse.x - engine.position.x,
            height: mouse.y - engine.position.y
        )
        // 말풍선은 그대로 둔다. 옮기려고 잡았을 뿐인데 보던 설명이 사라지면 안 된다.
        setAnimation(.waiting)
    }

    private func updateDrag() {
        guard let offset = dragGrabOffset else { return }
        let mouse = NSEvent.mouseLocation
        engine?.reposition(
            to: CGPoint(x: mouse.x - offset.width, y: mouse.y - offset.height)
        )
        moveOverlay()
    }

    private func endDrag() {
        dragGrabOffset = nil
        // 설명 중이면 그 자세를 유지한다.
        setAnimation(state.bubble == nil ? .idle : .waiting)
    }

    private func turnOff() {
        endChat()
        UserDefaults.standard.set(false, forKey: Constants.AppStorageKey.companionEnabled)
        applySettings()
    }

    // MARK: - 대화

    /// 캐릭터를 눌렀을 때.
    ///
    /// 진행 중인 것을 클릭 한 번으로 날려버리지 않는다.
    /// 온보딩과 대화는 닫기(✕)·esc·메뉴처럼 분명한 수단으로만 끝낸다.
    private func toggleChat() {
        guard !isOnboarding, !state.isChatting else { return }
        beginChat()
    }

    private func beginChat() {
        guard !state.isChatting, mode != .hidden else { return }
        state.isMenuVisible = false
        bubbleDismissTask?.cancel()
        state.bubble = nil
        state.isChatting = true
        setAnimation(.waiting)
        overlay.setPresentation(expanded: true, acceptsInput: true)

        if state.chatMessages.isEmpty {
            state.chatMessages = [
                CompanionChatMessage(role: .companion, text: line(\.greeting))
            ]
        }
    }

    private func endChat() {
        guard state.isChatting else { return }
        chatReplyTask?.cancel()
        chatReplyTask = nil
        moodResetTask?.cancel()
        moodResetTask = nil
        state.streamingMessageID = nil
        state.isAwaitingReply = false
        state.isChatting = false
        overlay.setPresentation(expanded: false, acceptsInput: false)
        setAnimation(.idle)
    }

    /// 설정에서 고른 공급자. 공급자나 프로필이 바뀌면 세션을 새로 연다.
    private func currentChatProvider() -> CompanionChatProvider {
        if let chatProviderCache { return chatProviderCache }
        let provider = CompanionChatProviderFactory.make(ollamaReachable: isOllamaReachable)
        chatProviderCache = provider
        return provider
    }

    /// 대화 문맥은 세션에 남는다. 창을 닫았다 열어도 앞의 대화를 이어서 기억한다.
    /// 사용자 정보가 바뀌면 시스템 프롬프트가 달라지므로 세션을 새로 연다.
    private func chatSessionForCurrentCharacter() -> CompanionChatSession {
        let profile = CompanionUserProfile.load()
        if let chatSession, profile == appliedUserProfile { return chatSession }

        let session = currentChatProvider().makeSession(
            CompanionChatContext(
                character: state.character,
                profile: profile,
                modelContainer: modelContainer
            )
        )
        chatSession = session
        appliedUserProfile = profile
        return session
    }

    private func send(_ message: String) {
        if let memoIntent = CompanionMemoIntent.parse(message) {
            handleMemoIntent(memoIntent, userMessage: message)
            return
        }

        state.chatMessages.append(CompanionChatMessage(role: .user, text: message))
        state.isAwaitingReply = true
        state.streamingMessageID = nil
        setAnimation(.review)

        let session = chatSessionForCurrentCharacter()
        let isTaskQuestion = CompanionTaskQuestion.matches(message)
        let items = isTaskQuestion ? todayBriefingItems() : []
        let evidence = isTaskQuestion ? [] : appEvidence(for: message)
        let guide = isTaskQuestion ? nil : guideEvidence(for: message)
        // 근거가 있으면 창의성이 필요 없다. 낮은 온도가 지어내는 걸 줄인다.
        let hasEvidence = !evidence.isEmpty || guide != nil
        let modelInput = CompanionChatComposer.modelInput(
            userMessage: message,
            taskDigest: isTaskQuestion
                ? CompanionTaskDigest.format(items: items, now: Date())
                : nil,
            // 조각을 잇는 방식은 지금 그대로다. 어떻게 실을지는 S5d 에서 조립기가 정한다.
            appFacts: evidence.isEmpty ? nil : evidence.map(\.text).joined(separator: "\n"),
            guideSection: guide?.text
        )
        // 일정은 모델의 문장이 아니라 저장된 데이터로 그린다.
        pendingSchedule = isTaskQuestion
            ? CompanionScheduleBuilder.entries(from: items, now: Date())
            : []

        chatReplyTask?.cancel()
        chatReplyTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let reply = await session.reply(to: modelInput, precise: hasEvidence) { [weak self] partial in
                self?.applyStreamedReply(partial.text)
            }
            guard !Task.isCancelled, self.state.isChatting else { return }
            self.applyStreamedReply(reply.text)
            self.attachPendingSchedule()
            self.state.isAwaitingReply = false
            self.state.streamingMessageID = nil
            self.reactWithMood(reply.mood)
            self.showAnswerDestinationIfAny(for: message)
        }
    }

    /// 저장 지시는 모델에 보내지 않고 사용자 입력 또는 직전 말풍선의 원문을 바로 저장한다.
    private func handleMemoIntent(_ intent: CompanionMemoIntent, userMessage: String) {
        let previousMessage = state.chatMessages.last {
            $0.allowsMemoSave
                && !$0.text.isEmpty
                && $0.id != state.streamingMessageID
        }
        let commandMessage = CompanionChatMessage(
            role: .user,
            text: userMessage,
            allowsMemoSave: false
        )
        state.chatMessages.append(commandMessage)

        switch intent.target {
        case .previousMessage:
            guard let previousMessage else {
                appendMemoStatusMessage("아직 메모로 저장할 대화가 없어요.")
                return
            }
            persistMemo(
                messageID: previousMessage.id,
                content: previousMessage.text,
                icon: MemoIcon.defaultIcon,
                isTodayTask: false
            )
        case .text(let content):
            // "내일 … 14시 30분으로" 같은 말은 본문에서 떼어내 시작·마감으로 옮긴다.
            let schedule = CompanionMemoSchedule.parse(content)
            persistMemo(
                messageID: commandMessage.id,
                content: schedule.title,
                icon: MemoIcon.defaultIcon,
                isTodayTask: false,
                schedule: schedule
            )
        }
    }

    private func saveChatMessageAsMemo(
        messageID: UUID,
        icon: String,
        isTodayTask: Bool
    ) {
        guard let message = state.chatMessages.first(where: { $0.id == messageID }),
              message.allowsMemoSave,
              !message.text.isEmpty,
              message.id != state.streamingMessageID else {
            return
        }
        persistMemo(
            messageID: message.id,
            content: message.text,
            icon: icon,
            isTodayTask: isTodayTask
        )
    }

    private func persistMemo(
        messageID: UUID,
        content: String,
        icon: String,
        isTodayTask: Bool,
        schedule: CompanionMemoSchedule? = nil
    ) {
        guard let modelContext = modelContainer?.mainContext else {
            appendMemoStatusMessage("메모를 저장하지 못했어요. 잠시 후 다시 시도해 주세요.")
            return
        }

        do {
            let result = try memoStore.save(
                CompanionMemoSaveRequest(
                    messageID: messageID,
                    content: content,
                    icon: icon,
                    isTodayTask: isTodayTask,
                    startDate: schedule?.startDate,
                    deadline: schedule?.deadline
                ),
                in: modelContext
            )

            let memoID: UUID
            let message: String
            switch result {
            case .saved(let savedMemoID):
                memoID = savedMemoID
                if let summary = schedule?.summary() {
                    message = "\(summary) 일정으로 메모에 저장했어요."
                } else {
                    message = isTodayTask ? "오늘 할 일로 저장했어요." : "메모에 저장했어요."
                }
            case .duplicate(let savedMemoID):
                memoID = savedMemoID
                message = "이 말은 이미 메모에 저장되어 있어요."
            }

            if let index = state.chatMessages.firstIndex(where: { $0.id == messageID }) {
                state.chatMessages[index].savedMemoID = memoID
            }
            appendMemoStatusMessage(message, memoID: memoID)
        } catch {
            appendMemoStatusMessage("메모를 저장하지 못했어요. 잠시 후 다시 시도해 주세요.")
        }
    }

    private func appendMemoStatusMessage(_ message: String, memoID: UUID? = nil) {
        state.chatMessages.append(
            CompanionChatMessage(
                role: .companion,
                text: message,
                memoDestinationID: memoID,
                allowsMemoSave: false
            )
        )
        setAnimation(.waiting)
    }

    /// 코드에서 만든 사실 + 설정 색인을 근거 조각으로 모은다.
    /// 설정 페이지 목록을 함께 넣어 없는 페이지 이름을 지어내지 못하게 한다.
    ///
    /// 조각으로 돌려주는 이유는 합쳐 놓으면 **어느 근거가 걸렸는지 되짚을 수 없기** 때문이다.
    /// 프롬프트에 실을 때는 `send()` 가 지금까지와 똑같이 줄바꿈으로 잇는다.
    private func appEvidence(for message: String) -> [Evidence] {
        var parts = CompanionAppFacts.evidence(for: message)
        if CompanionGuideQuestion.matches(message),
           let match = CompanionSettingsIndex.bestMatch(for: message) {
            parts.append(match.evidenceItem)
        }
        return parts
    }

    /// 답한 내용을 화면으로도 보여준다. 설정 경로를 말했으면 그 자리를 열어 잠깐 강조한다.
    private func showAnswerDestinationIfAny(for message: String) {
        guard CompanionGuideQuestion.matches(message) else { return }
        if let destination = CompanionAppFacts.destination(for: message) {
            CompanionOnboardingPresenter.openSettings(
                tab: destination.tab,
                highlight: destination.highlight
            )
            return
        }
        // 손으로 지정한 목적지가 없어도 색인이 페이지를 찾아주고,
        // 그 페이지에서 제목이 가장 잘 맞는 카드가 스스로 강조된다.
        if let match = CompanionSettingsIndex.bestMatch(for: message) {
            CompanionOnboardingPresenter.openSettings(
                tab: match.tab,
                highlight: nil,
                questionTokens: SearchTokens.from(message)
            )
        }
    }

    /// 사용법 질문이면 설명서에서 근거가 될 섹션 하나를 찾아 준다.
    private func guideEvidence(for message: String) -> Evidence? {
        guard CompanionGuideQuestion.matches(message) else { return nil }
        if guideSections.isEmpty {
            guideSections = CompanionGuide.loadFromBundle()
        }
        return GuideRetriever.evidence(for: message, in: guideSections)
    }

    /// 답변에 붙일 일정. 스트리밍이 끝난 뒤 마지막 말풍선에 실린다.
    private var pendingSchedule: [CompanionScheduleEntry] = []
    private var guideSections: [GuideSection] = []

    private func attachPendingSchedule() {
        defer { pendingSchedule = [] }
        guard !pendingSchedule.isEmpty else { return }

        if let id = state.streamingMessageID,
           let index = state.chatMessages.firstIndex(where: { $0.id == id }) {
            state.chatMessages[index].schedule = pendingSchedule
        } else {
            state.chatMessages.append(
                CompanionChatMessage(role: .companion, text: "", schedule: pendingSchedule)
            )
        }
    }

    /// 답의 감정에 맞는 동작을 잠깐 보여준 뒤 다시 듣는 자세로 돌아온다.
    private func reactWithMood(_ mood: CompanionMood?) {
        moodResetTask?.cancel()
        guard let mood else {
            setAnimation(.waiting)
            return
        }
        setAnimation(mood.animation)

        moodResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.moodReactionSeconds))
            guard let self, !Task.isCancelled, self.state.isChatting else { return }
            self.setAnimation(.waiting)
        }
    }

    /// 스트리밍으로 들어오는 누적 텍스트를 말풍선 하나에 계속 덮어쓴다.
    private func applyStreamedReply(_ text: String) {
        let text = CompanionReplyFormatter.clean(text)
        guard !text.isEmpty else { return }
        state.isAwaitingReply = false

        if let id = state.streamingMessageID,
           let index = state.chatMessages.firstIndex(where: { $0.id == id }) {
            state.chatMessages[index].text = text
            return
        }

        let message = CompanionChatMessage(role: .companion, text: text)
        state.streamingMessageID = message.id
        state.chatMessages.append(message)
    }

    // MARK: - 일정 브리핑

    private func deliverBriefingIfDue() {
        // 숨어 있거나 대화 중이면 건너뛴다. 다시 나타날 때 같은 조건으로 재시도된다.
        guard mode == .roaming, !state.isChatting else { return }
        guard Self.isBriefingEnabled else { return }
        guard CompanionBriefingSchedule.shouldDeliver(
            now: Date(),
            hour: Self.briefingHour,
            minute: Self.briefingMinute,
            lastDeliveredAt: Self.lastBriefingDeliveredAt
        ) else { return }

        UserDefaults.standard.set(
            Date().timeIntervalSince1970,
            forKey: Constants.AppStorageKey.companionBriefingLastDeliveredAt
        )
        presentSchedule()
    }

    /// 캐릭터 오른쪽 클릭. 한 번 더 누르면 닫힌다.
    private func toggleMenu() {
        guard mode != .hidden else { return }
        if state.isMenuVisible {
            hideMenu()
            return
        }
        bubbleDismissTask?.cancel()
        bubbleDismissTask = nil
        // 마지막 온보딩 단계에서는 사용자가 우클릭 메뉴를 직접 열어본다.
        // 메뉴를 닫았을 때 설명으로 돌아올 수 있도록 그동안 말풍선을 보존한다.
        if !isOnboarding {
            state.bubble = nil
        }
        state.isMenuVisible = true
        // 메뉴가 캐릭터 위에 온전히 들어가도록 창을 넓힌다.
        overlay.setPresentation(expanded: true, acceptsInput: false)
    }

    private func hideMenu() {
        guard state.isMenuVisible else { return }
        state.isMenuVisible = false
        // 대화나 말풍선이 이어서 뜨면 그쪽에서 다시 크기를 정한다.
        if !state.isChatting, state.bubble?.schedule.isEmpty ?? true {
            overlay.setPresentation(expanded: false, acceptsInput: false)
        }
    }

    /// 우클릭 메뉴에서 부르는 "오늘 일정 보기".
    /// 하루 한 번 제한과 무관하게 언제든 다시 볼 수 있어야 하므로 전달 이력을 건드리지 않는다.
    private func showScheduleOnDemand() {
        guard mode != .hidden else { return }
        if state.isChatting { endChat() }
        presentSchedule()
    }

    /// 오늘 일정을 타임라인 말풍선으로 띄운다. 사용자가 닫을 때까지 남는다.
    private func presentSchedule() {
        state.isMenuVisible = false
        // 채팅 답변과 같은 타임라인을 쓴다. 완료된 항목도 상태를 유지한 채 보여준다.
        let entries = CompanionScheduleBuilder.entries(from: todayBriefingItems(), now: Date())
        if entries.isEmpty {
            presentTemporaryBubble(
                CompanionBubble(
                    headline: CompanionBriefingSummary.headline(for: entries),
                    message: line(\.briefingEmpty),
                    isDismissible: true
                ),
                animation: .review,
                seconds: nil
            )
        } else {
            presentTemporaryBubble(
                CompanionBubble(
                    headline: CompanionBriefingSummary.headline(for: entries),
                    message: line(\.briefingIntro),
                    schedule: entries,
                    isDismissible: true
                ),
                animation: .review,
                seconds: nil
            )
        }
    }

    /// 보관하지 않은 메모 전체를 브리핑·대화가 함께 쓰는 형태로 바꾼다.
    private func todayBriefingItems() -> [CompanionBriefingItem] {
        guard let modelContainer,
              let memos = try? modelContainer.mainContext.fetch(FetchDescriptor<Memo>()) else {
            return []
        }
        return memos
            .filter { !$0.isArchivedValue }
            .map {
                CompanionBriefingItem(
                    title: $0.content,
                    isCompleted: $0.isCompletedValue,
                    startDate: $0.startDate,
                    deadline: $0.deadline
                )
            }
    }

    // MARK: - 말풍선 유틸

    /// 집중 넛지. 판정 이유와 수치 뒤에 사용자가 등록한 문구를 이어 말한다.
    ///
    /// 집중 중에는 숨어 있으므로, 말할 때만 잠깐 나타났다 다시 사라진다.
    /// 대화나 온보딩이 떠 있으면 건너뛰고 false 를 돌려준다 — 이번 세션의 한 번을 쓴 것으로
    /// 치지 않아야 다음 판정 때 다시 올 수 있다.
    @discardableResult
    private func presentFocusNudge(_ message: String) -> Bool {
        guard Self.isEnabled, !isOnboarding, !state.isChatting, !state.isMenuVisible else {
            return false
        }

        bubbleDismissTask?.cancel()
        focusNudgeMessage = message
        state.bubble = CompanionBubble(message: message, isDismissible: true)
        overlay.setPresentation(expanded: false, acceptsInput: false)
        setAnimation(.waving)
        // 집중 중에 컴패니언을 켠 경우처럼 아직 무대를 잡은 적이 없으면 여기서 잡는다.
        // 그러지 않으면 자리가 정해지지 않은 채로 나타난다.
        if engine == nil {
            appliedRoamingRegion = Self.roamingRegion
            rebuildEngine(force: true)
        }
        moveOverlayToFocusNudgeCenter()
        overlay.show()
        startTicking()

        bubbleDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.focusNudgeSeconds))
            guard let self, !Task.isCancelled, self.focusNudgeMessage == message else { return }
            self.focusNudgeMessage = nil
            self.state.bubble = nil
            // 숨어 있어야 할 상태였다면 말만 하고 다시 사라진다.
            if self.mode == .hidden {
                self.stopTicking()
                self.overlay.hide()
            } else {
                self.setAnimation(.idle)
            }
        }
        return true
    }

    /// 사용자가 직접 닫을 때까지 말풍선을 유지한다.
    private func dismissBubble() {
        if isOnboarding {
            finishOnboarding()
            return
        }
        focusNudgeMessage = nil
        bubbleDismissTask?.cancel()
        bubbleDismissTask = nil
        state.bubble = nil
        overlay.setPresentation(expanded: false, acceptsInput: false)
        setAnimation(.idle)
        // 넛지 때문에 잠깐 나와 있던 것이라면 말풍선을 닫는 순간 다시 숨는다.
        if mode == .hidden {
            stopTicking()
            overlay.hide()
        }
    }

    /// `seconds` 가 nil 이면 저절로 사라지지 않는다(브리핑처럼 사용자가 닫아야 하는 경우).
    private func presentTemporaryBubble(
        _ bubble: CompanionBubble,
        animation: CompanionAnimation,
        seconds: Double?,
        thenRestoreBreakMenu: Bool = false
    ) {
        bubbleDismissTask?.cancel()
        bubbleDismissTask = nil
        state.bubble = bubble
        overlay.setPresentation(expanded: !bubble.schedule.isEmpty, acceptsInput: false)
        setAnimation(animation)

        guard let seconds else { return }

        bubbleDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled else { return }
            // 사이에 온보딩이 시작됐다면 그쪽 말풍선을 건드리지 않는다.
            if self.isOnboarding { return }
            if thenRestoreBreakMenu, self.mode == .breakTime {
                self.presentBreakMenu()
            } else if self.mode != .hidden {
                self.state.bubble = nil
                self.overlay.setPresentation(expanded: false, acceptsInput: false)
                self.setAnimation(.idle)
            }
        }
    }

    /// 상황에 맞는 대사 하나. 부를 이름을 정해뒀으면 앞에 붙인다.
    private func line(_ keyPath: KeyPath<CompanionLineCatalog, [String]>) -> String {
        let text = state.character.lines.pick(keyPath, using: &generator)
        let nickname = CompanionUserProfile.load().nickname
        guard !nickname.isEmpty else { return text }
        return "\(nickname), \(text)"
    }

    // MARK: - 설정 값

    private static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Constants.AppStorageKey.companionEnabled) as? Bool
            ?? Constants.defaultCompanionEnabled
    }

    private static var selectedIdentifier: String {
        UserDefaults.standard.string(forKey: Constants.AppStorageKey.companionSelectedIdentifier)
            ?? Constants.defaultCompanionIdentifier
    }

    private static var hidesDuringFocus: Bool {
        UserDefaults.standard.object(forKey: Constants.AppStorageKey.companionHideDuringFocus) as? Bool
            ?? Constants.defaultCompanionHideDuringFocus
    }

    /// 지정한 활동 영역. 없으면 nil(= 화면 전체).
    private static var roamingRegion: CGRect? {
        guard let stored = UserDefaults.standard.string(
            forKey: Constants.AppStorageKey.companionRoamingRegion
        ) else { return nil }
        return CompanionRoamingRegion.rect(fromStorageValue: stored)
    }

    private static var isBriefingEnabled: Bool {
        UserDefaults.standard.object(forKey: Constants.AppStorageKey.companionBriefingEnabled) as? Bool
            ?? Constants.defaultCompanionBriefingEnabled
    }

    private static var briefingHour: Int {
        guard UserDefaults.standard.object(forKey: Constants.AppStorageKey.companionBriefingHour) != nil else {
            return Constants.defaultCompanionBriefingHour
        }
        return CompanionBriefingSchedule.normalizedHour(
            UserDefaults.standard.integer(forKey: Constants.AppStorageKey.companionBriefingHour)
        )
    }

    private static var briefingMinute: Int {
        guard UserDefaults.standard.object(forKey: Constants.AppStorageKey.companionBriefingMinute) != nil else {
            return Constants.defaultCompanionBriefingMinute
        }
        return CompanionBriefingSchedule.normalizedMinute(
            UserDefaults.standard.integer(forKey: Constants.AppStorageKey.companionBriefingMinute)
        )
    }

    private static var lastBriefingDeliveredAt: Date? {
        let key = Constants.AppStorageKey.companionBriefingLastDeliveredAt
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        return Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: key))
    }
}
