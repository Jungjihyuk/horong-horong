import SwiftUI

struct TimerSettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage(Constants.AppStorageKey.pomodoroFocusMinutes)
    private var pomodoroFocusMinutes: Int = Constants.defaultPomodoroFocusMinutes
    @AppStorage(Constants.AppStorageKey.pomodoroBreakMinutes)
    private var pomodoroBreakMinutes: Int = Constants.defaultPomodoroBreakMinutes
    @AppStorage(Constants.AppStorageKey.longFocusFocusMinutes)
    private var longFocusFocusMinutes: Int = Constants.defaultLongFocusFocusMinutes
    @AppStorage(Constants.AppStorageKey.longFocusBreakMinutes)
    private var longFocusBreakMinutes: Int = Constants.defaultLongFocusBreakMinutes

    var body: some View {
        @Bindable var state = appState

        Form {
            Section("포모도로 시간 설정") {
                Stepper("집중 시간: \(appState.focusMinutes)분", value: $state.focusMinutes, in: 1...120)
                Stepper("휴식 시간: \(appState.breakMinutes)분", value: $state.breakMinutes, in: 1...30)
            }

            Section("프리셋") {
                Button("포모도로 (\(pomodoroFocusMinutes)/\(pomodoroBreakMinutes))") {
                    appState.focusMinutes = pomodoroFocusMinutes
                    appState.breakMinutes = pomodoroBreakMinutes
                }
                Button("긴 집중 (\(longFocusFocusMinutes)/\(longFocusBreakMinutes))") {
                    appState.focusMinutes = longFocusFocusMinutes
                    appState.breakMinutes = longFocusBreakMinutes
                }
            }

            Section("프리셋 시간 편집") {
                Stepper("포모도로 집중: \(pomodoroFocusMinutes)분",
                        value: $pomodoroFocusMinutes, in: 1...120)
                Stepper("포모도로 휴식: \(pomodoroBreakMinutes)분",
                        value: $pomodoroBreakMinutes, in: 1...30)
                Stepper("긴 집중 집중: \(longFocusFocusMinutes)분",
                        value: $longFocusFocusMinutes, in: 1...240)
                Stepper("긴 집중 휴식: \(longFocusBreakMinutes)분",
                        value: $longFocusBreakMinutes, in: 1...60)
            }
        }
        .formStyle(.grouped)
    }
}
