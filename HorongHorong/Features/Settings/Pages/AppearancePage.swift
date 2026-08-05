import SwiftUI

struct AppearancePage: View {
    // 화면 모드: light / dark. (시스템 따라가기는 미구현)
    @AppStorage(Constants.AppStorageKey.appearanceMode)
    private var appearanceMode: String = Constants.defaultAppearanceMode
    @AppStorage(Constants.AppStorageKey.appearanceDensity)
    private var density: String = Constants.defaultAppearanceDensity
    @AppStorage(Constants.AppStorageKey.popoverTheme)
    private var popoverTheme: String = Constants.defaultPopoverTheme
    @AppStorage(Constants.AppStorageKey.warmLanternAccent)
    private var warmLanternAccent = AppearanceAccentPalette.defaultID(for: .warmLantern)
    @AppStorage(Constants.AppStorageKey.wineLanternAccent)
    private var wineLanternAccent = AppearanceAccentPalette.defaultID(for: .wineLantern)
    @AppStorage(Constants.AppStorageKey.gamePixelAccent)
    private var gamePixelAccent = AppearanceAccentPalette.defaultID(for: .gamePixel)
    @AppStorage(Constants.AppStorageKey.menubarIcon)
    private var menubarIconRaw: String = Constants.defaultMenubarIcon
    @AppStorage(Constants.AppStorageKey.appIcon)
    private var appIconRaw: String = Constants.defaultAppIcon

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
            if Constants.PopoverTheme(rawValue: popoverTheme) == nil {
                popoverTheme = Constants.defaultPopoverTheme
            }
            density = AppearanceDensity.normalized(rawValue: density).rawValue
            normalizeAccentSelections()
            appIconRaw = selectedAppIcon.rawValue
            AppIconManager.apply(selectedAppIcon)
        }
        .onChange(of: appIconRaw) { _, newValue in
            let normalized = Constants.AppIconStyle.normalized(rawValue: newValue)
            if newValue != normalized.rawValue {
                appIconRaw = normalized.rawValue
                return
            }
            AppIconManager.apply(normalized)
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
                subtitle: "현재 팝오버 테마와 앱의 버튼·활성 상태·토스트에 사용됩니다."
            ) {
                HStack(spacing: 8) {
                    ForEach(accentOptions) { option in
                        Button {
                            selectedAccentID = option.id
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(option.popoverColor)
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary.opacity(0.18), lineWidth: 0.5)
                                    )

                                if selectedAccentID == option.id {
                                    Circle()
                                        .stroke(Color.primary, lineWidth: 1.5)
                                        .frame(width: 25, height: 25)
                                }
                            }
                            .frame(width: 26, height: 26)
                            .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help(option.name)
                        .accessibilityLabel(option.name)
                        .accessibilityValue(selectedAccentID == option.id ? "선택됨" : "")
                    }
                }
            }
            SettingsRow(
                "정보 밀도",
                subtitle: "설정 목록의 항목 간 여백과 폰트 크기를 조절합니다."
            ) {
                Picker("", selection: $density) {
                    ForEach(AppearanceDensity.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
        }        .companionHighlight("settings.appearanceMode")

    }

    private var selectedTheme: Constants.PopoverTheme {
        Constants.PopoverTheme.normalized(rawValue: popoverTheme)
    }

    private var accentOptions: [AppearanceAccentOption] {
        AppearanceAccentPalette.options(for: selectedTheme)
    }

    private var selectedAccentID: String {
        get {
            let rawValue: String
            switch selectedTheme {
            case .warmLantern: rawValue = warmLanternAccent
            case .wineLantern: rawValue = wineLanternAccent
            case .gamePixel: rawValue = gamePixelAccent
            }
            return AppearanceAccentPalette.normalizedID(rawValue, for: selectedTheme)
        }
        nonmutating set {
            switch selectedTheme {
            case .warmLantern: warmLanternAccent = newValue
            case .wineLantern: wineLanternAccent = newValue
            case .gamePixel: gamePixelAccent = newValue
            }
        }
    }

    private func normalizeAccentSelections() {
        warmLanternAccent = AppearanceAccentPalette.normalizedID(
            warmLanternAccent,
            for: .warmLantern
        )
        wineLanternAccent = AppearanceAccentPalette.normalizedID(
            wineLanternAccent,
            for: .wineLantern
        )
        gamePixelAccent = AppearanceAccentPalette.normalizedID(
            gamePixelAccent,
            for: .gamePixel
        )
    }

    // MARK: - 테마 카드 (팝오버 UI 스타일)

    private var themeCard: some View {
        SettingsGroupCard("테마") {
            SettingsRow(
                "팝오버 테마",
                subtitle: "팝오버와 관련 상세창의 UI 스타일을 선택합니다."
            ) {
                popoverThemeMenu
            }
        }        .companionHighlight("settings.theme")

    }

    private var popoverThemeMenu: some View {
        Menu {
            ForEach(Constants.PopoverTheme.allCases) { theme in
                Button {
                    popoverTheme = theme.rawValue
                } label: {
                    Label(theme.label, systemImage: popoverTheme == theme.rawValue ? "checkmark" : "")
                }
            }

            Button {} label: {
                HStack {
                    Text("편안한 풀")
                    Text("준비 중")
                }
            }
            .disabled(true)
        } label: {
            let selectedTheme = Constants.PopoverTheme.normalized(rawValue: popoverTheme)
            HStack(spacing: 8) {
                Text(selectedTheme.symbol)
                    .font(.system(size: 14))
                Text(selectedTheme.label)
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
            appIconSelector
        }        .companionHighlight("settings.appIcon")

    }

    private var selectedAppIcon: Constants.AppIconStyle {
        Constants.AppIconStyle.normalized(rawValue: appIconRaw)
    }

    private var appIconSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("앱 아이콘")
                    .font(.callout)
                Text("Dock 및 앱 전환기에 표시할 아이콘을 선택합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                spacing: 12
            ) {
                ForEach(Constants.AppIconStyle.allCases) { style in
                    appIconCard(style)
                }
            }
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

    private func appIconCard(_ style: Constants.AppIconStyle) -> some View {
        let isSelected = selectedAppIcon == style

        return Button {
            appIconRaw = style.rawValue
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text(style.label)
                        .font(.callout.bold())
                        .lineLimit(1)

                    if style == .horong {
                        Text("기본")
                            .font(.caption2.bold())
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }

                    Spacer(minLength: 4)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(
                            isSelected
                                ? Color.accentColor
                                : Color.secondary.opacity(0.45)
                        )
                }

                appIconPreview(style)
                    .frame(maxWidth: .infinity)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.08)
                            : Color.primary.opacity(0.035)
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected
                            ? Color.accentColor.opacity(0.75)
                            : Color.primary.opacity(0.1),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(style.label) 앱 아이콘 선택")
        .accessibilityValue(isSelected ? "선택됨" : "선택 안 됨")
    }

    @ViewBuilder
    private func appIconPreview(_ style: Constants.AppIconStyle) -> some View {
        if let image = AppIconManager.image(for: style) {
            Image(nsImage: image)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 104, height: 104)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 42))
                .foregroundStyle(.tertiary)
                .frame(width: 104, height: 104)
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
