import AppKit
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
    @AppStorage(Constants.AppStorageKey.pomodoroReflectionEnabled)
    private var pomodoroReflectionEnabled: Bool = Constants.defaultPomodoroReflectionEnabled
    @AppStorage(Constants.AppStorageKey.timerCompletionNotificationStyle)
    private var timerCompletionNotificationStyleRaw: String =
        Constants.defaultTimerCompletionNotificationStyle.rawValue
    @AppStorage(Constants.AppStorageKey.todayPlanningReminderEnabled)
    private var todayPlanningReminderEnabled: Bool = Constants.defaultTodayPlanningReminderEnabled
    @AppStorage(Constants.AppStorageKey.todayPlanningReminderDelayMinutes)
    private var todayPlanningReminderDelayMinutes: Int = Constants.defaultTodayPlanningReminderDelayMinutes

    @AppStorage(Constants.AppStorageKey.menubarLabelStyle)
    private var menubarLabelStyleRaw: String = Constants.defaultMenubarLabelStyle
    @AppStorage(Constants.AppStorageKey.menubarTimeStyle)
    private var menubarTimeStyleRaw: String = Constants.defaultMenubarTimeStyle

    @State private var autoBreak: Bool = true
    @State private var soundEnabled: Bool = true
    @State private var notificationAuthorizationState: NotificationManager.AlertAuthorizationState?

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

    private var timerCompletionNotificationStyle: Binding<Constants.TimerCompletionNotificationStyle> {
        Binding(
            get: {
                Constants.TimerCompletionNotificationStyle(
                    rawValue: timerCompletionNotificationStyleRaw
                ) ?? Constants.defaultTimerCompletionNotificationStyle
            },
            set: { timerCompletionNotificationStyleRaw = $0.rawValue }
        )
    }

    private var requiresSystemNotificationPermission: Bool {
        timerCompletionNotificationStyle.wrappedValue == .system
            || todayPlanningReminderEnabled
    }

    private var notificationPermissionTaskID: String {
        "\(timerCompletionNotificationStyleRaw):\(todayPlanningReminderEnabled)"
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

            SettingsGroupCard("알림") {
                notificationStyleSelector

                SettingsRow(
                    "선택한 스타일 미리 확인",
                    subtitle: "실제 포모도로가 끝나기를 기다리지 않고 현재 선택한 알림을 보내봅니다."
                ) {
                    Button("시험 알림 보내기") {
                        Task {
                            await showSelectedNotificationPreview()
                        }
                    }
                    .controlSize(.small)
                }

                if requiresSystemNotificationPermission,
                   notificationAuthorizationState == .unavailable {
                    SettingsRow(
                        "macOS 알림이 꺼져 있어요",
                        subtitle: "macOS 알림을 사용하는 기능을 받으려면 시스템 설정에서 호롱호롱 알림을 허용하고 배너 또는 알림을 선택해 주세요."
                    ) {
                        Button("알림 설정 열기") {
                            openNotificationSettings()
                        }
                        .controlSize(.small)
                    }
                }

                SettingsRow(
                    "오늘 할 일 계획 알림",
                    subtitle: "앱 실행 \(todayPlanningReminderDelayMinutes)분 뒤 시작일이 오늘인 미완료 할 일이 없으면 하루 한 번 알려줍니다."
                ) {
                    Toggle("", isOn: $todayPlanningReminderEnabled)
                        .labelsHidden()
                        .onChange(of: todayPlanningReminderEnabled) { _, isEnabled in
                            TodayPlanningReminderCoordinator.shared.settingDidChange(
                                isEnabled: isEnabled
                            )
                        }
                }

                if todayPlanningReminderEnabled {
                    SettingsRow(
                        "알림까지 기다릴 시간",
                        subtitle: "이 시간 안에 오늘 시작할 할 일을 등록하면 알림을 보내지 않습니다."
                    ) {
                        NumberField(
                            value: $todayPlanningReminderDelayMinutes,
                            range: Constants.todayPlanningReminderDelayMinutesRange,
                            suffix: "분",
                            width: 48
                        )
                        .onChange(of: todayPlanningReminderDelayMinutes) { _, _ in
                            TodayPlanningReminderCoordinator.shared.settingDidChange(
                                isEnabled: true
                            )
                        }
                    }
                }
            }

            SettingsGroupCard("동작") {
                SettingsRow(
                    "포모도로 완료 후 돌아보기",
                    subtitle: "집중 경험과 진행 결과를 기기에 저장해, 나에게 맞는 몰입 패턴을 찾는 데 사용합니다."
                ) {
                    Toggle("", isOn: $pomodoroReflectionEnabled)
                        .labelsHidden()
                }

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
        .task(id: notificationPermissionTaskID) {
            guard requiresSystemNotificationPermission else {
                notificationAuthorizationState = nil
                return
            }
            await prepareSystemNotifications()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard requiresSystemNotificationPermission else { return }
            Task {
                await refreshSystemNotificationState()
            }
        }
    }

    @MainActor
    private func prepareSystemNotifications() async {
        let previousState = await NotificationManager.shared.alertAuthorizationState()
        let state = await NotificationManager.shared.requestAuthorizationIfNeeded()
        guard requiresSystemNotificationPermission else { return }

        notificationAuthorizationState = state
        if todayPlanningReminderEnabled,
           previousState != .available,
           state == .available {
            TodayPlanningReminderCoordinator.shared.settingDidChange(isEnabled: true)
        }
    }

    @MainActor
    private func refreshSystemNotificationState() async {
        let previousState = notificationAuthorizationState
        let currentState = await NotificationManager.shared.alertAuthorizationState()
        guard requiresSystemNotificationPermission else { return }

        notificationAuthorizationState = currentState
        if todayPlanningReminderEnabled,
           previousState != .available,
           currentState == .available {
            TodayPlanningReminderCoordinator.shared.settingDidChange(isEnabled: true)
        }
    }

    @MainActor
    private func showSelectedNotificationPreview() async {
        let content = Constants.focusCompletionNotificationContent(
            focusMinutes: pomodoroFocusMinutes
        )

        switch timerCompletionNotificationStyle.wrappedValue {
        case .system:
            await prepareSystemNotifications()
            guard timerCompletionNotificationStyle.wrappedValue == .system else { return }
            guard notificationAuthorizationState == .available else {
                ToastPanel.shared.show(
                    icon: "🔕",
                    title: "알림을 보낼 수 없어요",
                    subtitle: "macOS 알림 설정에서 호롱호롱 알림을 확인해 주세요."
                )
                return
            }
            NotificationManager.shared.send(
                title: content.title,
                subtitle: content.subtitle,
                body: content.body,
                identifier: Constants.timerCompletionPreviewNotificationIdentifier,
                replacesExisting: true
            )

        case .horong:
            ToastPanel.shared.showTimerAlert(
                title: content.title,
                subtitle: content.subtitle,
                detail: content.body
            )
        }
    }

    private var notificationStyleSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("포모도로 종료 알림 스타일")
                    .font(.callout)
                Text("집중과 휴식이 끝났을 때 사용할 디자인을 하나 선택해 주세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(Constants.TimerCompletionNotificationStyle.allCases) { style in
                notificationStyleCard(style)
            }

            Text("이 선택은 포모도로 종료 알림에만 적용됩니다. 오늘 할 일과 메모 미리알림은 계속 macOS 알림으로 표시돼요.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 0.5)
                .padding(.leading, 14)
        }
    }

    private func notificationStyleCard(
        _ style: Constants.TimerCompletionNotificationStyle
    ) -> some View {
        let isSelected = timerCompletionNotificationStyle.wrappedValue == style
        let content = Constants.focusCompletionNotificationContent(
            focusMinutes: pomodoroFocusMinutes
        )

        return Button {
            timerCompletionNotificationStyle.wrappedValue = style
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(style.label)
                                .font(.callout.bold())
                            if style == Constants.defaultTimerCompletionNotificationStyle {
                                Text("기본")
                                    .font(.caption2.bold())
                                    .foregroundStyle(SettingsTheme.accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        SettingsTheme.accent.opacity(0.12),
                                        in: Capsule()
                                    )
                            }
                        }
                        Text(style.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(
                            isSelected
                                ? SettingsTheme.accent
                                : Color.secondary.opacity(0.45)
                        )
                }

                notificationPreview(style: style, content: content)
                    .frame(maxWidth: .infinity)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSelected
                            ? SettingsTheme.accent.opacity(0.08)
                            : Color.primary.opacity(0.035)
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected
                            ? SettingsTheme.accent.opacity(0.75)
                            : Color.primary.opacity(0.1),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(style.label) 선택")
        .accessibilityValue(isSelected ? "선택됨" : "선택 안 됨")
    }

    @ViewBuilder
    private func notificationPreview(
        style: Constants.TimerCompletionNotificationStyle,
        content: Constants.TimerCompletionNotificationContent
    ) -> some View {
        switch style {
        case .system:
            SystemTimerNotificationPreview(content: content)
        case .horong:
            ToastView(
                icon: "",
                title: content.title,
                subtitle: content.subtitle,
                detail: content.body,
                style: .timerAlert,
                onDismiss: {}
            )
            .allowsHitTesting(false)
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
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

private struct SystemTimerNotificationPreview: View {
    let content: Constants.TimerCompletionNotificationContent

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(content.title)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("지금")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(content.subtitle)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(content.body)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(width: 430, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "macOS 알림 예시. \(content.title), \(content.subtitle), \(content.body)"
        )
    }
}
