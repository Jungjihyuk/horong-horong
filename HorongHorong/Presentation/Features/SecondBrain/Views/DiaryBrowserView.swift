import SwiftUI
import AppKit

/// 일기 화면. 글 쓰는 자리가 화면을 차지하고, 달력과 인사이트는 접었다 펴는 우측 패널에 있다.
///
/// **`@Query`·`ModelContext` 를 쓰지 않는다.** 화면은 ViewModel 이 준 값 타입만 본다.
struct DiaryBrowserView: View {
    @State private var viewModel: DiaryViewModel
    @State private var isInsightsPresented = false
    /// 끄는 동안에만 쓰는 값. 손을 뗄 때 한 번만 저장해 UserDefaults 를 매 프레임 건드리지 않는다.
    @State private var draggingPanelWidth: CGFloat?
    @State private var panelWidthAtDragStart: CGFloat?

    @AppStorage(Constants.AppStorageKey.diaryPanelWidth)
    private var storedPanelWidth: Double = Double(Constants.diaryPanelDefaultWidth)
    @AppStorage(Constants.AppStorageKey.diaryPanelOpen)
    private var isPanelOpen = true
    /// 설정에서 정한 수면 축. 설정 창에서 바꾸면 `@AppStorage` 가 여기까지 바로 흐른다.
    private let axisStorage = DiarySleepAxisStorage()

    private let repository: DiaryRepository
    private let calendar = Calendar.current

    init(repository: DiaryRepository) {
        self.repository = repository
        _viewModel = State(initialValue: DiaryViewModel(repository: repository))
    }

    var body: some View {
        GeometryReader { proxy in
            let panelWidth = resolvedPanelWidth(totalWidth: proxy.size.width)
            HStack(spacing: 0) {
                editorPane
                if isPanelOpen {
                    PaneResizeHandle(
                        onDrag: { translation in
                            let base = panelWidthAtDragStart ?? CGFloat(storedPanelWidth)
                            panelWidthAtDragStart = base
                            draggingPanelWidth = base - translation
                        },
                        onDragEnd: {
                            storedPanelWidth = Double(panelWidth)
                            draggingPanelWidth = nil
                            panelWidthAtDragStart = nil
                        }
                    )
                    sidePanel
                        .frame(width: panelWidth)
                } else {
                    panelOpenStrip
                }
            }
        }
        .onAppear {
            viewModel.sleepAxis = axisStorage.axis
            viewModel.reload()
        }
        .onChange(of: axisStorage.axis) { _, axis in viewModel.sleepAxis = axis }
        .onDisappear { viewModel.flush() }
        .sheet(isPresented: $isInsightsPresented) {
            DiaryInsightsView(
                repository: repository,
                referenceDate: viewModel.selectedDay,
                axis: axisStorage.axis
            )
                .frame(minWidth: 760, minHeight: 600)
        }
    }

    /// 창이 좁아졌거나 저장값이 오래됐을 수 있으므로 그릴 때마다 지금 창 크기로 다시 자른다.
    private func resolvedPanelWidth(totalWidth: CGFloat) -> CGFloat {
        PaneWidthPolicy.resolveTrailing(
            proposed: draggingPanelWidth ?? CGFloat(storedPanelWidth),
            totalWidth: totalWidth,
            leadingMinimum: Constants.diaryEditorPaneMinWidth,
            trailingMinimum: Constants.diaryPanelMinWidth,
            trailingMaximum: Constants.diaryPanelMaxWidth
        )
    }

    // MARK: - 패널

    private var sidePanel: some View {
        DiarySidePanel(
            visibleMonth: viewModel.visibleMonth,
            selectedDay: viewModel.selectedDay,
            writtenCount: viewModel.writtenCount,
            snapshot: viewModel.insightPreview,
            axis: axisStorage.axis,
            calendar: calendar,
            moodEmoji: { viewModel.entry(on: $0)?.representativeMood?.emoji },
            moodGroups: { viewModel.entry(on: $0)?.recordedGroups ?? [] },
            onSelectDay: { viewModel.select($0) },
            onShiftMonth: { viewModel.shiftMonth($0) },
            onGoToToday: { viewModel.goToToday() },
            onCollapse: { setPanel(open: false) },
            onOpenInsights: { isInsightsPresented = true }
        )
    }

    /// 패널을 접었을 때 남는 세로 띠. 접고 나서 다시 펴는 길이 없으면 한 번 접은 사람은 갇힌다.
    private var panelOpenStrip: some View {
        Button { setPanel(open: true) } label: {
            Image(systemName: "sidebar.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PopoverChrome.inkSecondary)
                .frame(width: 26)
                .frame(maxHeight: .infinity)
                .background(PopoverChrome.surfaceAlt)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(PopoverChrome.divider)
                        .frame(width: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("달력과 인사이트 열기")
        .accessibilityLabel("달력과 인사이트 열기")
    }

    private func setPanel(open: Bool) {
        withAnimation(.easeOut(duration: 0.2)) { isPanelOpen = open }
    }

    // MARK: - 편집기

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            editorHeader
            DiaryMetaRow(
                day: viewModel.selectedDay,
                entry: viewModel.selected,
                axis: axisStorage.axis,
                calendar: calendar,
                onSelectMood: { viewModel.setMood($0, in: $1) },
                onSelectIntensity: { viewModel.setIntensity($0, in: $1) },
                onSelectCause: { viewModel.setCause($0, in: $1) },
                onCommitSleep: { viewModel.setSleepWindow(start: $0, end: $1) },
                onClearSleep: { viewModel.clearSleep() }
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Divider().overlay(PopoverChrome.divider)

            DiaryNotebookPage {
                TextEditor(text: $viewModel.bodyDraft)
                    .font(.system(size: DiaryNotebookMetrics.fontSize, design: .serif))
                    // 글줄도 괘선과 같은 간격으로 내려가게 한다 — 이게 없으면 폰트 기본 줄높이로
                    // 흘러서 한 줄 적을 때마다 글이 선 위로 조금씩 떠오른다.
                    .lineSpacing(DiaryNotebookMetrics.lineSpacing)
                    .foregroundStyle(PopoverChrome.ink)
                    .scrollContentBackground(.hidden)
                    .padding(.leading, 40)
                    .padding(.trailing, 16)
                    .padding(.vertical, DiaryNotebookMetrics.topInset)
                    .onChange(of: viewModel.bodyDraft) { _, _ in viewModel.draftChanged() }
            }

            HStack {
                Text("\(viewModel.bodyDraft.count)자 · 자동 저장")
                Spacer()
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(PopoverChrome.inkTertiary)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity)
        .background(PopoverChrome.surface)
    }

    private var editorHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(DiaryDateText.day(viewModel.selectedDay))
                    .font(.system(size: 19, weight: .semibold, design: .serif))
                    .foregroundStyle(PopoverChrome.ink)
                if calendar.isDateInToday(viewModel.selectedDay) {
                    Text("오늘")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.accentInk)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(PopoverChrome.accent, in: Capsule())
                }
                Spacer(minLength: 0)
            }
            Text(viewModel.selected == nil ? "오늘의 마음을 한 줄 남겨보세요" : "기록됨")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }
}

/// 괘선과 글줄을 **같은 격자**에 올리기 위한 치수.
///
/// 예전에는 괘선만 30pt 간격으로 그리고 글은 폰트 기본 줄높이(19pt)로 흘렀다. 한 줄 적을 때마다
/// 8pt 씩 어긋나서, 다섯 줄이면 글이 괘선에서 완전히 떠올랐다. 그래서 줄 간격을 상수로 적지 않고
/// **«괘선 간격 − 줄 높이»** 로 되돌려 계산한다 — 둘 중 하나만 고쳐도 다시 어긋나는 일이 없다.
///
/// 줄 높이와 baseline 위치는 실제 조판기(`NSLayoutManager`)에 물어본다. 눈으로 재서 적어 둔 상수는
/// 폰트나 OS 지표가 바뀌면 조용히 틀리기 시작한다. 만드는 비용이 있어 한 번만 계산해 둔다(AGENTS.md R7).
/// `NSFont`·`NSLayoutManager` 는 `Sendable` 이 아니다. 우회 키워드로 덮지 않고
/// 화면과 같은 격리(@MainActor)에 둔다 — 어차피 그리는 쪽에서만 쓰는 값이다(AGENTS.md R5).
@MainActor
enum DiaryNotebookMetrics {
    /// 본문 글자 크기. 에디터와 치수 계산이 반드시 같은 값을 봐야 한다.
    static let fontSize: CGFloat = 16

    /// 괘선 간격. 글이 답답해 보여 예전 30pt 에서 10% 줄였다.
    static let ruleSpacing: CGFloat = 27

    /// 에디터 위·아래 여백. `TextEditor` 안쪽 `NSTextView` 의 `textContainerInset` 은 0 이라
    /// 이 값이 곧 첫 글줄이 시작하는 높이다.
    static let topInset: CGFloat = 14

    /// `TextEditor` 에 넣을 줄 사이 여백.
    static var lineSpacing: CGFloat { max(0, ruleSpacing - layout.lineHeight) }

    /// 첫 괘선의 y. 글자가 선 **위에 앉도록** baseline 보다 아주 살짝 아래에 둔다.
    static var firstRuleY: CGFloat { topInset + layout.baselineOffset + baselineGap }

    /// baseline 과 괘선 사이. 0 이면 선이 글자 밑동에 닿아 지저분해 보인다.
    private static let baselineGap: CGFloat = 1.5

    private static let font: NSFont = {
        let base = NSFont.systemFont(ofSize: fontSize)
        guard let descriptor = base.fontDescriptor.withDesign(.serif),
              let serif = NSFont(descriptor: descriptor, size: fontSize) else { return base }
        return serif
    }()

    /// 실제로 한 글자를 조판해 «줄 상자의 높이» 와 «상자 위에서 baseline 까지» 를 잰다.
    /// `NSLayoutManager.defaultBaselineOffset(for:)` 은 조판 결과와 1pt 어긋나서 쓰지 않는다.
    private static let layout: (lineHeight: CGFloat, baselineOffset: CGFloat) = {
        let storage = NSTextStorage(string: "가", attributes: [.font: font])
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        guard manager.numberOfGlyphs > 0 else { return (19, 14) }
        let fragment = manager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        return (fragment.height, manager.location(forGlyphAt: 0).y)
    }()
}

private struct DiaryNotebookPage<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            PopoverChrome.surface
            Canvas { context, size in
                let lineColor = PopoverChrome.divider.opacity(PopoverChrome.isWineLantern ? 0.38 : 0.65)
                var y = DiaryNotebookMetrics.firstRuleY
                while y < size.height {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(path, with: .color(lineColor), lineWidth: 0.6)
                    y += DiaryNotebookMetrics.ruleSpacing
                }
                var margin = Path()
                margin.move(to: CGPoint(x: 34, y: 0))
                margin.addLine(to: CGPoint(x: 34, y: size.height))
                context.stroke(margin, with: .color(PopoverChrome.accent.opacity(0.25)), lineWidth: 1)
            }
            .allowsHitTesting(false)
            content
        }
    }
}
