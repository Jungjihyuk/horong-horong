import SwiftUI

struct SettingsRoot: View {
    @State private var selection: SettingsTab = .general
    @State private var query: String = ""
    @State private var showResetConfirm: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var hostWindow: NSWindow?
    @AppStorage(Constants.AppStorageKey.appearanceMode)
    private var appearanceMode: String = Constants.defaultAppearanceMode

    init(initialSelection: SettingsTab = .general) {
        _selection = State(initialValue: initialSelection)
    }

    /// 화면 모드를 SwiftUI ColorScheme 으로 (nil = 시스템 따라감).
    private var colorScheme: ColorScheme? {
        switch appearanceMode {
        case "dark":  return .dark
        case "light": return .light
        default:      return nil
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SettingsSidebar(selection: $selection, query: $query)
                .navigationSplitViewColumnWidth(min: 200, ideal: SettingsTheme.sidebarWidth, max: 280)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            VStack(spacing: 0) {
                detailView
                Divider()
                footerBar
            }
        }
        .navigationTitle("설정 — \(selection.label)")
        .frame(
            minWidth: SettingsTheme.windowMinSize.width,
            minHeight: SettingsTheme.windowMinSize.height
        )
        .configureHostWindow { window in
            hostWindow = window
            configureWindowChrome(window)
        }
        .preferredColorScheme(colorScheme)
        .onChange(of: appearanceMode) { _, newValue in
            applyAppearance(newValue, to: hostWindow)
        }
        .onChange(of: columnVisibility) { _, _ in
            configureWindowChrome(hostWindow)
        }
        .alert("기본값으로 복원하시겠어요?", isPresented: $showResetConfirm) {
            Button("취소", role: .cancel) {}
            Button("복원", role: .destructive) {
                resetToDefaults(for: selection)
            }
        } message: {
            Text("\(selection.label) 페이지의 설정만 기본값으로 되돌립니다.")
        }
    }

    private func collapseSidebar() {
        withAnimation { columnVisibility = .detailOnly }
    }

    private func expandSidebar() {
        withAnimation { columnVisibility = .all }
    }

    private func configureWindowChrome(_ window: NSWindow?) {
        guard let window else { return }

        // 최소화/확대 + fullSizeContentView 로 사이드바 배경이 트래픽 라이트 영역까지 확장된다.
        window.styleMask.insert([.miniaturizable, .resizable, .fullSizeContentView])
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        if window.horongTrafficLightController == nil {
            window.horongTrafficLightController = TrafficLightInsetController(window: window, dx: 6, dy: -4)
        }
        if window.horongSidebarToggleController == nil {
            window.horongSidebarToggleController = SettingsSidebarToggleController(window: window)
        }
        window.horongSidebarToggleController?.update(isSidebarVisible: columnVisibility == .all) {
            if columnVisibility == .all {
                collapseSidebar()
            } else {
                expandSidebar()
            }
        }
        applyAppearance(appearanceMode, to: window)
    }

    /// 설정 윈도우 *한 개만* 라이트/다크/시스템 모드를 따르도록 NSWindow.appearance 를 갱신한다.
    /// NSApp.appearance 를 건드리지 않아 팝오버·통계 윈도우는 영향을 받지 않는다.
    private func applyAppearance(_ mode: String, to window: NSWindow?) {
        guard let window else { return }
        switch mode {
        case "dark":
            window.appearance = NSAppearance(named: .darkAqua)
        case "light":
            window.appearance = NSAppearance(named: .aqua)
        default:
            window.appearance = nil  // 시스템 따라감
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .general:    GeneralPage()
        case .appearance: AppearancePage()
        case .timer:      TimerPage()
        case .hotkey:     HotkeyPage()
        case .category:   CategoryMappingPage()
        case .stats:      StatsPage()
        case .news:       NewsPage()
        case .agent:      AgentPage()
        case .memo:       MemoPage()
        case .data:       DataPage()
        case .about:      AboutPage()
        }
    }

    private var footerBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
            Text("모든 변경 사항은 즉시 적용됩니다")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("기본값으로 복원") {
                showResetConfirm = true
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.03))
    }

    private func resetToDefaults(for tab: SettingsTab) {
        let defaults = UserDefaults.standard
        switch tab {
        case .timer:
            defaults.removeObject(forKey: Constants.AppStorageKey.pomodoroFocusMinutes)
            defaults.removeObject(forKey: Constants.AppStorageKey.pomodoroBreakMinutes)
            defaults.removeObject(forKey: Constants.AppStorageKey.longFocusFocusMinutes)
            defaults.removeObject(forKey: Constants.AppStorageKey.longFocusBreakMinutes)
            defaults.removeObject(forKey: Constants.AppStorageKey.customFocusMinutes)
            defaults.removeObject(forKey: Constants.AppStorageKey.customBreakMinutes)
            defaults.removeObject(forKey: Constants.AppStorageKey.menubarLabelStyle)
            defaults.removeObject(forKey: Constants.AppStorageKey.menubarTimeStyle)
        case .stats:
            defaults.removeObject(forKey: Constants.AppStorageKey.timelineStartHour)
            defaults.removeObject(forKey: Constants.AppStorageKey.timelineEndHour)
            defaults.removeObject(forKey: Constants.AppStorageKey.timelineBucketMinutes)
        case .news:
            defaults.removeObject(forKey: Constants.NewsStorageKey.interestKeywords)
            defaults.removeObject(forKey: Constants.NewsStorageKey.selectedProvider)
        case .agent:
            defaults.removeObject(forKey: Constants.AppStorageKey.agentRootDirectoryPath)
            defaults.removeObject(forKey: Constants.AppStorageKey.selectedAgentType)
            defaults.removeObject(forKey: Constants.AppStorageKey.planDayCount)
            defaults.removeObject(forKey: Constants.AppStorageKey.interestKeywords)
        case .category:
            for category in Constants.allCategories {
                IdleThresholdStore.shared.resetToDefault(category: category)
            }
        default:
            break
        }
    }
}
