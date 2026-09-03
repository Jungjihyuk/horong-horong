import SwiftUI
import AppKit

/// 호롱 톤의 버튼 스타일. 주(primary)·보조(secondary) 두 가지.
struct LanternPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(PopoverChrome.accentInk)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background {
                ZStack {
                    if PopoverChrome.isGamePixel && !configuration.isPressed {
                        RoundedRectangle(cornerRadius: PopoverChrome.controlRadius, style: .continuous)
                            .fill(PopoverChrome.pixelShadow)
                            .offset(x: 3, y: 3)
                    }

                    RoundedRectangle(cornerRadius: PopoverChrome.controlRadius, style: .continuous)
                        .fill(PopoverChrome.accent)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: PopoverChrome.controlRadius, style: .continuous)
                    .stroke(PopoverChrome.isGamePixel ? PopoverChrome.border : Color.clear, lineWidth: PopoverChrome.borderWidth)
            )
            .shadow(
                color: PopoverChrome.isGamePixel ? .clear : PopoverChrome.accent.opacity(configuration.isPressed ? 0.12 : 0.22),
                radius: PopoverChrome.isGamePixel ? 0 : 10,
                x: 0,
                y: PopoverChrome.isGamePixel ? 0 : 4
            )
            .offset(x: PopoverChrome.isGamePixel && configuration.isPressed ? 2 : 0, y: PopoverChrome.isGamePixel && configuration.isPressed ? 2 : 0)
            .scaleEffect(!PopoverChrome.isGamePixel && configuration.isPressed ? 0.98 : 1)
    }
}

struct LanternSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(PopoverChrome.inkSecondary)
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background {
                ZStack {
                    if PopoverChrome.isGamePixel && !configuration.isPressed {
                        RoundedRectangle(cornerRadius: PopoverChrome.controlRadius, style: .continuous)
                            .fill(PopoverChrome.pixelShadow)
                            .offset(x: 2, y: 2)
                    }

                    RoundedRectangle(cornerRadius: PopoverChrome.controlRadius, style: .continuous)
                        .fill(PopoverChrome.card.opacity(configuration.isPressed ? 0.72 : 1))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: PopoverChrome.controlRadius, style: .continuous)
                    .stroke(PopoverChrome.isGamePixel ? PopoverChrome.border : PopoverChrome.divider, lineWidth: PopoverChrome.borderWidth)
            )
            .shadow(
                color: .clear,
                radius: 0,
                x: 0,
                y: 0
            )
            .offset(x: PopoverChrome.isGamePixel && configuration.isPressed ? 1.5 : 0, y: PopoverChrome.isGamePixel && configuration.isPressed ? 1.5 : 0)
    }
}
