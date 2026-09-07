import SwiftUI

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
                    .font(.system(size: 16, design: .serif))
                    .foregroundStyle(PopoverChrome.ink)
                    .scrollContentBackground(.hidden)
                    .padding(.leading, 40)
                    .padding(.trailing, 16)
                    .padding(.vertical, 14)
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
                var y: CGFloat = 30
                while y < size.height {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(path, with: .color(lineColor), lineWidth: 0.6)
                    y += 30
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
