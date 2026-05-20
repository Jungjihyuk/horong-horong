import SwiftUI

struct SettingsRoot: View {
    @State private var selection: SettingsTab = .general
    @State private var query: String = ""
    @State private var showResetConfirm: Bool = false

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selection: $selection, query: $query)
                .navigationSplitViewColumnWidth(min: 200, ideal: SettingsTheme.sidebarWidth, max: 280)
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
            // 최소화/확대 버튼 활성화. Resizable 은 .windowResizability(.contentMinSize) 에서 이미 보장.
            window.styleMask.insert([.miniaturizable, .resizable])
            // 트래픽 라이트를 우/하로 살짝 밀어 cmux 처럼 여유 있는 간격을 만든다.
            if window.horongTrafficLightController == nil {
                window.horongTrafficLightController = TrafficLightInsetController(window: window, dx: 6, dy: -4)
            }
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
