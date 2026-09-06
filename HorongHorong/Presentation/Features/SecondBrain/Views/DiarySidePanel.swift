import SwiftUI

/// 편집기 오른쪽에 접었다 펴는 패널. 달력과 감정·수면 인사이트 카드를 담는다.
///
/// **글쓰기가 주인이다.** 예전에는 달력이 280pt 를 항상 차지하고 접을 수도 없어,
/// 정작 일기를 쓰는 자리가 남는 폭으로 밀려 있었다.
struct DiarySidePanel: View {
    let visibleMonth: Date
    let selectedDay: Date
    let writtenCount: Int
    let snapshot: DiaryInsightsSnapshot
    let axis: DiarySleepAxis
    let calendar: Calendar
    let moodEmoji: (Date) -> String?
    let moodGroups: (Date) -> [DiaryMoodGroup]
    let onSelectDay: (Date) -> Void
    let onShiftMonth: (Int) -> Void
    let onGoToToday: () -> Void
    let onCollapse: () -> Void
    let onOpenInsights: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            ScrollView {
                VStack(spacing: 12) {
                    calendarBlock
                    DiaryMoodTimelineCard(snapshot: snapshot).equatable()
                    DiaryMoodPatternCard(snapshot: snapshot).equatable()
                    DiarySleepInsightCard(snapshot: snapshot, axis: axis).equatable()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
        }
        .background(PopoverChrome.surfaceAlt)
    }

    private var panelHeader: some View {
        HStack(spacing: 6) {
            Button(action: onCollapse) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(PopoverChrome.inkSecondary)
            .help("패널 접기")
            .accessibilityLabel("패널 접기")

            Spacer(minLength: 0)

            Button("인사이트", action: onOpenInsights)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(PopoverChrome.accent)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    // MARK: - 달력

    private var calendarBlock: some View {
        let month = calendar.dateComponents([.year, .month], from: visibleMonth)
        let first = calendar.date(from: month) ?? visibleMonth
        let daysInMonth = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let pad = calendar.component(.weekday, from: first) - 1
        let cells: [Int?] = Array(repeating: nil, count: pad) + Array(1...daysInMonth)
        let today = calendar.startOfDay(for: Date())

        return VStack(alignment: .leading, spacing: 10) {
            monthHeader
            weekdayHeader

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 3) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        let date = calendar.date(byAdding: .day, value: day - 1, to: first)
                            .map { calendar.startOfDay(for: $0) } ?? today
                        Button { onSelectDay(date) } label: {
                            DiaryDayCell(
                                day: day,
                                emoji: moodEmoji(date),
                                groups: moodGroups(date),
                                isToday: date == today,
                                isSelected: date == selectedDay
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(minHeight: 42)
                    }
                }
            }

            HStack(spacing: 8) {
                Button("오늘로", action: onGoToToday)
                    .controlSize(.small)
                Spacer(minLength: 0)
                Text("이 달에 \(writtenCount)일")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }
        }
        .padding(12)
        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PopoverChrome.border, lineWidth: 0.5)
        )
    }

    private var monthHeader: some View {
        HStack {
            Button { onShiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)
            Spacer()
            Text(DiaryDateText.month(visibleMonth))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
            Spacer()
            Button { onShiftMonth(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain)
        }
        .foregroundStyle(PopoverChrome.inkSecondary)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 3) {
            ForEach(Array(["일", "월", "화", "수", "목", "금", "토"].enumerated()), id: \.offset) { index, name in
                Text(name)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(index == 0 ? .red.opacity(0.7) : PopoverChrome.inkTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// 달력 한 칸. **값만 들고 있어 `Equatable` 이 성립한다.**
///
/// 하루에 감정을 최대 셋까지 적으므로 이모지 하나로는 «몇 칸을 적었는지» 를 알 수 없다.
/// 대표 이모지 아래에 기록 수만큼 점을 찍어, 하나만 적은 날과 셋 다 적은 날을 구분한다.
struct DiaryDayCell: View, Equatable {
    let day: Int
    let emoji: String?
    let groups: [DiaryMoodGroup]
    let isToday: Bool
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 1) {
            Text("\(day)")
                .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .rounded))
            Text(emoji ?? " ")
                .font(.system(size: 10))
                .frame(height: 13)
            HStack(spacing: 2) {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    Circle()
                        .fill(group.chartColor.opacity(0.85))
                        .frame(width: 3.5, height: 3.5)
                }
            }
            .frame(height: 4)
        }
        .foregroundStyle(isToday ? PopoverChrome.accent : PopoverChrome.ink)
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? PopoverChrome.accentSoft.opacity(0.7) : .clear)
        )
        .accessibilityLabel(groups.isEmpty ? "\(day)일" : "\(day)일, 감정 \(groups.count)건")
    }
}

@MainActor
enum DiaryDateText {
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
