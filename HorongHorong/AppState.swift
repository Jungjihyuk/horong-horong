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
        case .focusing, .paused:
            let m = remainingSeconds / 60
            let s = remainingSeconds % 60
            return String(format: "%02d:%02d", m, s)
        case .breaking:
            let m = remainingSeconds / 60
            let s = remainingSeconds % 60
            return String(format: "%02d:%02d", m, s)
        default:
            return ""
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
