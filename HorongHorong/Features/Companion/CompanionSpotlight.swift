import AppKit

/// 온보딩 동안 화면을 어둡게 덮어, 설명 중인 곳만 눈에 들어오게 한다.
///
/// 팝오버와 컴패니언 창은 이 창보다 위에 있어 어두워지지 않는다.
/// 창 레벨만으로 "구멍"을 만드는 셈이라 별도의 마스크 계산이 필요 없다.
/// 클릭은 그대로 통과시켜 설명을 따라 눌러볼 수 있다.
@MainActor
final class CompanionSpotlight {
    static let shared = CompanionSpotlight()

    private var windows: [NSWindow] = []
    private var screenObserver: NSObjectProtocol?

    private init() {}

    var isVisible: Bool { !windows.isEmpty }

    func show() {
        guard windows.isEmpty else { return }
        build()

        // 디스플레이 구성이 바뀌면 덮개도 다시 만든다.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isVisible else { return }
                self.teardown()
                self.build()
            }
        }
    }

    func hide() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
        teardown()
    }

    private func build() {
        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = NSColor.black.withAlphaComponent(Self.dimAlpha)
            window.hasShadow = false
            // 클릭을 가로채지 않아 설명대로 눌러볼 수 있다.
            window.ignoresMouseEvents = true
            // 레벨 순서: 딤(-2) < 설명 중인 창(-1) < 컴패니언(.floating) < 팝오버.
            // 캐릭터가 항상 맨 위에 남아야 말풍선을 놓치지 않는다.
            window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 2)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            window.setFrame(screen.frame, display: true)
            window.alphaValue = 0
            window.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                window.animator().alphaValue = 1
            }
            windows.append(window)
        }
    }

    private func teardown() {
        let closing = windows
        windows.removeAll()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            for window in closing {
                window.animator().alphaValue = 0
            }
        }, completionHandler: {
            MainActor.assumeIsolated {
                for window in closing {
                    window.orderOut(nil)
                }
            }
        })
    }

    /// 너무 어두우면 뒤 화면 맥락이 사라지고, 너무 옅으면 강조가 안 된다.
    private static let dimAlpha: CGFloat = 0.45
}
