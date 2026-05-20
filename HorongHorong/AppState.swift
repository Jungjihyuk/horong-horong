import SwiftUI

enum TimerState: String {
    case idle
    case focusing
    case paused
    case breakAlert
    case breaking
}

@Observable
final class AppState {
    var timerState: TimerState = .idle
    var remainingSeconds: Int = 0
    var focusMinutes: Int = Constants.defaultPomodoroFocusMinutes
    var breakMinutes: Int = Constants.defaultPomodoroBreakMinutes

    var menuBarTitle: String {
        switch timerState {
        case .focusing, .paused, .breaking:
            return formattedRemaining(style: .mmss)
        default:
            return ""
        }
    }

    /// 메뉴바에 표시할 남은 시간 텍스트. 분:초 또는 분 단위.
    func formattedRemaining(style: Constants.MenubarTimeStyle) -> String {
        switch style {
        case .mmss:
            let m = remainingSeconds / 60
            let s = remainingSeconds % 60
            return String(format: "%02d:%02d", m, s)
        case .minutes:
            let m = max(0, Int((Double(remainingSeconds) / 60.0).rounded(.up)))
            return "\(m)분"
        }
    }

    var menuBarIcon: String {
        switch timerState {
        case .focusing, .paused: return "flame.fill"
        case .breaking: return "cup.and.saucer.fill"
        default: return "pawprint.fill"
        }
    }

    var currentTrackingApp: String = ""
    var isQuickMemoVisible: Bool = false
}
