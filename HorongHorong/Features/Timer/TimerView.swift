import SwiftUI

struct TimerView: View {
    @Environment(AppState.self) private var appState
    @AppStorage(Constants.AppStorageKey.selectedFocusCategory)
    private var selectedFocusCategory: String = Constants.defaultFocusCategory
    @AppStorage(Constants.AppStorageKey.pomodoroFocusMinutes)
    private var pomodoroFocusMinutes: Int = Constants.defaultPomodoroFocusMinutes
    @AppStorage(Constants.AppStorageKey.pomodoroBreakMinutes)
    private var pomodoroBreakMinutes: Int = Constants.defaultPomodoroBreakMinutes
    @AppStorage(Constants.AppStorageKey.longFocusFocusMinutes)
    private var longFocusFocusMinutes: Int = Constants.defaultLongFocusFocusMinutes
    @AppStorage(Constants.AppStorageKey.longFocusBreakMinutes)
    private var longFocusBreakMinutes: Int = Constants.defaultLongFocusBreakMinutes
    var timerManager: TimerManager

    var body: some View {
        VStack(spacing: 16) {
            timerDisplay
            controlButtons
            presetSelector
        }
    }

    private var timerDisplay: some View {
        VStack(spacing: 4) {
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(timeString)
                .font(.system(size: 48, weight: .light, design: .monospaced))
                .contentTransition(.numericText())
                .animation(.default, value: appState.remainingSeconds)

            if appState.timerState == .focusing || appState.timerState == .breaking {
                ProgressView(value: progress)
                    .tint(appState.timerState == .focusing ? .orange : .green)
                    .animation(.linear, value: progress)
            }
        }
    }

    private var controlButtons: some View {
        HStack(spacing: 16) {
            switch appState.timerState {
            case .idle:
                Button {
                    timerManager.startFocus(category: selectedFocusCategory)
                } label: {
                    Label("집중 시작", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

            case .focusing:
                Button {
                    timerManager.pause()
                } label: {
                    Label("일시정지", systemImage: "pause.fill")
                }
                .buttonStyle(.bordered)

                Button {
                    timerManager.reset()
                } label: {
                    Label("리셋", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .tint(.red)

            case .paused:
                Button {
                    timerManager.resume()
                } label: {
                    Label("재개", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                Button {
                    timerManager.reset()
                } label: {
                    Label("리셋", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .tint(.red)

            case .breakAlert:
                Button {
                    timerManager.startBreak()
                } label: {
                    Label("휴식 시작", systemImage: "cup.and.saucer.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button {
                    timerManager.reset()
                } label: {
                    Label("건너뛰기", systemImage: "forward.fill")
                }
                .buttonStyle(.bordered)

            case .breaking:
                Button {
                    timerManager.reset()
                } label: {
                    Label("휴식 종료", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var presetSelector: some View {
        Group {
            if appState.timerState == .idle {
                VStack(spacing: 8) {
                    Picker("프리셋", selection: Binding(
                        get: { currentPreset },
                        set: { applyPreset($0) }
                    )) {
                        ForEach(Constants.PomodoroPreset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 8) {
                        Text("카테고리")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("카테고리", selection: $selectedFocusCategory) {
                            ForEach(Constants.allCategories, id: \.self) { cat in
                                Text("\(Constants.categoryEmoji(for: cat)) \(cat)")
                                    .tag(cat)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    if currentPreset == .custom {
                        HStack {
                            Stepper("집중 \(appState.focusMinutes)분", value: Binding(
                                get: { appState.focusMinutes },
                                set: { appState.focusMinutes = $0 }
                            ), in: 1...120)

                            Stepper("휴식 \(appState.breakMinutes)분", value: Binding(
                                get: { appState.breakMinutes },
                                set: { appState.breakMinutes = $0 }
                            ), in: 1...30)
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }

    private var currentPreset: Constants.PomodoroPreset {
        if appState.focusMinutes == pomodoroFocusMinutes && appState.breakMinutes == pomodoroBreakMinutes {
            return .pomodoro
        } else if appState.focusMinutes == longFocusFocusMinutes && appState.breakMinutes == longFocusBreakMinutes {
            return .longFocus
        } else {
            return .custom
        }
    }

    private func applyPreset(_ preset: Constants.PomodoroPreset) {
        switch preset {
        case .pomodoro:
            appState.focusMinutes = pomodoroFocusMinutes
            appState.breakMinutes = pomodoroBreakMinutes
        case .longFocus:
            appState.focusMinutes = longFocusFocusMinutes
            appState.breakMinutes = longFocusBreakMinutes
        case .custom:
            appState.focusMinutes = Constants.defaultCustomFocusMinutes
            appState.breakMinutes = Constants.defaultCustomBreakMinutes
        }
    }

    private var statusText: String {
        switch appState.timerState {
        case .idle: return "준비"
        case .focusing: return "🔥 집중 중"
        case .paused: return "⏸ 일시정지"
        case .breakAlert: return "🎉 집중 완료!"
        case .breaking: return "☕ 휴식 중"
        }
    }

    private var timeString: String {
        let minutes = appState.remainingSeconds / 60
        let seconds = appState.remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var progress: Double {
        let total: Int
        switch appState.timerState {
        case .focusing, .paused:
            total = appState.focusMinutes * 60
        case .breaking:
            total = appState.breakMinutes * 60
        default:
            return 0
        }
        guard total > 0 else { return 0 }
        return Double(total - appState.remainingSeconds) / Double(total)
    }
}
