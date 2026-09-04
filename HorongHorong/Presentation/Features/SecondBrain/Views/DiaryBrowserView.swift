import SwiftUI

/// 달력과 그날의 일기.
///
/// **`@Query`·`ModelContext` 를 쓰지 않는다.** 화면은 ViewModel 이 준 값 타입만 본다.
struct DiaryBrowserView: View {
    @State private var viewModel: DiaryViewModel

    private let calendar = Calendar.current

    init(repository: DiaryRepository, sleep: SleepGateway) {
        _viewModel = State(initialValue: DiaryViewModel(repository: repository, sleep: sleep))
    }

    var body: some View {
        HStack(spacing: 0) {
            calendarPane
            Divider().overlay(PopoverChrome.divider)
            editorPane
        }
        .onAppear {
            viewModel.reload()
            viewModel.pullSleepIfNeeded()
        }
        .onDisappear { viewModel.flush() }
    }

    // MARK: - 달력

    private var calendarPane: some View {
        let month = calendar.dateComponents([.year, .month], from: viewModel.visibleMonth)
        let first = calendar.date(from: month) ?? viewModel.visibleMonth
        let daysInMonth = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let pad = calendar.component(.weekday, from: first) - 1
        let cells: [Int?] = Array(repeating: nil, count: pad) + Array(1...daysInMonth)
        let today = calendar.startOfDay(for: Date())

        return VStack(alignment: .leading, spacing: 12) {
            monthHeader
            weekdayHeader

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        let date = calendar.date(byAdding: .day, value: day - 1, to: first)
                            .map { calendar.startOfDay(for: $0) } ?? today
                        Button {
                            viewModel.select(date)
                        } label: {
                            DiaryDayCell(
                                day: day,
                                emoji: viewModel.entry(on: date)?.mood?.emoji,
                                isToday: date == today,
                                isSelected: date == viewModel.selectedDay
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(minHeight: 42)
                    }
                }
            }
            .padding(.horizontal, 10)

            Button("오늘로") {
                viewModel.goToToday()
            }
            .controlSize(.small)
            .padding(.horizontal, 16)

            Text("이 달에 \(viewModel.writtenCount)일 기록")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
                .padding(.horizontal, 16)

            Spacer()
        }
        .frame(width: 280)
        .background(PopoverChrome.surfaceAlt)
    }

    private var monthHeader: some View {
        HStack {
            Button { viewModel.shiftMonth(-1) } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            Spacer()
            Text(DiaryDateText.month(viewModel.visibleMonth))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
            Spacer()
            Button { viewModel.shiftMonth(1) } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(PopoverChrome.inkSecondary)
        .padding(.horizontal, 16)
        .padding(.top, 18)
    }

    private var weekdayHeader: some View {
        HStack {
            ForEach(Array(["일", "월", "화", "수", "목", "금", "토"].enumerated()), id: \.offset) { index, name in
                Text(name)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(index == 0 ? .red.opacity(0.7) : PopoverChrome.inkTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 10)
    }

    // MARK: - 편집기

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            editorHeader
            metaRow
            Divider().overlay(PopoverChrome.divider)

            TextEditor(text: $viewModel.bodyDraft)
                .font(.system(size: 15, design: .rounded))
                .scrollContentBackground(.hidden)
                .padding(16)
                .onChange(of: viewModel.bodyDraft) { _, _ in viewModel.draftChanged() }

            HStack {
                Text("\(viewModel.bodyDraft.count)자 · 자동 저장")
                Spacer()
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(PopoverChrome.inkTertiary)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(PopoverChrome.surface)
    }

    private var editorHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(DiaryDateText.day(viewModel.selectedDay))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                if calendar.isDateInToday(viewModel.selectedDay) {
                    Text("오늘")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.accentInk)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(PopoverChrome.accent, in: Capsule())
                }
            }
            Text(viewModel.selected == nil ? "아직 비어 있어요" : "기록됨")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var metaRow: some View {
        HStack(alignment: .top, spacing: 24) {
            metaGroup(title: "기분") {
                HStack(spacing: 6) {
                    ForEach(DiaryMood.allCases) { mood in
                        Button {
                            viewModel.setMood(mood)
                        } label: {
                            Text(mood.emoji)
                                .font(.system(size: 18))
                                .frame(width: 34, height: 34)
                                .background(
                                    viewModel.selected?.mood == mood ? PopoverChrome.accentSoft : PopoverChrome.card,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(mood.rawValue)
                    }
                }
            }
            metaGroup(title: "수면") {
                VStack(alignment: .leading, spacing: 6) {
                    Stepper(sleepLabel, value: sleepBinding, in: 0...14, step: 0.5)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                    HStack(spacing: 8) {
                        Text(sleepSourceCaption)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(PopoverChrome.inkTertiary)
                        if viewModel.isSleepAvailable {
                            Button(viewModel.isPullingSleep ? "가져오는 중…" : "건강 앱에서 가져오기") {
                                viewModel.pullSleep(force: true)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(PopoverChrome.accent)
                            .disabled(viewModel.isPullingSleep)
                        }
                    }
                }
            }
            metaGroup(title: "스트레스") {
                HStack(spacing: 6) {
                    ForEach(1...5, id: \.self) { value in
                        Button {
                            viewModel.setStress(value)
                        } label: {
                            Text("\(value)")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .frame(width: 28, height: 28)
                                .foregroundStyle(viewModel.selected?.stress == value ? PopoverChrome.accentInk : PopoverChrome.inkSecondary)
                                .background(
                                    viewModel.selected?.stress == value ? PopoverChrome.accent : PopoverChrome.card,
                                    in: Circle()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func metaGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
            content()
        }
    }

    private var sleepLabel: String {
        guard let hours = viewModel.selected?.sleepHours else { return "기록 없음" }
        return String(format: "%.1f시간", hours)
    }

    private var sleepSourceCaption: String {
        switch viewModel.selected?.sleepSource {
        case .healthKit:
            return "건강 앱 기록 · 직접 고쳐도 됩니다"
        case .manual:
            return "직접 입력함"
        case nil:
            return viewModel.isSleepAvailable
                ? "건강 앱에 없으면 직접 입력하세요"
                : "이 Mac에서는 건강 앱을 쓸 수 없어 직접 입력하세요"
        }
    }

    private var sleepBinding: Binding<Double> {
        Binding(
            get: { viewModel.selected?.sleepHours ?? 7 },
            set: { viewModel.setSleepHours($0) }
        )
    }
}

/// 달력 한 칸. **값만 들고 있어 `Equatable` 이 성립한다.**
private struct DiaryDayCell: View, Equatable {
    let day: Int
    let emoji: String?
    let isToday: Bool
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text("\(day)")
                .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
            Text(emoji ?? " ")
                .font(.system(size: 11))
                .frame(height: 14)
        }
        .foregroundStyle(isToday ? PopoverChrome.accent : PopoverChrome.ink)
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? PopoverChrome.accentSoft.opacity(0.7) : .clear)
        )
    }
}

/// body 평가마다 새로 만들면 로케일 데이터 로드가 반복된다.
@MainActor
private enum DiaryDateText {
    static func month(_ date: Date) -> String { monthFormatter.string(from: date) }
    static func day(_ date: Date) -> String { dayFormatter.string(from: date) }

    private static let monthFormatter = make("yyyy년 M월")
    private static let dayFormatter = make("yyyy년 M월 d일 EEEE")

    private static func make(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = format
        return formatter
    }
}
