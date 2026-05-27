import SwiftUI

struct AppearancePage: View {
    // 화면 모드: light / dark. (시스템 따라가기는 미구현)
    @AppStorage(Constants.AppStorageKey.appearanceMode)
    private var appearanceMode: String = Constants.defaultAppearanceMode
    @AppStorage(Constants.AppStorageKey.popoverTheme)
    private var popoverTheme: String = Constants.defaultPopoverTheme
    @AppStorage(Constants.AppStorageKey.menubarIcon)
    private var menubarIconRaw: String = Constants.defaultMenubarIcon
    @State private var accent: Color = SettingsTheme.accent
    @State private var density: String = "comfortable"
    @State private var appIcon: String = "auto"
    @State private var menubarAnim: Bool = true

    var body: some View {
        SettingsPageScroll {
            SettingsPageHeader(title: SettingsTab.appearance.label, subtitle: SettingsTab.appearance.subtitle)

            modeCard
            themeCard
            iconCard
        }
        .onAppear {
            // 시스템 모드 옵션 제거 — 기존 "system" 저장값은 라이트로 정규화한다.
            if appearanceMode != "light" && appearanceMode != "dark" {
                appearanceMode = "light"
            }
            if popoverTheme != Constants.defaultPopoverTheme {
                popoverTheme = Constants.defaultPopoverTheme
            }
        }
    }

    // MARK: - 모드 카드 (밝기 모드 + 강조 색 + 정보 밀도)

    private var modeCard: some View {
        SettingsGroupCard("모드") {
            SettingsRow(
                "화면 모드",
                subtitle: "설정 윈도우에 적용할 색 모드를 선택합니다."
            ) {
                Picker("", selection: $appearanceMode) {
                    Text("라이트").tag("light")
                    Text("다크").tag("dark")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
            SettingsRow(
                "강조 색",
                subtitle: "버튼·활성 상태·토스트에 사용되는 색입니다.",
                comingSoon: true
            ) {
                HStack(spacing: 8) {
                    ForEach(SettingsTheme.accentPalette, id: \.name) { swatch in
                        Circle()
                            .fill(swatch.color)
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle()
                                    .stroke(accent == swatch.color ? Color.white : Color.clear, lineWidth: 2)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                            )
                            .onTapGesture { accent = swatch.color }
                            .help(swatch.name)
                    }
                }
            }
            SettingsRow(
                "정보 밀도",
                subtitle: "목록 항목 간 여백과 폰트 크기를 조절합니다.",
                comingSoon: true
            ) {
                Picker("", selection: $density) {
                    Text("촘촘").tag("compact")
                    Text("보통").tag("comfortable")
                    Text("넉넉").tag("comfy")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
        }
    }

    // MARK: - 테마 카드 (팝오버 UI 스타일)

    private var themeCard: some View {
        SettingsGroupCard("테마") {
            SettingsRow(
                "팝오버 테마",
                subtitle: "현재 팝오버에 적용되는 테마입니다. 다른 테마는 준비 중입니다."
            ) {
                popoverThemeMenu
            }
        }
    }

    private var popoverThemeMenu: some View {
        Menu {
            Button {
                popoverTheme = Constants.defaultPopoverTheme
            } label: {
                Label("따뜻한 등불", systemImage: popoverTheme == Constants.defaultPopoverTheme ? "checkmark" : "")
            }

            Button {} label: {
                HStack {
                    Text("편안한 풀")
                    Text("준비 중")
                }
            }
            .disabled(true)

            Button {} label: {
                HStack {
                    Text("게임 픽셀")
                    Text("준비 중")
                }
            }
            .disabled(true)
        } label: {
            HStack(spacing: 8) {
                Text("🏮")
                    .font(.system(size: 14))
                Text("따뜻한 등불")
                    .font(.callout)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: 190, alignment: .leading)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 아이콘 카드

    private var iconCard: some View {
        SettingsGroupCard("아이콘") {
            SettingsRow(
                "메뉴바 아이콘",
                subtitle: "메뉴바에 표시되는 기본 아이콘을 선택합니다."
            ) {
                menubarIconMenu
            }
            SettingsRow(
                "앱 아이콘",
                subtitle: "Dock 및 앱 전환기에 표시되는 아이콘 스타일.",
                comingSoon: true
            ) {
                Picker("", selection: $appIcon) {
                    Text("자동").tag("auto")
                    Text("라이트").tag("light")
                    Text("다크").tag("dark")
                    Text("축제").tag("festival")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 240)
            }
            SettingsRow(
                "메뉴바 아이콘 애니메이션",
                subtitle: "타이머가 실행 중일 때 호롱불이 깜빡입니다.",
                comingSoon: true
            ) {
                Toggle("", isOn: $menubarAnim).labelsHidden()
            }
        }
    }

    private var selectedMenubarIcon: Constants.MenubarIconStyle {
        Constants.MenubarIconStyle(rawValue: menubarIconRaw) ?? .horong
    }

    private var menubarIconMenu: some View {
        Menu {
            ForEach(Constants.MenubarIconStyle.allCases) { style in
                Button {
                    menubarIconRaw = style.rawValue
                } label: {
                    Label(
                        style.label,
                        systemImage: selectedMenubarIcon == style ? "checkmark" : ""
                    )
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(selectedMenubarIcon.imageName)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                Text(selectedMenubarIcon.label)
                    .font(.callout)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: 190, alignment: .leading)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
