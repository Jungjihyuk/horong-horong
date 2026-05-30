import SwiftUI

struct TimerPage: View {
    @Environment(AppState.self) private var appState
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
    @AppStorage(Constants.AppStorageKey.postBreakTransitionPromptMode)
    private var postBreakTransitionPromptModeRaw: String = Constants.PostBreakTransitionPromptMode.afterDelay.rawValue
    @AppStorage(Constants.AppStorageKey.postBreakTransitionPromptDelayMinutes)
    private var postBreakTransitionPromptDelayMinutes: Int = Constants.defaultPostBreakTransitionPromptDelayMinutes

    @AppStorage(Constants.AppStorageKey.menubarLabelStyle)
    private var menubarLabelStyleRaw: String = Constants.defaultMenubarLabelStyle
    @AppStorage(Constants.AppStorageKey.menubarTimeStyle)
    private var menubarTimeStyleRaw: String = Constants.defaultMenubarTimeStyle

    @State private var autoBreak: Bool = true
    @State private var soundEnabled: Bool = true

    private var menubarLabelStyle: Binding<Constants.MenubarLabelStyle> {
        Binding(
            get: { Constants.MenubarLabelStyle(rawValue: menubarLabelStyleRaw) ?? .timeAndIcon },
            set: { menubarLabelStyleRaw = $0.rawValue }
        )
    }

    private var menubarTimeStyle: Binding<Constants.MenubarTimeStyle> {
        Binding(
            get: { Constants.MenubarTimeStyle(rawValue: menubarTimeStyleRaw) ?? .mmss },
            set: { menubarTimeStyleRaw = $0.rawValue }
        )
    }

    private var menubarTimeStyleDisabled: Bool {
        menubarLabelStyle.wrappedValue == .categoryOnly || menubarLabelStyle.wrappedValue == .iconOnly
    }

    private var postBreakTransitionPromptMode: Binding<Constants.PostBreakTransitionPromptMode> {
        Binding(
            get: {
                Constants.PostBreakTransitionPromptMode(rawValue: postBreakTransitionPromptModeRaw) ?? .afterDelay
            },
            set: { postBreakTransitionPromptModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        SettingsPageScroll {
            SettingsPageHeader(title: SettingsTab.timer.label, subtitle: SettingsTab.timer.subtitle)

            SettingsGroupCard("프리셋") {
                presetGrid
            }

            Text("프리셋 카드를 클릭하면 그 값이 현재 타이머에 적용됩니다. 아래 표에서 각 프리셋의 시간을 수정하면 다음번 그 프리셋을 누를 때부터 새 값이 사용돼요.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
                .padding(.top, -10)

            SettingsGroupCard("프리셋 시간 편집") {
                presetEditorRow(
                    icon: "🍅",
                    name: "포모도로",
                    focusBinding: $pomodoroFocusMinutes,
                    breakBinding: $pomodoroBreakMinutes,
                    focusRange: 1...120,
                    breakRange: 1...30
                )
                presetEditorRow(
                    icon: "🔥",
                    name: "긴 집중",
                    focusBinding: $longFocusFocusMinutes,
                    breakBinding: $longFocusBreakMinutes,
                    focusRange: 1...240,
                    breakRange: 1...60
                )
                presetEditorRow(
                    icon: "⚙️",
                    name: "커스텀",
                    focusBinding: $customFocusMinutes,
                    breakBinding: $customBreakMinutes,
                    focusRange: 1...240,
                    breakRange: 1...60
                )
            }

            HStack {
                Button("모든 프리셋 시간 공장 초기화") {
                    pomodoroFocusMinutes = Constants.defaultPomodoroFocusMinutes
                    pomodoroBreakMinutes = Constants.defaultPomodoroBreakMinutes
                    longFocusFocusMinutes = Constants.defaultLongFocusFocusMinutes
                    longFocusBreakMinutes = Constants.defaultLongFocusBreakMinutes
                    customFocusMinutes = Constants.defaultCustomFocusMinutes
                    customBreakMinutes = Constants.defaultCustomBreakMinutes
                }
                .buttonStyle(.link)
                .help("3개 프리셋(포모도로 / 긴 집중 / 커스텀)의 편집 값을 호롱호롱이 처음 설치됐을 때의 값으로 되돌립니다. 진행 중인 타이머에는 영향을 주지 않아요.")
                Spacer()
            }
            .padding(.leading, 4)

            SettingsGroupCard("동작") {
                SettingsRow(
                    "휴식 후 다음 흐름 확인",
                    subtitle: postBreakTransitionPromptMode.wrappedValue.subtitle
                ) {
                    Picker("", selection: postBreakTransitionPromptMode) {
                        ForEach(Constants.PostBreakTransitionPromptMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }

                if postBreakTransitionPromptMode.wrappedValue == .afterDelay {
                    SettingsRow(
                        "확인까지 기다릴 시간",
                        subtitle: "이 시간 안에 포모도로나 업무·개발·공부·조사·기록 활동이 있으면 묻지 않습니다."
                    ) {
                        NumberField(
                            value: $postBreakTransitionPromptDelayMinutes,
                            range: 1...60,
                            suffix: "분",
                            width: 48
                        )
                    }
                }

                SettingsRow(
                    "집중 완료 시 자동으로 휴식 시작",
                    subtitle: "휴식 종료 후 다음 집중도 자동으로 이어집니다.",
                    comingSoon: true
                ) {
                    Toggle("", isOn: $autoBreak).labelsHidden()
                }
                SettingsRow(
                    "종료 알림 사운드",
                    subtitle: "시스템 알림과 함께 호롱호롱 사운드를 재생합니다.",
                    comingSoon: true
                ) {
                    Toggle("", isOn: $soundEnabled).labelsHidden()
                }
            }

            SettingsGroupCard("메뉴바 표시") {
                SettingsRow(
                    "라벨 형식",
                    subtitle: "집중·휴식 중 메뉴바에 보여줄 내용."
                ) {
                    Picker("", selection: menubarLabelStyle) {
                        ForEach(Constants.MenubarLabelStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
                SettingsRow(
                    "시간 형식",
                    subtitle: menubarTimeStyleDisabled
                        ? "라벨에 시간을 표시하는 경우에만 적용됩니다."
                        : "초까지 / 분 단위 중 선택. 분 단위가 시각적으로 더 조용합니다."
                ) {
                    Picker("", selection: menubarTimeStyle) {
                        ForEach(Constants.MenubarTimeStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .disabled(menubarTimeStyleDisabled)
                }
            }
        }
    }

    private var presetGrid: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 12) {
            presetCard(icon: "🍅", name: "포모도로",
                       focus: pomodoroFocusMinutes, rest: pomodoroBreakMinutes) {
                appState.focusMinutes = pomodoroFocusMinutes
                appState.breakMinutes = pomodoroBreakMinutes
            }
            presetCard(icon: "🔥", name: "긴 집중",
                       focus: longFocusFocusMinutes, rest: longFocusBreakMinutes) {
                appState.focusMinutes = longFocusFocusMinutes
                appState.breakMinutes = longFocusBreakMinutes
            }
            presetCard(icon: "⚙️", name: "커스텀",
                       focus: customFocusMinutes, rest: customBreakMinutes) {
                appState.focusMinutes = customFocusMinutes
                appState.breakMinutes = customBreakMinutes
            }
        }
        .padding(14)
    }

    private func presetCard(icon: String, name: String, focus: Int, rest: Int, apply: @escaping () -> Void) -> some View {
        Button(action: apply) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(icon).font(.system(size: 16))
                    Text(name).font(.callout.bold())
                }
                HStack(spacing: 10) {
                    presetMetric(value: focus, label: "집중")
                    Divider().frame(height: 24)
                    presetMetric(value: rest, label: "휴식")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func presetMetric(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)")
                .font(.system(size: 22, weight: .semibold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func presetEditorRow(
        icon: String,
        name: String,
        focusBinding: Binding<Int>,
        breakBinding: Binding<Int>,
        focusRange: ClosedRange<Int>,
        breakRange: ClosedRange<Int>
    ) -> some View {
        SettingsRow("\(icon) \(name)", subtitle: "집중/휴식 분") {
            HStack(spacing: 6) {
                Text("집중").font(.caption).foregroundStyle(.secondary)
                NumberField(value: focusBinding, range: focusRange, suffix: "분", width: 48)
                Text("휴식").font(.caption).foregroundStyle(.secondary)
                NumberField(value: breakBinding, range: breakRange, suffix: "분", width: 44)
            }
        }
    }

}
