import SwiftUI

/// 전체 메모 · 뉴스 보관함 · 통계 · 성취를 담는 통합 윈도우.
///
/// 네 화면을 모두 ZStack 에 올려둔 채 보이는 것만 바꾼다.
/// switch 로 갈아끼우면 탭을 옮길 때마다 각 뷰의 @State 와
/// StatsDetailWindow 의 loadCache 가 날아가 매번 다시 로딩한다.
struct MainHubWindow: View {
    @Environment(AppState.self) private var appState
    @AppStorage(Constants.AppStorageKey.popoverTheme)
    private var popoverTheme: String = Constants.defaultPopoverTheme

    var body: some View {
        HStack(spacing: 0) {
            rail
            Divider().overlay(PopoverChrome.divider)

            ZStack {
                MemoBrowserWindow()
                    .hubTabVisible(appState.hubTab == .memo)
                NewsReportArchiveWindow()
                    .hubTabVisible(appState.hubTab == .news)
                StatsDetailWindow()
                    .hubTabVisible(appState.hubTab == .stats)
                AchievementDetailWindow()
                    .hubTabVisible(appState.hubTab == .achievement)
            }
        }
        .background(PopoverChrome.surface)
        .appearanceAccentTint(.popover)
    }

    // MARK: - 아이콘 레일

    private var rail: some View {
        VStack(spacing: 6) {
            ForEach(HubTab.allCases) { tab in
                railItem(tab)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.top, 12)
        .frame(width: 64)
        .frame(maxHeight: .infinity)
        .background(PopoverChrome.surfaceAlt)
    }

    private func railItem(_ tab: HubTab) -> some View {
        let isSelected = appState.hubTab == tab
        return Button {
            appState.hubTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.systemIcon)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                Text(tab.label)
                    .font(.system(size: 9, weight: isSelected ? .bold : .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? PopoverChrome.selectionInk : PopoverChrome.inkSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous)
                    .fill(isSelected ? PopoverChrome.selectionFill : .clear)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help(tab.label)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension View {
    /// 통합 윈도우에서 선택되지 않은 탭을 숨긴다.
    ///
    /// `.disabled` 까지 걸어야 숨은 탭의 TextField 가 Tab 키 포커스를 가져가지 않는다.
    /// 뷰 자체는 계층에 남아 @State 와 onReceive 가 그대로 살아있다.
    func hubTabVisible(_ isActive: Bool) -> some View {
        opacity(isActive ? 1 : 0)
            .disabled(!isActive)
            .accessibilityHidden(!isActive)
    }
}
