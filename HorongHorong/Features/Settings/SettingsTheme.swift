import SwiftUI

enum SettingsTheme {
    static let sidebarWidth: CGFloat = 240
    /// 페이지 콘텐츠 가로폭 상한. 최소 윈도우(920) - 사이드바(240) = detail 영역 ~680 보다 살짝 작게 잡아
    /// 어느 크기에서도 캡이 활성화돼 카드 폭이 변하지 않게 한다.
    static let contentMaxWidth: CGFloat = 680
    static let windowMinSize = CGSize(width: 920, height: 640)
    static let windowDefaultSize = CGSize(width: 980, height: 680)
}

enum AppearanceDensity: String, CaseIterable, Identifiable, Sendable {
    case compact
    case comfortable
    case spacious

    var id: String { rawValue }

    var label: String {
        switch self {
        case .compact: return "촘촘"
        case .comfortable: return "보통"
        case .spacious: return "넉넉"
        }
    }

    static func normalized(rawValue: String) -> AppearanceDensity {
        AppearanceDensity(rawValue: rawValue) ?? .comfortable
    }

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .compact: return .medium
        case .comfortable: return .large
        case .spacious: return .xLarge
        }
    }

    var controlSize: ControlSize {
        switch self {
        case .compact: return .small
        case .comfortable: return .regular
        case .spacious: return .large
        }
    }

    var rowHorizontalSpacing: CGFloat { value(10, 12, 14) }
    var rowTextSpacing: CGFloat { value(1, 2, 4) }
    var rowTrailingSpacing: CGFloat { value(6, 8, 10) }
    var rowHorizontalPadding: CGFloat { value(12, 14, 16) }
    var rowVerticalPadding: CGFloat { value(6, 10, 14) }
    var rowTitleFontSize: CGFloat { value(12, 13, 14) }
    var rowSubtitleFontSize: CGFloat { value(10, 11, 12) }
    var cardHeaderSpacing: CGFloat { value(4, 6, 8) }
    var pageContentSpacing: CGFloat { value(14, 18, 24) }
    var pageVerticalPadding: CGFloat { value(18, 24, 30) }
    var pageTitleFontSize: CGFloat { value(26, 28, 30) }
    var pageHeaderSpacing: CGFloat { value(3, 4, 5) }
    var pageHeaderBottomPadding: CGFloat { value(4, 6, 8) }

    func popoverMetric(_ metric: CGFloat) -> CGFloat {
        metric * value(0.94, 1, 1.06)
    }

    func informationMetric(_ metric: CGFloat) -> CGFloat {
        metric * value(0.88, 1, 1.12)
    }

    private func value(
        _ compact: CGFloat,
        _ comfortable: CGFloat,
        _ spacious: CGFloat
    ) -> CGFloat {
        switch self {
        case .compact: return compact
        case .comfortable: return comfortable
        case .spacious: return spacious
        }
    }
}

private struct AppearanceDensityEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppearanceDensity.comfortable
}

extension EnvironmentValues {
    var appearanceDensity: AppearanceDensity {
        get { self[AppearanceDensityEnvironmentKey.self] }
        set { self[AppearanceDensityEnvironmentKey.self] = newValue }
    }
}

struct AppearanceAccentOption: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let popoverRGB: UInt32
    let settingsLightRGB: UInt32
    let settingsDarkRGB: UInt32
    let softRGB: UInt32
    let buttonTopRGB: UInt32?
    let buttonBottomRGB: UInt32?

    var popoverColor: Color {
        AppearanceAccentPalette.color(rgb: popoverRGB)
    }

    var softColor: Color {
        AppearanceAccentPalette.color(rgb: softRGB)
    }

    var accentInkRGB: UInt32 {
        let white: UInt32 = 0xFFFFFF
        let dark: UInt32 = 0x1D1933
        let whiteContrast = AppearanceAccentPalette.contrastRatio(popoverRGB, white)
        let darkContrast = AppearanceAccentPalette.contrastRatio(popoverRGB, dark)
        return whiteContrast >= darkContrast ? white : dark
    }

    var accentInkColor: Color {
        AppearanceAccentPalette.color(rgb: accentInkRGB)
    }

    var buttonFill: AnyShapeStyle {
        if let buttonTopRGB, let buttonBottomRGB {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        AppearanceAccentPalette.color(rgb: buttonTopRGB),
                        AppearanceAccentPalette.color(rgb: buttonBottomRGB),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }

        return AnyShapeStyle(popoverColor)
    }

    func settingsColor(for colorScheme: ColorScheme) -> Color {
        AppearanceAccentPalette.color(
            rgb: colorScheme == .dark ? settingsDarkRGB : settingsLightRGB
        )
    }
}

enum AppearanceAccentPalette {
    static let warmLantern: [AppearanceAccentOption] = [
        option(
            "lantern", "호롱불", 0xF0782E, 0xB45309, 0xFB923C, 0xFFDBB3,
            buttonTop: 0xFF993D, buttonBottom: 0xF5661A
        ),
        option(
            "bamboo", "대나무", 0x3F7D58, 0x2F6F4E, 0x6FBF8A, 0xDCEADF,
            buttonTop: 0x467B58, buttonBottom: 0x34704C
        ),
        option(
            "celadon", "청자", 0x377773, 0x2E6F6B, 0x70B9B2, 0xD8E9E6,
            buttonTop: 0x437975, buttonBottom: 0x2F6966
        ),
        option(
            "mulberry", "오디", 0x865179, 0x754468, 0xC77AAF, 0xE8DCE4,
            buttonTop: 0x925A84, buttonBottom: 0x754468
        ),
    ]

    static let wineLantern: [AppearanceAccentOption] = [
        option("wine", "와인", 0xA23A52, 0x9F1239, 0xE05A78, 0x3A2129),
        option("rose", "로즈", 0xB24F72, 0x9D174D, 0xE879A0, 0x3D222F),
        option("brass", "황동", 0x9A693D, 0x854D0E, 0xD89A5B, 0x38291F),
        option("sage", "세이지", 0x567563, 0x3F6B57, 0x83B39A, 0x223029),
    ]

    static let gamePixel: [AppearanceAccentOption] = [
        option("magic", "마법", 0x7A52D6, 0x6D28D9, 0xA78BFA, 0xD8C6F5),
        option("mana", "마나", 0x2F6FC1, 0x1D4ED8, 0x60A5FA, 0xC8D9F2),
        option("slime", "슬라임", 0x277A4E, 0x166534, 0x4ADE80, 0xC9E6D6),
        option("heart", "하트", 0xB84078, 0x9D174D, 0xF472B6, 0xF0C8DC),
    ]

    static func options(for theme: Constants.PopoverTheme) -> [AppearanceAccentOption] {
        switch theme {
        case .warmLantern: return warmLantern
        case .wineLantern: return wineLantern
        case .gamePixel: return gamePixel
        }
    }

    static func defaultID(for theme: Constants.PopoverTheme) -> String {
        options(for: theme)[0].id
    }

    static func normalizedID(_ rawValue: String, for theme: Constants.PopoverTheme) -> String {
        options(for: theme).contains { $0.id == rawValue } ? rawValue : defaultID(for: theme)
    }

    static func option(for theme: Constants.PopoverTheme, id: String) -> AppearanceAccentOption {
        let normalizedID = normalizedID(id, for: theme)
        return options(for: theme).first { $0.id == normalizedID }!
    }

    static func storageKey(for theme: Constants.PopoverTheme) -> String {
        switch theme {
        case .warmLantern: return Constants.AppStorageKey.warmLanternAccent
        case .wineLantern: return Constants.AppStorageKey.wineLanternAccent
        case .gamePixel: return Constants.AppStorageKey.gamePixelAccent
        }
    }

    static func selectedOption(
        for theme: Constants.PopoverTheme,
        defaults: UserDefaults = .standard
    ) -> AppearanceAccentOption {
        let storedID = defaults.string(forKey: storageKey(for: theme)) ?? defaultID(for: theme)
        return option(for: theme, id: storedID)
    }

    static func color(rgb: UInt32) -> Color {
        Color(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

    static func contrastRatio(_ firstRGB: UInt32, _ secondRGB: UInt32) -> Double {
        let first = relativeLuminance(firstRGB)
        let second = relativeLuminance(secondRGB)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private static func option(
        _ id: String,
        _ name: String,
        _ popoverRGB: UInt32,
        _ settingsLightRGB: UInt32,
        _ settingsDarkRGB: UInt32,
        _ softRGB: UInt32,
        buttonTop: UInt32? = nil,
        buttonBottom: UInt32? = nil
    ) -> AppearanceAccentOption {
        AppearanceAccentOption(
            id: id,
            name: name,
            popoverRGB: popoverRGB,
            settingsLightRGB: settingsLightRGB,
            settingsDarkRGB: settingsDarkRGB,
            softRGB: softRGB,
            buttonTopRGB: buttonTop,
            buttonBottomRGB: buttonBottom
        )
    }

    private static func relativeLuminance(_ rgb: UInt32) -> Double {
        let red = linearized(Double((rgb >> 16) & 0xFF) / 255)
        let green = linearized(Double((rgb >> 8) & 0xFF) / 255)
        let blue = linearized(Double(rgb & 0xFF) / 255)
        return red * 0.2126 + green * 0.7152 + blue * 0.0722
    }

    private static func linearized(_ component: Double) -> Double {
        component <= 0.04045
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }
}

@MainActor
@Observable
final class AppearanceAccentStore {
    static let shared = AppearanceAccentStore()

    private(set) var theme: Constants.PopoverTheme
    private(set) var option: AppearanceAccentOption
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?

    init(
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        self.defaults = defaults
        let theme = Self.currentTheme(defaults: defaults)
        self.theme = theme
        self.option = AppearanceAccentPalette.selectedOption(for: theme, defaults: defaults)

        defaultsObserver = notificationCenter.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.synchronize()
            }
        }
    }

    func synchronize() {
        let theme = Self.currentTheme(defaults: defaults)
        let option = AppearanceAccentPalette.selectedOption(for: theme, defaults: defaults)
        if self.theme != theme {
            self.theme = theme
        }
        if self.option != option {
            self.option = option
        }
    }

    private static func currentTheme(defaults: UserDefaults) -> Constants.PopoverTheme {
        Constants.PopoverTheme.normalized(
            rawValue: defaults.string(
                forKey: Constants.AppStorageKey.popoverTheme
            ) ?? Constants.defaultPopoverTheme
        )
    }
}

enum AppearanceAccentTintContext {
    case adaptive
    case popover
}

private struct AppearanceAccentOptionEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppearanceAccentPalette.warmLantern[0]
}

extension EnvironmentValues {
    var appearanceAccentOption: AppearanceAccentOption {
        get { self[AppearanceAccentOptionEnvironmentKey.self] }
        set { self[AppearanceAccentOptionEnvironmentKey.self] = newValue }
    }
}

private struct AppearanceAccentTintModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(Constants.AppStorageKey.popoverTheme)
    private var popoverTheme = Constants.defaultPopoverTheme
    @AppStorage(Constants.AppStorageKey.warmLanternAccent)
    private var warmLanternAccent = AppearanceAccentPalette.defaultID(for: .warmLantern)
    @AppStorage(Constants.AppStorageKey.wineLanternAccent)
    private var wineLanternAccent = AppearanceAccentPalette.defaultID(for: .wineLantern)
    @AppStorage(Constants.AppStorageKey.gamePixelAccent)
    private var gamePixelAccent = AppearanceAccentPalette.defaultID(for: .gamePixel)

    let context: AppearanceAccentTintContext

    private var option: AppearanceAccentOption {
        let theme = Constants.PopoverTheme.normalized(rawValue: popoverTheme)
        let selectedID: String
        switch theme {
        case .warmLantern: selectedID = warmLanternAccent
        case .wineLantern: selectedID = wineLanternAccent
        case .gamePixel: selectedID = gamePixelAccent
        }
        return AppearanceAccentPalette.option(for: theme, id: selectedID)
    }

    func body(content: Content) -> some View {
        let tint = context == .popover
            ? option.popoverColor
            : option.settingsColor(for: colorScheme)
        content
            .environment(\.appearanceAccentOption, option)
            .tint(tint)
            .onAppear {
                AppearanceAccentStore.shared.synchronize()
            }
            .onChange(of: option) { _, _ in
                AppearanceAccentStore.shared.synchronize()
            }
    }
}

extension View {
    func appearanceAccentTint(_ context: AppearanceAccentTintContext) -> some View {
        modifier(AppearanceAccentTintModifier(context: context))
    }
}

extension Color {
    static let horongCard = Color(nsColor: .windowBackgroundColor).opacity(0.6)
    static let horongCardBorder = Color.primary.opacity(0.08)
    static let horongMutedText = Color.secondary
}

/// 백엔드 로직이 아직 없는 컨트롤 옆에 다는 작은 라벨.
struct ComingSoonLabel: View {
    var body: some View {
        Text("준비 중")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.15))
            )
    }
}
