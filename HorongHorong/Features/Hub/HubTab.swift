import SwiftUI
import AppKit

/// 통합 윈도우가 담는 네 가지 화면.
enum HubTab: String, CaseIterable, Identifiable, Hashable {
    case memo
    case news
    case stats
    case achievement

    var id: String { rawValue }

    var label: String {
        switch self {
        case .memo:        return "전체 메모"
        case .news:        return "뉴스 보관함"
        case .stats:       return "통계"
        case .achievement: return "성취"
        }
    }

    var systemIcon: String {
        switch self {
        case .memo:        return "note.text"
        case .news:        return "newspaper"
        case .stats:       return "chart.bar"
        case .achievement: return "target"
        }
    }
}

@MainActor
enum HubWindowPresenter {
    static let windowID = "main-hub"
    static let windowTitle = "호롱호롱"

    /// 이미 떠 있는 통합 윈도우. openWindow 로 만들어진 창을 id 또는 제목으로 찾는다.
    static func existingWindow() -> NSWindow? {
        NSApp.windows.first {
            $0.identifier?.rawValue == windowID || $0.title == windowTitle
        }
    }

    /// 팝오버를 닫고 통합 윈도우를 지정 탭으로 띄워 최상단에 올린다.
    ///
    /// MenuBarExtra 앱은 accessory 정책이라 openWindow 만으로는 창이 앞으로 오지 않는다.
    /// 창이 생성/재사용된 뒤 활성화 + orderFrontRegardless 로 최상단까지 끌어올린다.
    static func present(
        tab: HubTab,
        appState: AppState,
        popoverWindow: NSWindow?,
        openWindow: OpenWindowAction
    ) {
        appState.hubTab = tab
        openWindow(id: windowID)
        popoverWindow?.orderOut(nil)

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if let window = existingWindow() {
                window.collectionBehavior.insert(.moveToActiveSpace)
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }
}
