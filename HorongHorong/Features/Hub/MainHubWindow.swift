import SwiftUI

/// 기록 · 뉴스 보관함 · 통계 · 성취를 담는 통합 윈도우.
///
/// **한 번 본 탭만 만들고, 만든 뒤에는 계속 살려둔다.**
///
/// switch 로 갈아끼우면 탭을 옮길 때마다 각 뷰의 @State 와 StatsDetailWindow 의
/// loadCache 가 날아가 매번 다시 로딩한다. 그렇다고 넷을 전부 미리 올려두면
/// **창을 여는 순간 보지도 않을 탭의 `@Query` 까지 전부 도는 것**이 문제였다
/// (실측 2026-09-01: 메모 13,002건일 때 한 번 열 때 약 3만 9천 개가 실체화됐다).
///
/// 그래서 «매번 다시 만들기» 와 «미리 다 만들기» 사이를 택한다 — 처음 누를 때 만들고,
/// 그 뒤로는 남겨둔다. 비용이 사라지는 게 아니라 **실제로 그 탭을 볼 때로 옮겨간다.**
struct MainHubWindow: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dependencies) private var dependencies
    @AppStorage(Constants.AppStorageKey.popoverTheme)
    private var popoverTheme: String = Constants.defaultPopoverTheme
    /// 한 번이라도 연 탭. 창을 닫았다 열면 비워져 다시 활성 탭 하나만 만든다.
    @State private var openedTabs: Set<HubTab> = []

    var body: some View {
        HStack(spacing: 0) {
            rail
            Divider().overlay(PopoverChrome.divider)

            ZStack {
                if openedTabs.contains(.memo) {
                    MindView()
                        .hubTabVisible(appState.hubTab == .memo)
                }
                if openedTabs.contains(.news) {
                    NewsReportArchiveWindow()
                        .hubTabVisible(appState.hubTab == .news)
                }
                if openedTabs.contains(.stats), let dependencies {
                    StatsDetailWindow(
                        todoRepository: dependencies.todoRepository,
                        reflectionRepository: dependencies.reflectionRepository
                    )
                        .hubTabVisible(appState.hubTab == .stats)
                }
                if openedTabs.contains(.achievement), let dependencies {
                    AchievementDetailWindow(
                        repository: dependencies.achievementRepository,
                        rewardRepository: dependencies.rewardRepository
                    )
                        .hubTabVisible(appState.hubTab == .achievement)
                }
            }
        }
        .onAppear { openedTabs.insert(appState.hubTab) }
        .onChange(of: appState.hubTab) { _, tab in openedTabs.insert(tab) }
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
            if tab == .memo, appState.hubTab == .memo {
                withAnimation(.easeInOut(duration: 0.24)) {
                    appState.isRecordRailVisible.toggle()
                }
            } else {
                appState.hubTab = tab
                if tab == .memo {
                    withAnimation(.easeInOut(duration: 0.24)) {
                        appState.isRecordRailVisible = true
                    }
                }
            }
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
            // contentShape 는 label 안에 있어야 한다.
            // Button 바깥에 걸면 히트 영역이 label 내용(아이콘·글자) 모양 그대로라
            // 배경이 비어 있는 비선택 항목은 글자에 정확히 대야만 눌린다.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tab == .memo ? "기록 · 다시 누르면 내 머리속을 접습니다" : tab.label)
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
