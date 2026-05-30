import SwiftUI

private struct TimerGradientButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.vertical, 12)
            .padding(.horizontal, 22)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 1.00, green: 0.60, blue: 0.24),
                        Color(red: 0.96, green: 0.40, blue: 0.10),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: Capsule()
            )
            .shadow(color: Color(red: 0.92, green: 0.40, blue: 0.08).opacity(configuration.isPressed ? 0.22 : 0.32), radius: 13, x: 0, y: 8)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct TimerView: View {
    @Environment(AppState.self) private var appState
    @State private var hoveredPreset: Constants.PomodoroPreset?
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
    @AppStorage(Constants.AppStorageKey.customFocusMinutes)
    private var customFocusMinutes: Int = Constants.defaultCustomFocusMinutes
    @AppStorage(Constants.AppStorageKey.customBreakMinutes)
    private var customBreakMinutes: Int = Constants.defaultCustomBreakMinutes
    var timerManager: TimerManager
    var closePopover: (() -> Void)?

    var body: some View {
        VStack(spacing: 4) {
            timerDisplay
            controlButtons
            postBreakTransitionPrompt
            presetSelector
        }
        .frame(maxWidth: .infinity, minHeight: 410, alignment: .top)
    }

    private var timerDisplay: some View {
        VStack(spacing: 12) {
            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(statusText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                focusStatusIcon
                    .padding(.leading, 2)
            }
            .frame(height: 26)

            timerText

            if showsProgress {
                ProgressView(value: progress)
                    .tint(statusColor)
                    .animation(.linear, value: progress)
                    .padding(.horizontal, 24)
            } else {
                Color.clear
                    .frame(height: 4)
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private var timerGlow: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        Color(red: 1.00, green: 0.67, blue: 0.31).opacity(isFocusing ? 0.44 : 0.34),
                        Color(red: 1.00, green: 0.75, blue: 0.39).opacity(0.18),
                        .clear,
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 128
                )
            )
            .frame(width: 260, height: 90)
            .blur(radius: 8)
            .offset(y: 44)
            .allowsHitTesting(false)
    }

    private var timerText: some View {
        ZStack {
            timerGlow

            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                HStack(spacing: 0) {
                    Text(minutesString)
                        .foregroundStyle(PopoverChrome.ink)
                        .contentTransition(.numericText())
                    Text(":")
                        .font(.system(size: 46, weight: .semibold, design: .rounded))
                        .foregroundStyle(PopoverChrome.accent)
                        .opacity(colonOpacity(at: context.date))
                    Text(secondsString)
                        .foregroundStyle(PopoverChrome.ink)
                        .contentTransition(.numericText())
                }
            }
            .font(.system(size: 66, weight: .bold, design: .rounded))
            .monospacedDigit()
            .shadow(color: Color(red: 0.95, green: 0.45, blue: 0.13).opacity(0.15), radius: 18, x: 0, y: 10)
            .animation(.default, value: appState.remainingSeconds)
        }
        .frame(height: 78)
    }

    private var focusStatusIcon: some View {
        TimelineView(.animation(minimumInterval: 1 / 60)) { context in
            Image(focusIconName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 35, height: 35)
                .offset(y: focusIconOffset(at: context.date))
                .shadow(color: PopoverChrome.accent.opacity(isFocusing ? 0.26 : 0.12), radius: 8, x: 0, y: 2)
        }
        .frame(width: 35, height: 35)
    }

    private var controlButtons: some View {
        HStack(spacing: 10) {
            switch appState.timerState {
            case .idle:
                Button {
                    timerManager.startFocus(category: selectedFocusCategory)
                } label: {
                    Label("집중 시작", systemImage: "play.fill")
                }
                .buttonStyle(TimerGradientButtonStyle())

            case .focusing:
                Button {
                    timerManager.pause()
                } label: {
                    Label("일시정지", systemImage: "pause.fill")
                }
                .buttonStyle(LanternSecondaryButtonStyle())

                Button {
                    timerManager.reset()
                } label: {
                    Label("리셋", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(LanternSecondaryButtonStyle())

            case .paused:
                Button {
                    timerManager.resume()
                } label: {
                    Label("재개", systemImage: "play.fill")
                }
                .buttonStyle(TimerGradientButtonStyle())

                Button {
                    timerManager.reset()
                } label: {
                    Label("리셋", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(LanternSecondaryButtonStyle())

            case .breakAlert:
                Button {
                    timerManager.startBreak()
                } label: {
                    Label("휴식 시작", systemImage: "cup.and.saucer.fill")
                }
                .buttonStyle(TimerGradientButtonStyle())

                Button {
                    timerManager.reset()
                } label: {
                    Label("건너뛰기", systemImage: "forward.fill")
                }
                .buttonStyle(LanternSecondaryButtonStyle())

            case .breaking:
                Button {
                    timerManager.reset()
                } label: {
                    Label("휴식 종료", systemImage: "stop.fill")
                }
                .buttonStyle(LanternSecondaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .offset(y: -9)
    }

    @ViewBuilder
    private var postBreakTransitionPrompt: some View {
        if appState.timerState == .idle, let prompt = appState.breakTransitionPrompt {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PopoverChrome.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("휴식 후 다음 흐름")
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .foregroundStyle(PopoverChrome.ink)
                        Text("다음 행동을 알려주면 주의 전환 신호를 더 정확하게 해석할 수 있어요.")
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .foregroundStyle(PopoverChrome.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(spacing: 7) {
                    Button {
                        selectedFocusCategory = prompt.previousCategory
                        timerManager.continueAfterBreak(category: prompt.previousCategory)
                    } label: {
                        Label("같은 작업 계속", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TimerGradientButtonStyle())

                    HStack(spacing: 7) {
                        Menu {
                            ForEach(productiveTransitionCategories, id: \.self) { category in
                                Button {
                                    selectedFocusCategory = category
                                    timerManager.resolveBreakTransition(.plannedTaskSwitch, nextCategory: category)
                                } label: {
                                    Text("\(Constants.categoryEmoji(for: category)) \(category)")
                                }
                            }
                        } label: {
                            Label("다른 작업", systemImage: "arrow.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(LanternSecondaryButtonStyle())

                        Button {
                            timerManager.resolveBreakTransition(.externalTransition)
                            closePopover?()
                        } label: {
                            Label("자리 비움", systemImage: "figure.walk")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(LanternSecondaryButtonStyle())
                    }

                }
            }
            .padding(12)
            .background(PopoverChrome.surfaceAlt.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(PopoverChrome.divider, lineWidth: 1)
            )
            .padding(.horizontal, 2)
            .padding(.bottom, 8)
            .offset(y: -6)
        }
    }

    private var presetSelector: some View {
        Group {
            if appState.timerState == .idle, appState.breakTransitionPrompt == nil {
                VStack(spacing: 8) {
                    Text("프리셋")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    presetChips

                    HStack(spacing: 8) {
                        Text("카테고리")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(PopoverChrome.inkSecondary)
                        Spacer(minLength: 8)
                        Menu {
                            ForEach(Constants.allCategories, id: \.self) { cat in
                                Button {
                                    selectedFocusCategory = cat
                                } label: {
                                    Text("\(Constants.categoryEmoji(for: cat)) \(cat)")
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text("\(Constants.categoryEmoji(for: selectedFocusCategory)) \(selectedFocusCategory)")
                                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(PopoverChrome.ink)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(PopoverChrome.inkSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 10)
                        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(PopoverChrome.divider, lineWidth: 1)
                        )
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(PopoverChrome.surfaceAlt.opacity(0.82), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                }
            }
        }
    }

    private var productiveTransitionCategories: [String] {
        Constants.allCategories.filter { Constants.postBreakProductiveCategories.contains($0) }
    }

    private var presetChips: some View {
        HStack(spacing: 6) {
            ForEach(Constants.PomodoroPreset.allCases) { preset in
                Button {
                    applyPreset(preset)
                } label: {
                    Text(preset.rawValue)
                        .font(.system(size: 12.5, weight: currentPreset == preset ? .bold : .medium, design: .rounded))
                        .foregroundStyle(currentPreset == preset ? PopoverChrome.accentInk : PopoverChrome.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(presetChipFill(for: preset))
                        )
                        .shadow(color: currentPreset == preset ? PopoverChrome.accent.opacity(0.28) : .clear, radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .onHover { isHovering in
                    hoveredPreset = isHovering ? preset : nil
                }
            }
        }
        .padding(4)
        .background(PopoverChrome.surfaceAlt.opacity(0.82), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
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
            appState.focusMinutes = customFocusMinutes
            appState.breakMinutes = customBreakMinutes
        }
    }

    private func presetChipFill(for preset: Constants.PomodoroPreset) -> Color {
        if currentPreset == preset {
            return PopoverChrome.accent
        }
        if hoveredPreset == preset {
            return PopoverChrome.card
        }
        return .clear
    }

    private var statusText: String {
        switch appState.timerState {
        case .idle: return "준비"
        case .focusing: return "집중 중"
        case .paused: return "잠시 멈춤"
        case .breakAlert: return "집중 완료"
        case .breaking: return "휴식 중"
        }
    }

    private var statusColor: Color {
        switch appState.timerState {
        case .idle, .paused:
            return PopoverChrome.accent
        case .focusing:
            return .orange
        case .breakAlert:
            return .yellow
        case .breaking:
            return .green
        }
    }

    private var isFocusing: Bool {
        appState.timerState == .focusing
    }

    private var isFocusSessionActive: Bool {
        appState.timerState == .focusing || appState.timerState == .paused
    }

    private var showsProgress: Bool {
        switch appState.timerState {
        case .focusing, .breaking:
            return true
        default:
            return false
        }
    }

    private var focusIconName: String {
        isFocusSessionActive ? "FocusOnTransparent" : "FocusOffTransparent"
    }

    private var minutesString: String {
        let minutes = displayedSeconds / 60
        return String(format: "%02d", minutes)
    }

    private var secondsString: String {
        let seconds = displayedSeconds % 60
        return String(format: "%02d", seconds)
    }

    private var displayedSeconds: Int {
        appState.timerState == .idle ? appState.focusMinutes * 60 : appState.remainingSeconds
    }

    private func colonOpacity(at date: Date) -> Double {
        let cycle = 1.44
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
        let wave = (sin(phase * 2 * .pi - (.pi / 2)) + 1) / 2
        return 0.36 + (wave * 0.64)
    }

    private func focusIconOffset(at date: Date) -> CGFloat {
        let cycle = 3.1
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
        return CGFloat(sin(phase * 2 * .pi) * 1.4)
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
