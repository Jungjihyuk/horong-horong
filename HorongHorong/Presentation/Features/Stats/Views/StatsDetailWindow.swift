import SwiftUI
import OSLog
import Charts

enum StatsContentMode {
    case period
    case focus
}

struct StatsDetailWindow: View {
    @State private var viewModel: StatsDetailViewModel
    @Environment(\.appearanceDensity) private var appearanceDensity
    @AppStorage(Constants.AppStorageKey.popoverTheme)
    private var popoverTheme: String = Constants.defaultPopoverTheme

    init(viewModel: StatsDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    init(
        repository: StatsDetailRepository,
        todoRepository: TodoRepository,
        reflectionRepository: PomodoroReflectionRepository,
        statsRepository: StatsRecordRepository,
        statsEditorRepository: StatsRecordEditorRepository,
        initialViewMode: StatsViewMode = .daily,
        initialContentMode: StatsContentMode = .period,
        initialSelectedDate: Date? = nil
    ) {
        _viewModel = State(initialValue: StatsDetailViewModel(
            repository: repository,
            todoRepository: todoRepository,
            reflectionRepository: reflectionRepository,
            statsRepository: statsRepository,
            statsEditorRepository: statsEditorRepository,
            initialViewMode: initialViewMode,
            initialContentMode: initialContentMode,
            initialSelectedDate: initialSelectedDate
        ))
    }

    /// **별도 프로퍼티로 뗀 이유**: body 안에 두면 인자가 늘었을 때
    /// 타입 검사기가 시간 안에 끝내지 못한다("unable to type-check in reasonable time").
    private var focusDetail: some View {
        FocusDetailView(
            sessions: viewModel.pomodoroComparisonSessions,
            reflectionRepository: viewModel.reflectionRepository,
            statsRepository: viewModel.statsRepository,
            statsDetailRepository: viewModel.repository,
            todoRepository: viewModel.todoRepository,
            reflections: viewModel.pomodoroReflections,
            taskCompletions: viewModel.pomodoroTaskCompletions,
            viewMode: viewModel.viewMode,
            referenceDate: viewModel.selectedDate,
            onNavigate: { mode, date in
                viewModel.selectedDate = date
                viewModel.viewMode = mode
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if viewModel.contentMode == .period, !viewModel.shouldShowVacationIllustration {
                vacationBanner
            }
            ZStack {
                ScrollView {
                    Group {
                        if viewModel.contentMode == .focus {
                            focusDetail
                        } else {
                            StatsChartView(
                                statsDetailRepository: viewModel.repository,
                                records: viewModel.records,
                                viewMode: viewModel.viewMode,
                                referenceDate: viewModel.selectedDate,
                                dailySegments: viewModel.dailySegments,
                                weekSegments: viewModel.weekSegments,
                                periodSegments: viewModel.periodSegments,
                                pomodoroComparisonSessions: viewModel.pomodoroComparisonSessions,
                                timerSessions: viewModel.timerSessions,
                                pomodoroReflections: viewModel.pomodoroReflections,
                                pomodoroTaskCompletions: viewModel.pomodoroTaskCompletions,
                                breakTransitionIntents: viewModel.breakTransitionIntents,
                                aggregateSnapshot: viewModel.aggregateSnapshot,
                                attentionDaySummaries: viewModel.attentionDaySummaries,
                                focusNudge: viewModel.focusNudge,
                                historicalFocusTrend: viewModel.historicalFocusTrend,
                                vacationDays: viewModel.viewMode == .monthly ? viewModel.vacationDaysInMonth : []
                            )
                        }
                    }
                    .padding(appearanceDensity.informationMetric(20))
                }
                .opacity(viewModel.showsVacationIllustration ? 0 : 1)
                .allowsHitTesting(!viewModel.showsVacationIllustration)
                .accessibilityHidden(viewModel.showsVacationIllustration)

                if viewModel.showsVacationIllustration {
                    vacationIllustration
                }
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .appearanceAccentTint(.popover)
        .background(PopoverChrome.surface)
        .id(popoverTheme)
        .onAppear {
            viewModel.loadData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pomodoroReflectionDidChange)) { _ in
            viewModel.invalidateLoadCache()
            viewModel.loadData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pomodoroSessionDidChange)) { _ in
            viewModel.invalidateLoadCache()
            viewModel.loadData()
        }
        .onChange(of: viewModel.selectedDate) { _, _ in
            viewModel.loadData()
        }
        .onChange(of: viewModel.viewMode) { _, _ in
            viewModel.loadData()
        }
        .onChange(of: viewModel.trackerStore.vacationRanges.count) { _, _ in
            viewModel.invalidateAllAggregateCaches()
            viewModel.invalidateLoadCache()
            viewModel.loadData()
        }
        .sheet(isPresented: $viewModel.showEditor, onDismiss: {
            viewModel.invalidateAggregateCaches(containing: viewModel.selectedDate)
            viewModel.invalidateLoadCache()
            viewModel.loadData()
        }) {
            ManualSegmentEditorView(
                date: viewModel.selectedDate,
                repository: viewModel.statsEditorRepository
            )
        }
    }

    // MARK: - 휴가 표시 배너

    @ViewBuilder
    private var vacationBanner: some View {
        switch viewModel.viewMode {
        case .daily:
            if let range = viewModel.trackerStore.vacationRange(containing: viewModel.selectedDate) {
                VStack(spacing: 0) {
                    vacationBannerView(
                        title: range.label.isEmpty ? "🏖️ 휴가" : "🏖️ \(range.label)",
                        subtitle: "이 날은 휴가 기간이라 기록이 남아있지 않습니다."
                    )
                    Divider()
                }
            }
        case .weekly:
            if let (start, end) = viewModel.periodBounds(for: .weekly, date: viewModel.selectedDate) {
                let days = viewModel.trackerStore.vacationCount(in: start, end: end)
                if days > 0 {
                    VStack(spacing: 0) {
                        vacationBannerView(
                            title: "🏖️ 이 기간에 휴가 \(days)일 포함",
                            subtitle: "휴가로 표시된 날에는 기록이 남아있지 않아 차트에 빈 부분이 있을 수 있어요."
                        )
                        Divider()
                    }
                }
            }
        case .monthly:
            EmptyView()
        }
    }

    private func vacationBannerView(title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - 휴가 일러스트 (일간 + 데이터 없음)

    private var vacationIllustration: some View {
        let range = viewModel.trackerStore.vacationRange(containing: viewModel.selectedDate)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy. M. d."
        return VStack(spacing: 14) {
            Spacer(minLength: 0)
            Text("🌴🍅🌴")
                .font(.system(size: 56))
            Text("오늘은 푹 쉬세요")
                .font(.title.bold())
            if let range {
                Text("\(range.label.isEmpty ? "휴가 기간" : range.label) · \(formatter.string(from: range.start)) ~ \(formatter.string(from: range.end))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - 툴바

    private var toolbar: some View {
        HStack {
            Text("호롱호롱 통계")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PopoverChrome.inkSecondary)

            modePicker

            Spacer()

            dateNavigator

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    viewModel.contentMode = viewModel.contentMode == .focus ? .period : .focus
                }
            } label: {
                Label(
                    viewModel.contentMode == .focus ? "통계로" : "몰입",
                    systemImage: viewModel.contentMode == .focus ? "chevron.left" : "scope"
                )
            }
            .buttonStyle(LanternSecondaryButtonStyle())
            .controlSize(.small)
            .fixedSize()
            .help(viewModel.contentMode == .focus ? "기간 통계로 돌아갑니다" : "이 기간의 몰입 세션을 자세히 봅니다")
            .companionHighlight("stats.focusToggle")
            .onReceive(
                NotificationCenter.default.publisher(for: .companionOnboardingPerform)
            ) { notification in
                guard let action = notification.object as? String else { return }
                switch action {
                case "stats.showPeriod":
                    viewModel.contentMode = .period
                case "stats.showFocus":
                    withAnimation(.easeInOut(duration: 0.15)) { viewModel.contentMode = .focus }
                default:
                    break
                }
            }

            Button {
                viewModel.showEditor = true
            } label: {
                Label("편집", systemImage: "pencil")
            }
            .buttonStyle(LanternSecondaryButtonStyle())
            .controlSize(.small)
            .disabled(viewModel.viewMode != .daily)
            .help(viewModel.viewMode == .daily ? "이 날짜의 포모도로와 세그먼트를 수동 편집" : "일간 뷰에서만 사용할 수 있습니다")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(PopoverChrome.surfaceAlt)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PopoverChrome.divider)
                .frame(height: 1)
        }
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(StatsViewMode.allCases) { mode in
                Button {
                    viewModel.viewMode = mode
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 12, weight: viewModel.viewMode == mode ? .bold : .medium, design: .rounded))
                        .foregroundStyle(viewModel.viewMode == mode ? PopoverChrome.selectionInk : PopoverChrome.inkSecondary)
                        .frame(width: 54)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous)
                                .fill(modeChipFill(for: mode))
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .onHover { isHovering in
                    viewModel.hoveredViewMode = isHovering ? mode : nil
                }
            }
        }
        .padding(3)
        .background(PopoverChrome.surface, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(11), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PopoverChrome.radius(11), style: .continuous)
                .stroke(PopoverChrome.divider, lineWidth: 1)
        )
    }

    private func modeChipFill(for mode: StatsViewMode) -> Color {
        if viewModel.viewMode == mode {
            return PopoverChrome.selectionFill
        }
        if viewModel.hoveredViewMode == mode {
            return PopoverChrome.card
        }
        return .clear
    }

    private var dateNavigator: some View {
        HStack(spacing: 8) {
            Button {
                navigateDate(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(PopoverChrome.inkSecondary)

            Text(dateRangeText)
                .font(.callout)
                .foregroundStyle(PopoverChrome.ink)
                .frame(minWidth: 120)

            Button {
                navigateDate(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .foregroundStyle(PopoverChrome.inkSecondary)

            Button("오늘") {
                viewModel.selectedDate = Date()
            }
            .buttonStyle(LanternSecondaryButtonStyle())
            .controlSize(.small)
            .fixedSize()
        }
    }

    private var dateRangeText: String {
        let formatter = DateFormatter()
        switch viewModel.viewMode {
        case .daily:
            formatter.dateFormat = "yyyy년 M월 d일"
            return formatter.string(from: viewModel.selectedDate)
        case .weekly:
            let calendar = Calendar.current
            let weekStart = Constants.mondayWeekStart(for: viewModel.selectedDate, calendar: calendar)
            guard let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
                return ""
            }
            formatter.dateFormat = "M/d"
            return "\(formatter.string(from: weekStart)) ~ \(formatter.string(from: weekEnd))"
        case .monthly:
            formatter.dateFormat = "yyyy년 M월"
            return formatter.string(from: viewModel.selectedDate)
        }
    }

    private func navigateDate(by value: Int) {
        let calendar = Calendar.current
        switch viewModel.viewMode {
        case .daily:
            if let newDate = calendar.date(byAdding: .day, value: value, to: viewModel.selectedDate) {
                viewModel.selectedDate = newDate
            }
        case .weekly:
            if let newDate = calendar.date(byAdding: .weekOfYear, value: value, to: viewModel.selectedDate) {
                viewModel.selectedDate = newDate
            }
        case .monthly:
            if let newDate = calendar.date(byAdding: .month, value: value, to: viewModel.selectedDate) {
                viewModel.selectedDate = newDate
            }
        }
    }
}
