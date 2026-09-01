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
        case .memo:        return "기록"
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
    /// MenuBarExtra 팝오버는 non-activating 패널이라 이 버튼을 누르는 순간 앱은 비활성이다.
    /// openWindow 만으로는 창이 앞으로 오지 않으므로 활성화를 직접 요청한다.
    ///
    /// 활성화 요청은 **사용자 클릭과 같은 런루프**에서 보낸다. 다음 런루프로 미루면
    /// 팝오버가 내려가며 직전 앱으로 돌아가는 활성화에 밀린다. 밀려도 창은 보이기 때문에
    /// 화면상으로는 성공처럼 보이고, 앱이 비활성이라 한글만 입력되지 않는 상태가 된다.
    static func present(
        tab: HubTab,
        appState: AppState,
        popoverWindow: NSWindow?,
        openWindow: OpenWindowAction
    ) {
        #if DEBUG
        PerfLog.start("허브 열기(\(tab))")
        #endif
        appState.hubTab = tab
        if tab == .memo {
            appState.isRecordRailVisible = true
        }
        popoverWindow?.orderOut(nil)
        NSApp.activate()
        openWindow(id: windowID)

        DispatchQueue.main.async {
            let window = existingWindow()
            window?.collectionBehavior.insert(.moveToActiveSpace)
            AppActivation.front(window)
        }
    }
}
