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

    private var modelContext: ModelContext?
    private var tickTimer: Timer?
    private var defaultsObserver: NSObjectProtocol?
    private var timerStateObservationTask: Task<Void, Never>?
    private var bubbleDismissTask: Task<Void, Never>?

    private lazy var chatProvider: CompanionChatProvider = CompanionChatProviderFactory.make()
    private var chatSession: CompanionChatSession?
    private var chatReplyTask: Task<Void, Never>?
    private var streamingMessageID: UUID?

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
        state.onDragBegan = { [weak self] in self?.beginDrag() }
        state.onDragChanged = { [weak self] in self?.updateDrag() }
        state.onDragEnded = { [weak self] in self?.endDrag() }
        state.onTurnOff = { [weak self] in self?.turnOff() }
    }

    func start(modelContext: ModelContext) {
        self.modelContext = modelContext

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applySettings()
            }
        }

        observeTimerState()
        applySettings()
    }

    func stop() {
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
        stopTicking()
        overlay.hide()
        mode = .hidden
    }

    // MARK: - 설정 반영

    private func applySettings() {
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

        // 대화 중이거나 말풍선이 떠 있는 동안에는 제자리에서 상황에 맞는 동작만 한다.
        if mode == .roaming, !state.isChatting, state.bubble == nil, engine != nil {
            engine?.advance(by: delta, using: &generator)
            moveOverlay()
            setAnimation(engine?.animation ?? .idle)
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
        bubbleDismissTask?.cancel()
        state.bubble = nil
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
        setAnimation(.idle)
    }

    private func turnOff() {
        endChat()
        UserDefaults.standard.set(false, forKey: Constants.AppStorageKey.companionEnabled)
        applySettings()
    }

    // MARK: - 대화

    private func toggleChat() {
        if state.isChatting {
            endChat()
        } else {
            beginChat()
        }
    }

    private func beginChat() {
        guard !state.isChatting, mode != .hidden else { return }
        bubbleDismissTask?.cancel()
        state.bubble = nil
        state.isChatting = true
        setAnimation(.waiting)
        overlay.setChatting(true)

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
        streamingMessageID = nil
        state.isAwaitingReply = false
        state.isChatting = false
        overlay.setChatting(false)
        setAnimation(.idle)
    }

    /// 대화 문맥은 세션에 남는다. 창을 닫았다 열어도 앞의 대화를 이어서 기억한다.
    private func chatSessionForCurrentCharacter() -> CompanionChatSession {
        if let chatSession { return chatSession }
        let session = chatProvider.makeSession(for: state.character)
        chatSession = session
        return session
    }

    private func send(_ message: String) {
        state.chatMessages.append(CompanionChatMessage(role: .user, text: message))
        state.isAwaitingReply = true
        streamingMessageID = nil
        setAnimation(.review)

        let session = chatSessionForCurrentCharacter()
        chatReplyTask?.cancel()
        chatReplyTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let reply = await session.reply(to: message) { [weak self] partial in
                self?.applyStreamedReply(partial)
            }
            guard !Task.isCancelled, self.state.isChatting else { return }
            self.applyStreamedReply(reply)
            self.state.isAwaitingReply = false
            self.streamingMessageID = nil
            self.setAnimation(.waiting)
        }
    }

    /// 스트리밍으로 들어오는 누적 텍스트를 말풍선 하나에 계속 덮어쓴다.
    private func applyStreamedReply(_ text: String) {
        guard !text.isEmpty else { return }
        state.isAwaitingReply = false

        if let id = streamingMessageID,
           let index = state.chatMessages.firstIndex(where: { $0.id == id }) {
            state.chatMessages[index].text = text
            return
        }

        let message = CompanionChatMessage(role: .companion, text: text)
        streamingMessageID = message.id
        state.chatMessages.append(message)
    }

    // MARK: - 일정 브리핑

    private func deliverBriefingIfDue() {
        guard Self.isBriefingEnabled else { return }
        guard CompanionBriefingSchedule.shouldDeliver(
            now: Date(),
            hour: Self.briefingHour,
            minute: Self.briefingMinute,
            lastDeliveredAt: Self.lastBriefingDeliveredAt
        ) else { return }

        let briefing = composeBriefing()
        UserDefaults.standard.set(
            Date().timeIntervalSince1970,
            forKey: Constants.AppStorageKey.companionBriefingLastDeliveredAt
        )

        if briefing.isEmpty {
            presentTemporaryBubble(
                CompanionBubble(headline: briefing.headline, message: line(\.briefingEmpty)),
                animation: .review,
                seconds: 8
            )
        } else {
            presentTemporaryBubble(
                CompanionBubble(
                    headline: briefing.headline,
                    message: line(\.briefingIntro),
                    detailLines: briefing.lines
                ),
                animation: .review,
                seconds: 12
            )
        }
    }

    private func composeBriefing() -> CompanionBriefing {
        guard let modelContext,
              let memos = try? modelContext.fetch(FetchDescriptor<Memo>()) else {
            return CompanionBriefing(headline: "오늘 일정 없음", lines: [])
        }
        let items = memos
            .filter { !$0.isArchivedValue }
            .map {
                CompanionBriefingItem(
                    title: $0.content,
                    isCompleted: $0.isCompletedValue,
                    startDate: $0.startDate,
                    deadline: $0.deadline
                )
            }
        return CompanionBriefingComposer.compose(items: items, now: Date())
    }

    // MARK: - 말풍선 유틸

    private func presentTemporaryBubble(
        _ bubble: CompanionBubble,
        animation: CompanionAnimation,
        seconds: Double,
        thenRestoreBreakMenu: Bool = false
    ) {
        bubbleDismissTask?.cancel()
        state.bubble = bubble
        setAnimation(animation)

        bubbleDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled else { return }
            if thenRestoreBreakMenu, self.mode == .breakTime {
                self.presentBreakMenu()
            } else if self.mode != .hidden {
                self.state.bubble = nil
                self.setAnimation(.idle)
            }
        }
    }

    private func line(_ keyPath: KeyPath<CompanionLineCatalog, [String]>) -> String {
        state.character.lines.pick(keyPath, using: &generator)
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
