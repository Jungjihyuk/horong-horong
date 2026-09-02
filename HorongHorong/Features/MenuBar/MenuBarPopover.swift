import SwiftUI
import AppKit
import Foundation

enum PopoverTab: String, CaseIterable, Identifiable {
    case timer = "타이머"
    case memo = "기록"
    case stats = "통계"
    case news = "뉴스"
    case agent = "Agent"
    case achievement = "성취"

    var id: String { rawValue }

    /// 온보딩 강조 대상 식별자에 쓰는 영문 키. rawValue 는 한글이라 따로 둔다.
    var highlightKey: String {
        switch self {
        case .timer: return "timer"
        case .memo: return "memo"
        case .stats: return "stats"
        case .news: return "news"
        case .agent: return "agent"
        case .achievement: return "achievement"
        }
    }

    var icon: String {
        switch self {
        case .timer: return "timer"
        case .memo: return "note.text"
        case .achievement: return "target"
        case .stats: return "chart.bar"
        case .news: return "newspaper"
        case .agent: return "bolt.horizontal.circle"
        }
    }
}

struct MenuBarPopover: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: PopoverTab
    @State private var showTelemetryConsentPrompt = false
    @State private var showFocusEndPrompt = false
    @AppStorage(Constants.AppStorageKey.popoverTheme)
    private var popoverTheme: String = Constants.defaultPopoverTheme
    private let referenceDate: Date
    var timerManager: TimerManager

    init(timerManager: TimerManager, initialTab: PopoverTab = .timer, referenceDate: Date = Date()) {
        self.timerManager = timerManager
        _selectedTab = State(initialValue: initialTab)
        self.referenceDate = referenceDate
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                tabBar
                tabContent
                    .id(selectedTab)
                    .companionDimUnlessTargeting(["timer.", "memo.", "stats.", "achievement.", "news.", "agent."])
                    .onReceive(
                        NotificationCenter.default.publisher(for: .companionOnboardingSelectTab)
                    ) { notification in
                        // 온보딩이 단계에 맞는 탭을 보여달라고 요청한다.
                        if let tab = notification.object as? PopoverTab {
                            selectedTab = tab
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                bottomBar
            }

            if showFocusEndPrompt {
                focusEndPrompt
            }
            if showTelemetryConsentPrompt {
                telemetryConsentPrompt
            }
        }
        .frame(width: Constants.popoverWidth, height: Constants.popoverMaxHeight, alignment: .top)
        .appearanceAccentTint(.popover)
        .background {
            RoundedRectangle(cornerRadius: PopoverChrome.panelRadius, style: .continuous)
                .fill(PopoverChrome.surface)
            if PopoverChrome.isGamePixel {
                PixelScanlineOverlay()
                    .clipShape(RoundedRectangle(cornerRadius: PopoverChrome.panelRadius, style: .continuous))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: PopoverChrome.panelRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PopoverChrome.panelRadius, style: .continuous)
                .strokeBorder(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
        )
        .background {
            if PopoverChrome.isGamePixel {
                RoundedRectangle(cornerRadius: PopoverChrome.panelRadius, style: .continuous)
                    .fill(PopoverChrome.pixelShadow)
                    .offset(x: 5, y: 5)
            }
        }
        .shadow(
            color: PopoverChrome.isGamePixel ? .clear : .black.opacity(0.28),
            radius: PopoverChrome.isGamePixel ? 0 : 30,
            x: 0,
            y: PopoverChrome.isGamePixel ? 0 : 18
        )
        .id(popoverTheme)
        .configureHostWindow(configurePopoverHostWindow)
        .onAppear {
            showTelemetryConsentPrompt = TelemetryConsentStore.shouldPromptForConsent
        }
        .onChange(of: appState.timerState) { _, state in
            if state != .focusing && state != .paused {
                showFocusEndPrompt = false
            }
        }
    }

    private func configurePopoverHostWindow(_ window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear

        for view in [window.contentView, window.contentView?.superview].compactMap({ $0 }) {
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.clear.cgColor
            view.layer?.cornerRadius = PopoverChrome.panelRadius
            view.layer?.cornerCurve = .continuous
            view.layer?.masksToBounds = true
        }
    }

    private var focusEndPrompt: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "stop.circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(PopoverChrome.accent)
                    Text("집중을 종료할까요?")
                        .font(.system(size: 14.5, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.ink)
                }

                Text("\(formattedFocusElapsedTime) 동안의 집중 기록을 저장할 수 있어요.")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)

                VStack(spacing: 8) {
                    Button {
                        showFocusEndPrompt = false
                        timerManager.endFocusAndRecord()
                    } label: {
                        Text("기록 후 종료")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LanternPrimaryButtonStyle())

                    Button {
                        showFocusEndPrompt = false
                        timerManager.discardCurrentFocus()
                    } label: {
                        Text("기록하지 않고 종료")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.large)

                    Button {
                        showFocusEndPrompt = false
                    } label: {
                        Text("계속하기")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LanternSecondaryButtonStyle())
                }
            }
            .padding(16)
            .frame(width: Constants.popoverWidth - 56)
            .background(
                PopoverChrome.card,
                in: RoundedRectangle(
                    cornerRadius: PopoverChrome.radius(16),
                    style: .continuous
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: PopoverChrome.radius(16),
                    style: .continuous
                )
                .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
            )
            .shadow(
                color: PopoverChrome.isGamePixel ? .clear : .black.opacity(0.18),
                radius: PopoverChrome.isGamePixel ? 0 : 20,
                x: 0,
                y: PopoverChrome.isGamePixel ? 0 : 12
            )
        }
        .zIndex(10)
    }

    private var formattedFocusElapsedTime: String {
        let seconds = timerManager.currentFocusElapsedSeconds
        let minutes = seconds / 60
        let remainder = seconds % 60
        if minutes == 0 {
            return "\(remainder)초"
        }
        if remainder == 0 {
            return "\(minutes)분"
        }
        return "\(minutes)분 \(remainder)초"
    }

    private var telemetryConsentPrompt: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(PopoverChrome.accent)
                    Text("익명 개선 데이터를 보내시겠어요?")
                        .font(.system(size: 14.5, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.ink)
                }

                Text("현재 보내는 내용은 익명 설치 ID, 앱/OS 버전, 이 설정의 동의 상태입니다. 앱 이름, 번들 ID, 작업 기록, 포모도로 회고 내용은 보내지 않습니다. 언제든 설정 > 데이터에서 바꿀 수 있어요.")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button {
                        TelemetryConsentStore.declineInitialPrompt()
                        showTelemetryConsentPrompt = false
                    } label: {
                        Text("지금은 안 함")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        TelemetryConsentStore.setEnabled(true)
                        showTelemetryConsentPrompt = false
                        Task {
                            await TelemetryClient.shared.recordConsent(.enabled)
                        }
                    } label: {
                        Text("허용")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(16)
            .frame(width: Constants.popoverWidth - 56)
            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(16), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PopoverChrome.radius(16), style: .continuous)
                    .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
            )
            .background {
                if PopoverChrome.isGamePixel {
                    RoundedRectangle(cornerRadius: PopoverChrome.radius(16), style: .continuous)
                        .fill(PopoverChrome.pixelShadow)
                        .offset(x: 3, y: 3)
                }
            }
            .shadow(color: PopoverChrome.isGamePixel ? .clear : .black.opacity(0.18), radius: PopoverChrome.isGamePixel ? 0 : 20, x: 0, y: PopoverChrome.isGamePixel ? 0 : 12)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(PopoverTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: .medium))
                        Text(tab.rawValue)
                            .font(.system(size: 11.5, weight: selectedTab == tab ? .semibold : .regular))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(selectedTab == tab ? PopoverChrome.selectionInk : PopoverChrome.inkSecondary)
                    .background(selectedTab == tab ? PopoverChrome.selectionFill : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .companionHighlight("tab.\(tab.highlightKey)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background {
            PopoverChrome.surfaceAlt
            if PopoverChrome.isGamePixel {
                PixelScanlineOverlay()
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PopoverChrome.divider)
                .frame(height: PopoverChrome.borderWidth)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .timer:
            TimerView(
                timerManager: timerManager,
                requestFocusEnd: {
                    showFocusEndPrompt = true
                }
            ) {
                dismiss()
            }
        case .memo:
            MemoListView()
        case .achievement:
            AchievementSummaryView()
        case .stats:
            StatsSummaryView(referenceDate: referenceDate)
        case .news:
            NewsView()
        case .agent:
            AgentExperimentView()
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button {
                NSApp.activate()
                openSettings()
                // openSettings 직후엔 윈도우가 아직 background 일 수 있어 다음 런루프에서 전면화.
                DispatchQueue.main.async {
                    for window in NSApp.windows {
                        let id = window.identifier?.rawValue ?? ""
                        let title = window.title
                        if id.contains("com_apple_SwiftUI_Settings") || title.localizedCaseInsensitiveContains("설정") {
                            AppActivation.front(window)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                    Text("설정")
                        .font(.system(size: 13))
                }
                .foregroundStyle(PopoverChrome.inkSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous)
                        .fill(.primary.opacity(0.00001))
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)

            Rectangle()
                .fill(PopoverChrome.divider)
                .frame(width: 1, height: 20)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 13))
                    Text("종료")
                        .font(.system(size: 13))
                }
                .foregroundStyle(PopoverChrome.inkSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous)
                        .fill(.primary.opacity(0.00001))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background {
            PopoverChrome.surfaceAlt
            if PopoverChrome.isGamePixel {
                PixelScanlineOverlay()
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(PopoverChrome.divider)
                .frame(height: PopoverChrome.borderWidth)
        }
    }
}

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

private struct PixelScanlineOverlay: View {
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
