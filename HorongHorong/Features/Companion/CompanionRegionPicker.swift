import AppKit

/// 화면을 덮고 마우스 드래그로 컴패니언 활동 영역을 지정하게 하는 오버레이.
/// 화면마다 창을 하나씩 띄우므로 드래그는 시작한 디스플레이 안에서만 이뤄진다.
@MainActor
final class CompanionRegionPicker {
    static let shared = CompanionRegionPicker()

    private var panels: [NSPanel] = []
    private var escapeMonitor: Any?
    private var completion: ((CGRect?) -> Void)?

    private init() {}

    var isPresenting: Bool { !panels.isEmpty }

    /// 사용자가 영역을 그리면 전역 화면 좌표의 사각형을, 취소하면 nil 을 돌려준다.
    func begin(completion: @escaping (CGRect?) -> Void) {
        guard !isPresenting else { return }
        self.completion = completion

        for screen in NSScreen.screens {
            // esc 를 받으려면 키 윈도우가 될 수 있어야 하므로 nonactivating 을 쓰지 않는다.
            let panel = RegionPickerPanel(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = false
            panel.animationBehavior = .none
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

            let view = RegionSelectionView(screenFrame: screen.frame) { [weak self] rect in
                self?.finish(with: rect)
            }
            panel.contentView = view
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            panels.append(panel)
        }

        NSApp.activate(ignoringOtherApps: true)
        panels.first?.makeKeyAndOrderFront(nil)
        NSCursor.crosshair.push()

        // 마우스가 어느 화면 위에 있든 esc 로 취소할 수 있게 앱 전체 keyDown 을 가로챈다.
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }  // esc
            MainActor.assumeIsolated {
                self?.finish(with: nil)
            }
            return nil
        }
    }

    private func finish(with rect: CGRect?) {
        guard isPresenting else { return }

        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
        escapeMonitor = nil

        for panel in panels {
            panel.orderOut(nil)
        }
        panels.removeAll()
        NSCursor.pop()

        let completion = self.completion
        self.completion = nil
        completion?(rect)
    }
}

private final class RegionPickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// 반투명 배경 위에 드래그 중인 선택 영역을 뚫어 보여주는 뷰.
private final class RegionSelectionView: NSView {
    private let screenFrame: CGRect
    private let onFinish: (CGRect?) -> Void

    /// 설정 화면 강조 색(#D97706) 과 톤을 맞춘 선택 테두리 색.
    private static let selectionStroke = NSColor(
        calibratedRed: 0.85,
        green: 0.46,
        blue: 0.04,
        alpha: 1
    )

    private var anchor: CGPoint?
    private var currentRect: CGRect?

    init(screenFrame: CGRect, onFinish: @escaping (CGRect?) -> Void) {
        self.screenFrame = screenFrame
        self.onFinish = onFinish
        super.init(frame: CGRect(origin: .zero, size: screenFrame.size))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        anchor = convert(event.locationInWindow, from: nil)
        currentRect = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchor else { return }
        let point = convert(event.locationInWindow, from: nil)
        currentRect = CGRect(
            x: min(anchor.x, point.x),
            y: min(anchor.y, point.y),
            width: abs(point.x - anchor.x),
            height: abs(point.y - anchor.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            anchor = nil
            currentRect = nil
        }
        guard let rect = currentRect,
              rect.width >= Constants.companionMinimumRegionSize.width,
              rect.height >= Constants.companionMinimumRegionSize.height else {
            // 너무 작게 그리거나 그냥 클릭하면 취소로 본다.
            onFinish(nil)
            return
        }

        onFinish(
            CGRect(
                x: screenFrame.minX + rect.minX,
                y: screenFrame.minY + rect.minY,
                width: rect.width,
                height: rect.height
            )
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()

        guard let rect = currentRect else {
            drawInstruction()
            return
        }

        // 선택 영역만 원래 화면이 보이도록 뚫는다.
        NSColor.clear.setFill()
        rect.fill(using: .copy)

        Self.selectionStroke.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 2
        path.stroke()

        drawSizeLabel(for: rect)
    }

    private func drawInstruction() {
        let text = "드래그해서 루미롱이 돌아다닐 영역을 지정하세요   ·   esc 취소"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    private func drawSizeLabel(for rect: CGRect) {
        let text = "\(Int(rect.width))×\(Int(rect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        let origin = CGPoint(x: rect.minX, y: rect.maxY + 6)
        let backdrop = CGRect(
            x: origin.x - 5,
            y: origin.y - 3,
            width: size.width + 10,
            height: size.height + 6
        )
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: backdrop, xRadius: 5, yRadius: 5).fill()
        text.draw(at: origin, withAttributes: attributes)
    }
}
