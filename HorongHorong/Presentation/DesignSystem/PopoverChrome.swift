import SwiftUI

/// 팝오버·창 공통의 색과 간격 토큰.
///
/// 앱 전역 **28개 파일**이 쓴다. 원래 `Features/MenuBar/MenuBarPopover.swift` 안에 있었는데,
/// 공유물이 한 기능의 소유물처럼 보여 어느 기능을 옮기든 여기서 걸렸다.
@MainActor
enum PopoverChrome {
    static var theme: Constants.PopoverTheme {
        AppearanceAccentStore.shared.theme
    }

    static var isGamePixel: Bool {
        theme == .gamePixel
    }

    static var isWineLantern: Bool {
        theme == .wineLantern
    }

    static var accentOption: AppearanceAccentOption {
        AppearanceAccentStore.shared.option
    }

    static var panelRadius: CGFloat {
        isGamePixel ? 0 : 22
    }

    static var cardRadius: CGFloat {
        isGamePixel ? 0 : 14
    }

    static var controlRadius: CGFloat {
        isGamePixel ? 0 : 999
    }

    static var borderWidth: CGFloat {
        isGamePixel ? 2 : 1
    }

    static var pixelShadow: Color {
        Color(red: 0.114, green: 0.098, blue: 0.200) // #1d1933
    }

    static var ink: Color {
        switch theme {
        case .gamePixel:
            return Color(red: 0.114, green: 0.098, blue: 0.200) // #1d1933
        case .wineLantern:
            return Color(red: 0.945, green: 0.918, blue: 0.902) // #f1eae6
        case .warmLantern:
            return Color(red: 0.23, green: 0.16, blue: 0.10)
        }
    }

    static var inkSecondary: Color {
        switch theme {
        case .gamePixel:
            return Color(red: 0.357, green: 0.310, blue: 0.529) // #5b4f87
        case .wineLantern:
            return Color(red: 0.714, green: 0.667, blue: 0.639) // #b6aaa3
        case .warmLantern:
            return Color(red: 0.48, green: 0.36, blue: 0.27)
        }
    }

    static var inkTertiary: Color {
        switch theme {
        case .gamePixel:
            return Color(red: 0.541, green: 0.494, blue: 0.722) // #8a7eb8
        case .wineLantern:
            return Color(red: 0.494, green: 0.447, blue: 0.412) // #7e7269
        case .warmLantern:
            return Color(red: 0.64, green: 0.52, blue: 0.39)
        }
    }

    static var surface: Color {
        switch theme {
        case .gamePixel:
            return Color(red: 0.957, green: 0.933, blue: 0.976) // #f4eef9
        case .wineLantern:
            return Color(red: 0.102, green: 0.082, blue: 0.094) // #1a1518
        case .warmLantern:
            return Color(red: 1.00, green: 0.965, blue: 0.91)
        }
    }

    static var surfaceAlt: Color {
        switch theme {
        case .gamePixel:
            return Color(red: 0.906, green: 0.871, blue: 0.980) // #e7defa
        case .wineLantern:
            return Color(red: 0.133, green: 0.106, blue: 0.122) // #221b1f
        case .warmLantern:
            return Color(red: 0.996, green: 0.94, blue: 0.86)
        }
    }

    static var card: Color {
        switch theme {
        case .gamePixel:
            return Color.white
        case .wineLantern:
            return Color(red: 0.141, green: 0.110, blue: 0.129) // #241c21
        case .warmLantern:
            return Color.white.opacity(0.78)
        }
    }

    static var border: Color {
        switch theme {
        case .gamePixel:
            return pixelShadow
        case .wineLantern:
            return Color.white.opacity(0.09)
        case .warmLantern:
            return Color(red: 0.71, green: 0.47, blue: 0.24).opacity(0.18)
        }
    }

    static var divider: Color {
        switch theme {
        case .gamePixel:
            return pixelShadow
        case .wineLantern:
            return Color.white.opacity(0.07)
        case .warmLantern:
            return Color(red: 0.71, green: 0.47, blue: 0.24).opacity(0.16)
        }
    }

    static var accent: Color {
        accentOption.popoverColor
    }

    static var accentSoft: Color {
        accentOption.softColor
    }

    static var accentInk: Color {
        Color.white
    }

    static var selectionFill: Color {
        isGamePixel ? pixelShadow : accent
    }

    static var selectionInk: Color {
        isGamePixel ? Color.white : accentInk
    }

    static var scanline: Color {
        Color(red: 0.114, green: 0.098, blue: 0.200).opacity(0.055)
    }

    static var glow: Color {
        accent.opacity(isWineLantern ? 0.22 : 0.10)
    }

    static var primaryButtonFill: AnyShapeStyle {
        accentOption.buttonFill
    }

    static var focusOnImageName: String {
        switch theme {
        case .gamePixel:
            return "FocusOnTransparent2"
        case .wineLantern:
            return "FocusOnTransparent3"
        case .warmLantern:
            return "FocusOnTransparent"
        }
    }

    static var focusOffImageName: String {
        switch theme {
        case .gamePixel:
            return "FocusOffTransparent2"
        case .wineLantern:
            return "FocusOffTransparent3"
        case .warmLantern:
            return "FocusOffTransparent"
        }
    }

    static func radius(_ defaultRadius: CGFloat) -> CGFloat {
        isGamePixel ? 0 : defaultRadius
    }

    static func displayFont(size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: isGamePixel ? .monospaced : .rounded)
    }
}
