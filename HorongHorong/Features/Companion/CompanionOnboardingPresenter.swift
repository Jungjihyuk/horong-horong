import AppKit
import SwiftUI

extension Notification.Name {
    /// 설정 창에서 온보딩을 직접 시작한다.
    static let companionStartOnboarding = Notification.Name(
        "companion.onboarding.start"
    )

    /// 온보딩이 특정 팝오버 탭을 보여달라고 요청한다.
    static let companionOnboardingSelectTab = Notification.Name(
        "companion.onboarding.selectTab"
    )
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

    static func show(_ screen: CompanionOnboardingScreen) {
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
            // 사용자가 팝오버의 "상세 보기" 를 직접 누르도록 둔다.
            break
        case .settingsCompanion:
            closePopover()
            openSettings()
        }
    }

    /// 온보딩이 끝나면 열어둔 팝오버를 닫아 원래 상태로 돌려놓는다.
    static func closePopover() {
        guard isPopoverOpen, let button = statusItemButton() else {
            isPopoverOpen = false
            return
        }
        button.performClick(nil)
        isPopoverOpen = false
    }

    private static func openPopover(tab: PopoverTab) {
        if !isPopoverOpen, let button = statusItemButton() {
            button.performClick(nil)
            isPopoverOpen = true
        }
        guard isPopoverOpen else { return }
        // 팝오버가 그려진 뒤에 탭을 바꾼다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(name: .companionOnboardingSelectTab, object: tab)
        }
    }

    /// `MenuBarExtra` 가 만든 상태바 버튼을 찾는다.
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

    private static func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
