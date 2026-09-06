import SwiftUI

/// 할 일 상세의 «일정» 카드.
///
/// 날짜를 고르는 길을 세 갈래로 둔다 — 7일 띠(가장 흔한 이번 주), 빠른 칩(오늘·내일),
/// 달력(그 밖의 날). 셋 다 **며칠 뒤인지**로 바꿔 밖에 넘긴다. 그래야 이미 정해 둔
/// 시각(09:30)을 잃지 않고 날짜만 옮길 수 있다.
struct TodoScheduleCard: View {
    let startDate: Date?
    let deadline: Date?
    let today: Date
    let onPickDayOffset: (Int) -> Void
    let onClear: () -> Void
    let onPickTime: (Int, Int) -> Void
    let onPickDeadlineTime: (Int, Int) -> Void
    /// 왼쪽 둘은 최근 값, 오른쪽 둘은 고정 값. 어느 쪽인지는 슬롯이 들고 있다.
    let durationSlots: [TodoDurationSlots.Slot]
    let onPickDuration: (Int) -> Void
    let onPinDuration: (Int) -> Void
    let onUnpinDuration: (Int) -> Void
    let onClearDuration: () -> Void
    let onCustomDuration: () -> Void
    @Binding var showsCustomDuration: Bool
    let customDurationContent: () -> AnyView
    /// 날짜 줄이 접히지 않으려면 카드가 최소 몇 pt 여야 하는지 알린다.
    let onMinimumWidthChange: (CGFloat) -> Void

    @State private var showsCalendar = false
    @State private var activeTimePicker: TimePickerTarget?
    @State private var displayedMonth: Date

    init<CustomDurationContent: View>(
        startDate: Date?,
        deadline: Date?,
        today: Date,
        onPickDayOffset: @escaping (Int) -> Void,
        onClear: @escaping () -> Void,
        onPickTime: @escaping (Int, Int) -> Void,
        onPickDeadlineTime: @escaping (Int, Int) -> Void,
        durationSlots: [TodoDurationSlots.Slot],
        onPickDuration: @escaping (Int) -> Void,
        onPinDuration: @escaping (Int) -> Void,
        onUnpinDuration: @escaping (Int) -> Void,
        onClearDuration: @escaping () -> Void,
        onCustomDuration: @escaping () -> Void,
        showsCustomDuration: Binding<Bool>,
        @ViewBuilder customDurationContent: @escaping () -> CustomDurationContent,
        onMinimumWidthChange: @escaping (CGFloat) -> Void
    ) {
        self.startDate = startDate
        self.deadline = deadline
        self.today = today
        self.onPickDayOffset = onPickDayOffset
        self.onClear = onClear
        self.onPickTime = onPickTime
        self.onPickDeadlineTime = onPickDeadlineTime
        self.durationSlots = durationSlots
        self.onPickDuration = onPickDuration
        self.onPinDuration = onPinDuration
        self.onUnpinDuration = onUnpinDuration
        self.onClearDuration = onClearDuration
        self.onCustomDuration = onCustomDuration
        _showsCustomDuration = showsCustomDuration
        self.customDurationContent = { AnyView(customDurationContent()) }
        self.onMinimumWidthChange = onMinimumWidthChange
        _displayedMonth = State(initialValue: startDate ?? today)
    }

    private var calendar: Calendar { .current }

    private var durationMinutes: Int? {
        guard let startDate, let deadline, deadline > startDate else { return nil }
        return Int(deadline.timeIntervalSince(startDate) / 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            headerRow
            dateLine
            if showsCalendar {
                monthPicker
            } else {
                weekStrip
            }
            quickChips
            if let startDate {
                sectionDivider
                scheduleTimeSection(startDate)
            }
        }
        .padding(13)
        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PopoverChrome.border.opacity(0.8), lineWidth: 1)
        )
        // 다른 할 일로 옮기면 달력이 열려 있던 것도, 보고 있던 달도 따라가야 한다.
        .onChange(of: startDate) { _, newValue in
            displayedMonth = newValue ?? today
        }
    }

    // MARK: - 머리말

    private var headerRow: some View {
        HStack(spacing: 5) {
            Image(systemName: "calendar")
                .font(.system(size: 11, weight: .bold))
            Text("일정")
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
            Spacer(minLength: 8)
            Button {
                withAnimation(.easeOut(duration: 0.16)) { showsCalendar.toggle() }
            } label: {
                Text("달력에서 고르기")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(showsCalendar ? TodoPickPalette.inkSoft : PopoverChrome.inkTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(showsCalendar ? TodoPickPalette.fill : Color.clear)
                    )
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(PopoverChrome.inkTertiary)
    }

    private static let dateLineSpacing: CGFloat = 7
    private static let clearButtonSize: CGFloat = 22
    /// 카드 좌우 안쪽 여백(13×2) + 날짜와 × 사이 최소 간극.
    private static let dateLineChromeWidth: CGFloat = 13 * 2 + 6

    private var dateLine: some View {
        HStack(spacing: Self.dateLineSpacing) {
            dateLineContent
            Spacer(minLength: 6)
            if startDate != nil {
                Button(action: onClear) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .frame(width: Self.clearButtonSize, height: Self.clearButtonSize)
                        .background(PopoverChrome.surface, in: Circle())
                }
                .buttonStyle(.plain)
                .help("일정 지우기")
                .accessibilityLabel("일정 지우기")
            }
        }
        .background(alignment: .leading) { dateLineRuler }
    }

    @ViewBuilder
    private var dateLineContent: some View {
        if let startDate {
            Text(TodoScheduleText.fullDay(startDate, now: today, calendar: calendar))
                .font(.system(size: 15.5, weight: .heavy, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
                // 패널을 좁혀도 두 줄로 접히지 않는다. 최소 너비가 이 줄을 지켜 주지만,
                // 창 자체가 좁아 그마저 못 지킬 때는 접는 대신 말줄임으로 버틴다.
                .lineLimit(1)
            pill(TodoDayTime.label(startDate, calendar: calendar), strong: true)
            if let badge = TodoScheduleText.relativeBadge(startDate, now: today, calendar: calendar) {
                pill(badge, strong: false)
            }
        } else {
            Text("날짜 없음")
                .font(.system(size: 15.5, weight: .heavy, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
                .lineLimit(1)
        }
    }

    /// 보이지 않는 자. 날짜 줄을 한 줄로 폈을 때의 너비를 재서 바깥에 알린다.
    /// 보이는 쪽은 말줄임이 걸려 있어 스스로는 온전한 폭을 알려 주지 못한다.
    private var dateLineRuler: some View {
        HStack(spacing: Self.dateLineSpacing) {
            dateLineContent
            if startDate != nil {
                Color.clear.frame(width: Self.clearButtonSize, height: 1)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .hidden()
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size.width, initial: true) { _, width in
                        onMinimumWidthChange(width + Self.dateLineChromeWidth)
                    }
            }
        }
    }

    // MARK: - 7일 띠

    /// 오늘부터 2주. 한 화면에 이레쯤 보이고 나머지는 옆으로 밀어서 본다 —
    /// 카드를 두 배로 키우지 않고도 «다다음 주 화요일» 까지 손이 닿는다.
    private static let stripDayCount = 14
    /// 참고 시안(`sb-todo.jsx` 의 `.td-day`)과 같은 44pt. 높이와 비슷해 정사각형에 가깝다.
    private static let stripCellWidth: CGFloat = 44

    private var weekStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 5) {
                    ForEach(0..<Self.stripDayCount, id: \.self) { offset in
                        let date = calendar.date(byAdding: .day, value: offset, to: today) ?? today
                        dayCell(offset: offset, date: date)
                            .id(offset)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 50)
            // 고른 날이 화면 밖에 있으면 보이지 않는 곳에서 선택된 셈이라 아무 표시도 안 남는다.
            .onAppear { scrollToSelection(proxy, animated: false) }
            .onChange(of: startDate) { _, _ in scrollToSelection(proxy, animated: true) }
        }
    }

    private func scrollToSelection(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let startDate else { return }
        let offset = dayOffset(to: startDate)
        guard (0..<Self.stripDayCount).contains(offset) else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(offset, anchor: .center) }
        } else {
            proxy.scrollTo(offset, anchor: .center)
        }
    }

    private func dayCell(offset: Int, date: Date) -> some View {
        let selected = isSelected(date)
        let isToday = offset == 0
        return Button {
            onPickDayOffset(offset)
        } label: {
            VStack(spacing: 3) {
                Text(TodoScheduleText.stripDayName(offset: offset, date: date, calendar: calendar))
                    .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(dayNameInk(offset: offset, date: date, selected: selected))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(selected ? TodoPickPalette.ink : PopoverChrome.inkSecondary)
                    .monospacedDigit()
            }
            .frame(width: Self.stripCellWidth, height: 42)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(selected ? TodoPickPalette.fill : PopoverChrome.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        strokeColor(selected: selected, isToday: isToday),
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    /// 주말 색은 «토»·«일» 이라고 **적힌 칸에만** 칠한다.
    /// 앞 두 칸은 «오늘»·«내일» 이라 요일이 드러나지 않는데, 거기까지 물들이면
    /// 오늘이 토요일이라는 이유만으로 «오늘» 이 파랗게 보여 뜻을 오해하게 된다.
    private func strokeColor(selected: Bool, isToday: Bool) -> Color {
        if selected { return TodoPickPalette.stroke }
        return isToday ? PopoverChrome.accentSoft : Color.clear
    }

    private func dayNameInk(offset: Int, date: Date, selected: Bool) -> Color {
        if selected { return TodoPickPalette.inkSoft }
        if offset == 0 { return PopoverChrome.accent }
        if offset == 1 { return PopoverChrome.inkTertiary }
        return weekdayInk(date)
    }

    // MARK: - 달력

    private var monthPicker: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                monthStepButton("chevron.left", months: -1)
                Text(displayedMonth.formatted(.dateTime.year().month(.wide)))
                    .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                    .frame(minWidth: 96)
                monthStepButton("chevron.right", months: 1)
                Spacer(minLength: 0)
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { showsCalendar = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("달력 닫기")
            }

            HStack(spacing: 2) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(weekdayInk(columnIndex: index))
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                    if let day {
                        monthDayCell(day)
                    } else {
                        Color.clear.frame(height: 28)
                    }
                }
            }
        }
    }

    private func monthStepButton(_ symbol: String, months: Int) -> some View {
        Button {
            displayedMonth = calendar.date(byAdding: .month, value: months, to: displayedMonth) ?? displayedMonth
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(PopoverChrome.inkSecondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(months < 0 ? "이전 달" : "다음 달")
    }

    private func monthDayCell(_ day: Date) -> some View {
        let selected = isSelected(day)
        let isToday = calendar.isDate(day, inSameDayAs: today)
        return Button {
            onPickDayOffset(dayOffset(to: day))
        } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 12.5, weight: selected || isToday ? .heavy : .medium, design: .rounded))
                .foregroundStyle(selected ? TodoPickPalette.ink : dayInk(day))
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? TodoPickPalette.fill : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(strokeColor(selected: selected, isToday: isToday), lineWidth: 1.2)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 빠른 칩

    /// 자주 쓰는 기준만 남긴다. 주말·다음 주는 7일 띠와 달력에서 고를 수 있어 중복된다.
    private static let quickScheduleOptions: [TodoQuickSchedule] = [.today, .tomorrow, .someday]

    private var quickChips: some View {
        TodoChipFlow(spacing: 6) {
            ForEach(Self.quickScheduleOptions) { option in
                quickChip(option)
            }
        }
    }

    private func quickChip(_ option: TodoQuickSchedule) -> some View {
        let offset = option.dayOffset(now: today, calendar: calendar)
        let selected = isSelected(option)
        return Button {
            if let offset {
                onPickDayOffset(offset)
            } else {
                onClear()
            }
        } label: {
            Text(option.title)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(selected ? TodoPickPalette.ink : PopoverChrome.inkSecondary)
                .padding(.horizontal, 11)
                .frame(height: 27)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? TodoPickPalette.fill : PopoverChrome.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            selected ? TodoPickPalette.stroke : PopoverChrome.border,
                            // «언젠가» 는 날짜를 **지우는** 것이라 다른 칩과 성격이 다르다.
                            // 점선으로 그 차이를 보인다.
                            style: StrokeStyle(lineWidth: 1.2, dash: option == .someday ? [3, 2.5] : [])
                        )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 시간과 소요 시간

    private enum TimePickerTarget: Equatable { case start, end }

    private func scheduleTimeSection(_ start: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                rowLabel("시간")
                Spacer(minLength: 0)
                if durationMinutes != nil {
                    clearButton("걸리는 시간 지우기", action: onClearDuration)
                }
                durationValueChip
            }

            HStack(spacing: 6) {
                timeValueChip(start, target: .start)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                if let end = deadline {
                    timeValueChip(end, target: .end)
                } else {
                    Text("종료 시각")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(PopoverChrome.border, style: StrokeStyle(lineWidth: 1.2, dash: [3, 2.5]))
                        )
                }
                if let durationMinutes {
                    Text(TodoDurationText.title(minutes: durationMinutes))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 5) {
                ForEach(durationSlots) { slot in
                    durationChip(slot, start: start)
                }
            }

            if let activeTimePicker {
                TodoWheelTimePicker(
                    date: activeTimePicker == .start ? start : (deadline ?? start),
                    onPick: { date in
                        let hour = calendar.component(.hour, from: date)
                        let minute = calendar.component(.minute, from: date)
                        if activeTimePicker == .start {
                            onPickTime(hour, minute)
                        } else {
                            onPickDeadlineTime(hour, minute)
                        }
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.16), value: activeTimePicker)
    }

    private func timeValueChip(_ date: Date, target: TimePickerTarget) -> some View {
        let timeLabel = clockLabel(date)
        return Button {
            withAnimation(.easeOut(duration: 0.16)) {
                activeTimePicker = activeTimePicker == target ? nil : target
            }
        } label: {
            Text(timeLabel)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(TodoPickPalette.ink)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(TodoPickPalette.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(activeTimePicker == target ? TodoPickPalette.stroke : TodoPickPalette.stroke.opacity(0.55), lineWidth: 1.2)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(target == .start ? "시작 시간 \(timeLabel)" : "마감 시간 \(timeLabel)")
    }

    private func clockLabel(_ date: Date) -> String {
        String(format: "%02d:%02d", calendar.component(.hour, from: date), calendar.component(.minute, from: date))
    }

    /// 소요 시간 프리셋 옆의 직접 입력 버튼. 팝오버는 이 버튼을 기준으로 열린다.
    private var durationValueChip: some View {
        Button(action: onCustomDuration) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(PopoverChrome.inkSecondary)
                .frame(width: 24, height: 24)
                .background(PopoverChrome.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("소요 시간 직접 입력")
        .popover(isPresented: $showsCustomDuration, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
            customDurationContent()
        }
    }

    private func durationChip(_ slot: TodoDurationSlots.Slot, start: Date) -> some View {
        stackedChip(
            top: TodoDurationText.title(minutes: slot.minutes),
            bottom: TodoDurationText.endLabel(start: start, minutes: slot.minutes, calendar: calendar),
            emphasis: .top,
            selected: durationMinutes == slot.minutes,
            pinned: slot.isPinned
        ) {
            onPickDuration(slot.minutes)
        }
        .contextMenu {
            if slot.isPinned {
                Button("고정 풀기") { onUnpinDuration(slot.minutes) }
            } else {
                Button("오른쪽에 고정") { onPinDuration(slot.minutes) }
            }
        }
        .help(slot.isPinned
              ? "고정된 칸 — 오른쪽 클릭으로 풀 수 있습니다"
              : "최근에 쓴 값 — 새 값을 쓰면 밀려납니다. 오른쪽 클릭으로 고정하세요")
    }

    // MARK: - 조각

    private var sectionDivider: some View {
        Divider().overlay(PopoverChrome.divider.opacity(0.6))
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5, weight: .bold, design: .rounded))
            .foregroundStyle(PopoverChrome.inkTertiary)
    }

    private func pill(_ text: String, strong: Bool) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .heavy, design: .rounded))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(PopoverChrome.accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(
                PopoverChrome.accentSoft.opacity(strong ? 1 : 0.55),
                in: Capsule(style: .continuous)
            )
    }

    /// 지금 값을 보여 주면서 고치는 자리로도 쓰이는 칩. 값이 없으면 점선으로 «비어 있음» 을 알린다.
    private func valueChip(_ text: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(filled ? TodoPickPalette.inkSoft : PopoverChrome.inkTertiary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(filled ? TodoPickPalette.fill : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            filled ? TodoPickPalette.stroke : PopoverChrome.border,
                            style: StrokeStyle(lineWidth: 1.2, dash: filled ? [] : [3, 2.5])
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func clearButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(PopoverChrome.inkSecondary)
                .frame(width: 20, height: 20)
                .background(PopoverChrome.surface, in: Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    /// 두 줄 칩에서 어느 줄을 크게 볼지.
    ///
    /// 시각은 «아침» 보다 «8시» 가, 길이는 «~9:00» 보다 «1시간» 이 먼저 읽혀야 한다.
    enum ChipEmphasis { case top, bottom }

    private func stackedChip(
        top: String,
        bottom: String,
        emphasis: ChipEmphasis,
        selected: Bool,
        pinned: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(top)
                    .font(.system(size: emphasis == .top ? 12 : 10, weight: emphasis == .top ? .heavy : .bold, design: .rounded))
                    .foregroundStyle(chipInk(selected: selected, strong: emphasis == .top))
                Text(bottom)
                    .font(.system(size: emphasis == .bottom ? 12.5 : 10, weight: emphasis == .bottom ? .heavy : .bold, design: .rounded))
                    .foregroundStyle(chipInk(selected: selected, strong: emphasis == .bottom))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? TodoPickPalette.fill : PopoverChrome.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? TodoPickPalette.stroke : Color.clear, lineWidth: 1.3)
            )
            // 고정된 칸임을 알리는 자물쇠. 어느 칸이 흘러가는지 눈으로 구분되어야
            // «내가 쓰던 값이 왜 사라졌지» 가 생기지 않는다.
            .overlay(alignment: .topTrailing) {
                if pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 6.5, weight: .bold))
                        .foregroundStyle(PopoverChrome.inkTertiary.opacity(0.7))
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: emphasis == .bottom, vertical: false)
    }

    private func chipInk(selected: Bool, strong: Bool) -> Color {
        if selected { return strong ? TodoPickPalette.ink : TodoPickPalette.inkSoft }
        return strong ? PopoverChrome.inkSecondary : PopoverChrome.inkTertiary
    }

    private func disclosureRow(_ title: String, expanded: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                Text(title)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                Spacer(minLength: 0)
            }
            .foregroundStyle(PopoverChrome.inkTertiary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 계산

    private func isSelected(_ option: TodoQuickSchedule) -> Bool {
        guard let offset = option.dayOffset(now: today, calendar: calendar) else {
            return startDate == nil
        }
        guard let target = calendar.date(byAdding: .day, value: offset, to: today) else { return false }
        return isSelected(target)
    }

    private func isSelected(_ date: Date) -> Bool {
        guard let startDate else { return false }
        return calendar.isDate(startDate, inSameDayAs: date)
    }

    private func dayOffset(to date: Date) -> Int {
        calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: today),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    private var monthDays: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }
        let first = interval.start
        let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let days = (0..<count).map { calendar.date(byAdding: .day, value: $0, to: first) }
        return Array(repeating: nil, count: leading) + days
    }

    private func weekdayInk(_ date: Date) -> Color {
        switch calendar.component(.weekday, from: date) {
        case 1: return TodoCalendarPalette.sunday
        case 7: return TodoCalendarPalette.saturday
        default: return PopoverChrome.inkTertiary
        }
    }

    private func weekdayInk(columnIndex: Int) -> Color {
        // 열 번호를 실제 요일로 되돌린다. 첫 요일이 일요일이 아닌 지역도 있다.
        let weekday = (calendar.firstWeekday - 1 + columnIndex) % 7 + 1
        switch weekday {
        case 1: return TodoCalendarPalette.sunday
        case 7: return TodoCalendarPalette.saturday
        default: return PopoverChrome.inkTertiary
        }
    }

    private func dayInk(_ date: Date) -> Color {
        switch calendar.component(.weekday, from: date) {
        case 1: return TodoCalendarPalette.sunday.opacity(0.85)
        case 7: return TodoCalendarPalette.saturday.opacity(0.85)
        default: return PopoverChrome.inkSecondary
        }
    }
}

/// 고른 칸을 표시하는 색.
///
/// 강조색을 꽉 채우면 카드 하나에 주황 덩어리가 대여섯 개 생겨 어디가 중요한지 알 수 없다.
/// **옅게 깔고 테두리로 또렷하게** 한다 — 글자는 평소 색 그대로라 읽기도 편하다.
/// 강조색 자체는 사용자가 고르는 값이므로 색을 새로 적지 않고 투명도만 준다.
@MainActor
enum TodoPickPalette {
    static var fill: Color { PopoverChrome.accent.opacity(0.20) }
    static var stroke: Color { PopoverChrome.accent.opacity(0.5) }
    static var ink: Color { PopoverChrome.ink }
    static var inkSoft: Color { PopoverChrome.accent }
}

/// 달력에서만 쓰는 요일 색.
enum TodoCalendarPalette {
    static let sunday = Color(red: 0.78, green: 0.35, blue: 0.30)
    static let saturday = Color(red: 0.33, green: 0.47, blue: 0.72)
}
