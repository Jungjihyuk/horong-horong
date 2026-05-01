import SwiftUI
import SwiftData

struct StatsDetailWindow: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewMode: StatsViewMode = .daily
    @State private var selectedDate: Date = Date()
    @State private var records: [AppUsageRecord] = []
    @State private var dailySegments: [AppUsageSegment] = []
    @State private var weekSegments: [AppUsageSegment] = []
    @State private var periodSegments: [AppUsageSegment] = []
    @State private var timerSessions: [FocusSession] = []
    @State private var showEditor: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView {
                StatsChartView(
                    records: records,
                    viewMode: viewMode,
                    referenceDate: selectedDate,
                    dailySegments: dailySegments,
                    weekSegments: weekSegments,
                    periodSegments: periodSegments,
                    timerSessions: timerSessions
                )
                .padding(20)
            }
        }
        .frame(minWidth: 720, minHeight: 460)
        .onAppear { loadRecords() }
        .onChange(of: selectedDate) { _, _ in loadRecords() }
        .onChange(of: viewMode) { _, _ in loadRecords() }
        .sheet(isPresented: $showEditor, onDismiss: { loadRecords() }) {
            ManualSegmentEditorView(date: selectedDate)
        }
    }

    private var toolbar: some View {
        HStack {
            Picker("기간", selection: $viewMode) {
                ForEach(StatsViewMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            Spacer()

            dateNavigator

            Button {
                showEditor = true
            } label: {
                Label("편집", systemImage: "pencil")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewMode != .daily)
            .help(viewMode == .daily ? "이 날짜의 세그먼트를 수동 편집" : "일간 뷰에서만 사용할 수 있습니다")
        }
        .padding(12)
    }

    private var dateNavigator: some View {
        HStack(spacing: 8) {
            Button {
                navigateDate(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)

            Text(dateRangeText)
                .font(.callout)
                .frame(minWidth: 120)

            Button {
                navigateDate(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)

            Button("오늘") {
                selectedDate = Date()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var dateRangeText: String {
        let formatter = DateFormatter()
        switch viewMode {
        case .daily:
            formatter.dateFormat = "yyyy년 M월 d일"
            return formatter.string(from: selectedDate)
        case .weekly:
            let calendar = Calendar.current
            guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)),
                  let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
                return ""
            }
            formatter.dateFormat = "M/d"
            return "\(formatter.string(from: weekStart)) ~ \(formatter.string(from: weekEnd))"
        case .monthly:
            formatter.dateFormat = "yyyy년 M월"
            return formatter.string(from: selectedDate)
        }
    }

    private func navigateDate(by value: Int) {
        let calendar = Calendar.current
        switch viewMode {
        case .daily:
            if let newDate = calendar.date(byAdding: .day, value: value, to: selectedDate) {
                selectedDate = newDate
            }
        case .weekly:
            if let newDate = calendar.date(byAdding: .weekOfYear, value: value, to: selectedDate) {
                selectedDate = newDate
            }
        case .monthly:
            if let newDate = calendar.date(byAdding: .month, value: value, to: selectedDate) {
                selectedDate = newDate
            }
        }
    }

    private func loadRecords() {
        let calendar = Calendar.current
        let startDate: Date
        let endDate: Date

        switch viewMode {
        case .daily:
            startDate = calendar.startOfDay(for: selectedDate)
            endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        case .weekly:
            guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)) else { return }
            startDate = weekStart
            endDate = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        case .monthly:
            guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate)) else { return }
            startDate = monthStart
            endDate = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        }

        let descriptor = FetchDescriptor<AppUsageRecord>(
            predicate: #Predicate { $0.date >= startDate && $0.date < endDate }
        )

        records = (try? modelContext.fetch(descriptor)) ?? []

        loadSegments(for: viewMode)
        loadTimerSessions(start: startDate, end: endDate)
    }

    /// 전환 카운트 예외 판단용. 범위 앞쪽으로 약간 버퍼를 둬서 경계에 걸친 세션도 포함.
    private func loadTimerSessions(start: Date, end: Date) {
        guard viewMode != .monthly else {
            timerSessions = []
            return
        }
        let calendar = Calendar.current
        let bufferStart = calendar.date(byAdding: .hour, value: -4, to: start) ?? start
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.startedAt >= bufferStart && $0.startedAt < end },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        timerSessions = (try? modelContext.fetch(descriptor)) ?? []
    }

    /// 일간 뷰에서는 선택한 하루의 세그먼트, 주간 뷰에서는 해당 주 7일 세그먼트를 읽는다.
    private func loadSegments(for mode: StatsViewMode) {
        let calendar = Calendar.current

        switch mode {
        case .daily:
            let dayStart = calendar.startOfDay(for: selectedDate)
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
                dailySegments = []
                weekSegments = []
                periodSegments = []
                return
            }
            let dayDescriptor = FetchDescriptor<AppUsageSegment>(
                predicate: #Predicate { $0.startTime < dayEnd && $0.endTime > dayStart },
                sortBy: [SortDescriptor(\.startTime)]
            )
            dailySegments = (try? modelContext.fetch(dayDescriptor)) ?? []
            weekSegments = []
            periodSegments = dailySegments

        case .weekly:
            dailySegments = []
            guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)),
                  let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
                weekSegments = []
                periodSegments = []
                return
            }
            let weekDescriptor = FetchDescriptor<AppUsageSegment>(
                predicate: #Predicate { $0.startTime < weekEnd && $0.endTime > weekStart },
                sortBy: [SortDescriptor(\.startTime)]
            )
            weekSegments = (try? modelContext.fetch(weekDescriptor)) ?? []
            periodSegments = weekSegments

        case .monthly:
            dailySegments = []
            weekSegments = []
            guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate)),
                  let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
                periodSegments = []
                return
            }
            let monthDescriptor = FetchDescriptor<AppUsageSegment>(
                predicate: #Predicate { $0.startTime < monthEnd && $0.endTime > monthStart },
                sortBy: [SortDescriptor(\.startTime)]
            )
            periodSegments = (try? modelContext.fetch(monthDescriptor)) ?? []
        }
    }
}
