import SwiftUI
import AppKit

/// 팝오버 카드 배경과 스크롤바 손질. `.popoverCard()` · `.popoverScrollbar()` 로 쓴다.
///
/// `PopoverScrollViewConfigurator` 는 `.popoverScrollbar()` 의 구현 세부라 `private` 으로 둔다.
/// `PixelScanlineOverlay` 는 `MenuBarPopover` 도 직접 쓰므로 공개한다.
/// 픽셀 테마의 스캔라인. `MenuBarPopover` 와 `.popoverCard()` 가 함께 쓰므로
/// 파일이 갈리면서 `private` 을 풀었다.
struct PixelScanlineOverlay: View {
    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                let rect = CGRect(x: 0, y: y, width: size.width, height: 1)
                context.fill(Path(rect), with: .color(PopoverChrome.scanline))
                y += 3
            }
        }
        .allowsHitTesting(false)
    }
}

struct PopoverCardModifier: ViewModifier {
    var padding: CGFloat = 12
    var radius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                ZStack {
                    if PopoverChrome.isGamePixel {
                        RoundedRectangle(cornerRadius: PopoverChrome.radius(radius), style: .continuous)
                            .fill(PopoverChrome.pixelShadow)
                            .offset(x: 3, y: 3)
                    }

                    RoundedRectangle(cornerRadius: PopoverChrome.radius(radius), style: .continuous)
                        .fill(PopoverChrome.card)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: PopoverChrome.radius(radius), style: .continuous)
                    .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
            )
            .shadow(
                color: PopoverChrome.isGamePixel ? .clear : PopoverChrome.glow,
                radius: PopoverChrome.isGamePixel ? 0 : 6,
                x: 0,
                y: PopoverChrome.isGamePixel ? 0 : 2
            )
    }
}

extension View {
    func popoverCard(padding: CGFloat = 12, radius: CGFloat = 14) -> some View {
        modifier(PopoverCardModifier(padding: padding, radius: radius))
    }

    func popoverScrollbar() -> some View {
        background(PopoverScrollViewConfigurator())
    }
}

private struct PopoverScrollViewConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configureScrollView(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureScrollView(from: nsView)
        }
    }

    private func configureScrollView(from view: NSView) {
        var candidate = view.superview
        while let current = candidate {
            if let scrollView = current as? NSScrollView {
                scrollView.hasVerticalScroller = true
                scrollView.hasHorizontalScroller = false
                scrollView.autohidesScrollers = true
                scrollView.scrollerStyle = .overlay
                scrollView.verticalScroller?.controlSize = .mini
                scrollView.verticalScroller?.knobStyle = .default
                return
            }
            candidate = current.superview
        }
    }
}
