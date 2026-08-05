import AppKit
import SwiftUI

extension Notification.Name {
    /// 설정 창에서 온보딩을 직접 시작한다.
    static let companionStartOnboarding = Notification.Name(
        "companion.onboarding.start"
    )

    /// 온보딩이 화면 안에서 무언가를 눌러 보여달라고 요청한다(object: 동작 이름).
    static let companionOnboardingPerform = Notification.Name(
        "companion.onboarding.perform"
    )

    /// 온보딩이 특정 팝오버 탭을 보여달라고 요청한다.
    static let companionOnboardingSelectTab = Notification.Name(
        "companion.onboarding.selectTab"
    )
}

/// `MenuBarExtra`가 만든 상태바 버튼을 찾아 실제 클릭과 같은 동작을 수행한다.
@MainActor
enum MenuBarExtraController {
    @discardableResult
    static func toggle() -> Bool {
        guard let button = statusItemButton() else { return false }
        button.performClick(nil)
        return true
    }

    private static func statusItemButton() -> NSStatusBarButton? {
        for window in NSApp.windows where window.className.contains("StatusBar") {
            if let button = findButton(in: window.contentView) {
                return button
            }
        }
        return nil
    }

    private static func findButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let button = findButton(in: subview) { return button }
        }
        return nil
    }
}

/// 온보딩 단계에 맞춰 실제 앱 화면을 띄운다.
///
/// 메뉴바 팝오버는 `MenuBarExtra` 가 관리해 직접 참조할 수 없어, 상태바 버튼을 찾아 눌러 연다.
/// macOS 내부 구조에 기대는 방식이라 버튼을 못 찾으면 화면 전환만 조용히 건너뛴다(온보딩은 계속된다).
///
/// 통계 상세 창처럼 사용자가 직접 눌러야 하는 화면은 열어주지 않는다.
/// 호로롱이 어디를 누르라고 알려주고 사용자가 눌러보는 편이 튜토리얼에 맞다.
@MainActor
enum CompanionOnboardingPresenter {
    private static var isPopoverOpen = false
    /// 온보딩이 직접 연 통계 상세 창만 닫는다. 사용자가 미리 열어둔 창은 건드리지 않는다.
    private static var didOpenStatsWindow = false
    /// 딤 위로 끌어올린 창과 원래 레벨. 온보딩이 끝나면 되돌린다.
    private static var raisedWindows: [(window: NSWindow, level: NSWindow.Level)] = []

    /// 설명 중인 창은 어두워지면 안 된다. 딤(`.floating - 2`) 위로 올린다.
    /// 다만 캐릭터(`.floating`) 보다는 아래에 둬야 말풍선이 가려지지 않는다.
    private static func raiseAboveDim(_ window: NSWindow) {
        guard !raisedWindows.contains(where: { $0.window === window }) else { return }
        raisedWindows.append((window, window.level))
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
    }

    private static func restoreRaisedWindows() {
        for entry in raisedWindows {
            entry.window.level = entry.level
        }
        raisedWindows.removeAll()
    }

    static func show(_ screen: CompanionOnboardingScreen) {
        // 통계 이야기를 벗어나면 열어줬던 상세 창을 정리한다.
        if screen != .windowStats {
            closeStatsDetailWindow()
        }

        switch screen {
        case .popoverTimer:
            openPopover(tab: .timer)
        case .popoverMemo:
            openPopover(tab: .memo)
        case .popoverStats:
            openPopover(tab: .stats)
        case .popoverAchievement:
            openPopover(tab: .achievement)
        case .windowStats:
            openStatsDetailWindow()
        case .settingsCompanion:
            openSettings(tab: .companion)
        case .settingsMemo:
            openSettings(tab: .memo)
        }
    }

    /// 온보딩이 열었던 창을 모두 정리한다.
    static func closeAll() {
        restoreRaisedWindows()
        closeStatsDetailWindow()
        closePopover()
    }

    static func closeStatsDetailWindow() {
        guard didOpenStatsWindow else { return }
        didOpenStatsWindow = false
        NSApp.windows.first {
            $0.identifier?.rawValue == "stats-detail" || $0.title == "호롱호롱 통계"
        }?.close()
    }

    /// 대화에서 저장한 메모를 곧바로 확인할 수 있게 팝오버의 메모 탭을 연다.
    static func showMemoTab() {
        openPopover(tab: .memo)
    }

    /// 온보딩이 끝나면 열어둔 팝오버를 닫아 원래 상태로 돌려놓는다.
    static func closePopover() {
        guard isPopoverOpen, MenuBarExtraController.toggle() else {
            isPopoverOpen = false
            return
        }
        isPopoverOpen = false
    }

    private static func openPopover(tab: PopoverTab) {
        if !isPopoverOpen, MenuBarExtraController.toggle() {
            isPopoverOpen = true
        }
        guard isPopoverOpen else { return }
        // 팝오버가 그려진 뒤에 탭을 바꾼다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(name: .companionOnboardingSelectTab, object: tab)
        }
    }

    /// 온보딩이 대신 눌러주는 동작. 각 화면이 알림을 받아 자기 상태를 바꾼다.
    static func perform(_ action: String) {
        NotificationCenter.default.post(name: .companionOnboardingPerform, object: action)
    }

    /// 통계 상세 창을 띄운다. "상세 보기" 버튼이 하는 일과 같은 방식이다.
    private static func openStatsDetailWindow() {
        closePopover()
        didOpenStatsWindow = true
        NSApp.activate(ignoringOtherApps: true)
        perform("stats.openDetail")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let window = NSApp.windows.first(where: {
                $0.identifier?.rawValue == "stats-detail" || $0.title == "호롱호롱 통계"
            }) {
                window.collectionBehavior.insert(.moveToActiveSpace)
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                raiseAboveDim(window)
            }
        }
    }

    /// 설정 창을 열고 원하는 페이지로 이동한다. 대화 답변에서도 쓴다.
    /// `questionTokens` 를 주면 그 페이지에서 제목이 가장 잘 맞는 카드가 스스로 강조된다.
    static func openSettings(
        tab: SettingsTab,
        highlight: String?,
        questionTokens: [String] = [],
        seconds: Double = 4
    ) {
        if !questionTokens.isEmpty {
            CompanionHighlightCenter.shared.beginCardSearch(tokens: questionTokens)
        }
        perform("settings.open")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            perform("settings.show:\(tab.rawValue)")
            closePopover()
            if let window = settingsWindow() {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
            if let highlight {
                CompanionHighlightCenter.shared.highlight(highlight)
            }
            // 잠깐 비추고 원래대로 돌린다. 대화 중엔 계속 강조할 이유가 없다.
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                CompanionHighlightCenter.shared.endCardSearch()
                CompanionHighlightCenter.shared.highlight(nil)
            }
        }
    }

    /// 항상 살아 있는 메뉴바 라벨에 설정 창을 열어 달라고 요청한다.
    private static func openSettings(tab: SettingsTab) {
        // 설정에서 사용법 안내를 시작했다면 이미 열린 창을 그대로 쓴다.
        // 팝오버를 중간 다리로 다시 열면 기본 타이머 탭이 잠깐 번쩍인다.
        if let window = settingsWindow() {
            perform("settings.show:\(tab.rawValue)")
            closePopover()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            raiseAboveDim(window)
            return
        }

        perform("settings.open")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            perform("settings.show:\(tab.rawValue)")
            closePopover()
            // 설정 창도 딤 위로 올려 설명 중인 부분이 보이게 한다.
            if let window = settingsWindow() {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                raiseAboveDim(window)
            }
        }
    }

    private static func settingsWindow() -> NSWindow? {
        NSApp.windows.first {
            ($0.identifier?.rawValue ?? "").contains("com_apple_SwiftUI_Settings")
                || $0.title.localizedCaseInsensitiveContains("설정")
        }
    }
}
