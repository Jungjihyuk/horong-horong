import SwiftUI

/// 편집기 위에 붙는 «기분 · 수면» 입력 줄.
///
/// **고르고 나면 접힌다.** 선택지가 계속 펼쳐져 있으면 본문이 아래로 밀리고 시선도 그쪽에 남는다.
/// 다 적은 뒤에는 요약 한 줄만 남겨 글쓰기에 자리를 내준다.
struct DiaryMetaRow: View {
    let day: Date
    let entry: DiaryDay?
    let axis: DiarySleepAxis
    let calendar: Calendar
    let onSelectMood: (DiaryMood, DiaryMoodSlot) -> Void
    let onSelectIntensity: (Int, DiaryMoodSlot) -> Void
    let onSelectCause: (DiaryCause, DiaryMoodSlot) -> Void
    let onCommitSleep: (Date, Date) -> Void
    let onClearSleep: () -> Void

    /// 한 번에 한 칸만 펼친다. 둘 다 펼치면 입력 줄이 본문보다 커진다.
    @State private var expanded: Section?
    /// 지금 적고 있는 칸. 오전 → 오후 → 하루 중 하나이며 순서 강제는 없다.
    @State private var activeSlot: DiaryMoodSlot = .wholeDay
    @State private var moodPopoverGroup: DiaryMoodGroup?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            moodSection
            sleepSection
        }
        .onChange(of: day) { _, _ in
            expanded = nil
            moodPopoverGroup = nil
            activeSlot = .wholeDay
        }
    }

    // MARK: - 기분 · 강도 · 원인

    private var moodSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            header(
                icon: "face.smiling",
                summary: moodSummary,
                isFilled: !(entry?.moodRecords.isEmpty ?? true),
                section: .mood
            )

            if expanded == .mood {
                VStack(alignment: .leading, spacing: 9) {
                    slotTabs
                    FlowLayout(spacing: 6) {
                        ForEach(DiaryMoodGroup.allCases) { group in
                            moodChip(group)
                        }
                    }

                    // 강도와 원인은 감정을 고른 뒤에만 나타난다. «얼마나 강했나» 도 «무엇 때문인가» 도
                    // 무엇이었는지 정한 다음에야 물을 수 있는 질문이다.
                    if activeRecord != nil {
                        intensityRow
                        causeRow
                    }
                }
                .padding(.leading, 2)
            }
        }
        .animation(.easeOut(duration: 0.18), value: expanded)
        .animation(.easeOut(duration: 0.18), value: activeSlot)
        .animation(.easeOut(duration: 0.18), value: activeRecord)
    }

    private var slotTabs: some View {
        HStack(spacing: 3) {
            ForEach(DiaryMoodSlot.allCases) { slot in
                let record = entry?.record(slot)
                let isActive = activeSlot == slot
                Button { activeSlot = slot } label: {
                    HStack(spacing: 4) {
                        Text(slot.title)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                        // 적힌 칸에는 이모지가 붙어 «어디를 아직 안 적었는지» 가 한눈에 보인다.
                        Text(record?.mood.emoji ?? "")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(isActive ? PopoverChrome.selectionInk : PopoverChrome.inkSecondary)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(
                        isActive ? PopoverChrome.selectionFill : .clear,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
        }
        .padding(2)
        .background(PopoverChrome.surfaceAlt, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func moodChip(_ group: DiaryMoodGroup) -> some View {
        let isSelected = activeRecord?.mood.group == group
        return Button { moodPopoverGroup = group } label: {
            HStack(spacing: 5) {
                Text(group.emoji).font(.system(size: 13))
                Text(group.shortTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(isSelected ? PopoverChrome.selectionInk : PopoverChrome.inkSecondary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                isSelected ? PopoverChrome.selectionFill : PopoverChrome.card,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSelected ? PopoverChrome.accent.opacity(0.5) : PopoverChrome.border, lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
        .help("\(group.title) · \(group.subtitle)")
        .accessibilityLabel("\(group.title), \(group.subtitle)")
        // 칩마다 «지금 열린 것이 나인가» 를 보는 바인딩을 준다. 일곱 칩이 같은 옵셔널을
        // `.popover(item:)` 으로 공유하면 팝오버가 일곱 개 만들어져 엉뚱한 칩에 붙는다.
        .popover(
            isPresented: Binding(
                get: { moodPopoverGroup == group },
                set: { if !$0 { moodPopoverGroup = nil } }
            )
        ) {
            DiaryMoodPickerPopover(
                group: group,
                selectedMood: activeRecord?.mood,
                onSelect: { mood in
                    moodPopoverGroup = nil
                    onSelectMood(mood, activeSlot)
                }
            )
        }
    }

    private var intensityRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("얼마나 강했나요?")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
            HStack(spacing: 5) {
                ForEach(Array(DiaryMoodIntensity.range), id: \.self) { value in
                    let isSelected = activeRecord?.intensity == value
                    Button { onSelectIntensity(value, activeSlot) } label: {
                        Text("\(value)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(isSelected ? PopoverChrome.selectionInk : PopoverChrome.inkSecondary)
                            .frame(width: 32, height: 28)
                            .background(
                                isSelected ? PopoverChrome.selectionFill : PopoverChrome.card,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(PopoverChrome.border, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(DiaryMoodIntensity.title(value))
                    .accessibilityLabel(DiaryMoodIntensity.title(value))
                }
                Text(activeRecord?.intensity.map(DiaryMoodIntensity.title) ?? "안 적어도 괜찮아요")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .padding(.leading, 2)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var causeRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("무엇 때문이었나요?")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
            FlowLayout(spacing: 5) {
                ForEach(DiaryCause.allCases) { cause in
                    causeChip(cause)
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func causeChip(_ cause: DiaryCause) -> some View {
        let isSelected = activeRecord?.cause == cause
        return Button { selectCause(cause) } label: {
            Text(cause.rawValue)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? PopoverChrome.selectionInk : PopoverChrome.inkSecondary)
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(
                    isSelected ? PopoverChrome.selectionFill : PopoverChrome.card,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(PopoverChrome.border, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 수면

    private var sleepSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            header(
                icon: "moon.zzz",
                summary: sleepSummary,
                isFilled: sleepWindow != nil,
                section: .sleep
            )

            if expanded == .sleep {
                DiarySleepTimeline(
                    day: day,
                    window: sleepWindow,
                    axis: axis,
                    calendar: calendar,
                    // 손잡이를 놓을 때는 값만 남긴다. 두 손잡이를 번갈아 잡는 동안 접히면
                    // 나머지 하나를 만지려고 매번 다시 펴야 한다.
                    onCommit: { start, end in onCommitSleep(start, end) },
                    onFinish: collapse,
                    onClear: onClearSleep
                )
                .padding(.leading, 2)
                .padding(.trailing, 4)
            }
        }
        .animation(.easeOut(duration: 0.18), value: expanded)
    }

    /// 시각이 있으면 그것을, 길이만 있는 옛 기록은 기상 시각 기준으로 되살려 보여 준다.
    private var sleepWindow: DiarySleepWindow? {
        if let recorded = entry?.sleepWindow { return recorded }
        guard let hours = entry?.sleepHours else { return nil }
        return DiarySleepWindowPolicy.window(hours: hours, day: day, calendar: calendar)
    }

    // MARK: - 공통

    private enum Section: Hashable { case mood, sleep }

    private var activeRecord: DiaryMoodRecord? { entry?.record(activeSlot) }

    private func header(icon: String, summary: String, isFilled: Bool, section: Section) -> some View {
        Button { toggle(section) } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isFilled ? PopoverChrome.accent : PopoverChrome.inkTertiary)
                Text(summary)
                    .font(.system(size: 12, weight: isFilled ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(isFilled ? PopoverChrome.ink : PopoverChrome.inkTertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: expanded == section ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(PopoverChrome.border, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 적은 칸만 이어 붙인다. 접힌 줄만 보고도 «오전은 적었고 오후는 비었다» 를 알 수 있어야
    /// 다시 열어 이어 적을 마음이 생긴다.
    private var moodSummary: String {
        let records = entry?.moodRecords ?? []
        guard !records.isEmpty else { return "오늘 어떤 마음이었나요?" }
        return records
            .map { "\($0.slot.title) \($0.mood.emoji) \($0.mood.rawValue)" }
            .joined(separator: " · ")
    }

    private var sleepSummary: String {
        guard let window = sleepWindow else { return "몇 시부터 몇 시까지 잤나요?" }
        return DiarySleepText.range(window)
    }

    private func toggle(_ section: Section) {
        withAnimation(.easeOut(duration: 0.18)) {
            expanded = expanded == section ? nil : section
        }
        // 열 때는 아직 안 적은 칸으로 데려간다 — 이미 적은 칸을 다시 보여 주면 덮어쓰기 쉽다.
        if expanded == .mood { activeSlot = firstEmptySlot }
    }

    private var firstEmptySlot: DiaryMoodSlot {
        DiaryMoodSlot.allCases.first { entry?.record($0) == nil } ?? .wholeDay
    }

    private func collapse() {
        withAnimation(.easeOut(duration: 0.18)) { expanded = nil }
    }

    /// 원인까지 골랐으면 이 칸은 끝났다 — 접어서 본문에 자리를 돌려준다.
    /// 같은 원인을 다시 눌러 해제한 경우는 아직 고르는 중이므로 펼친 채로 둔다.
    private func selectCause(_ cause: DiaryCause) {
        let isClearing = activeRecord?.cause == cause
        onSelectCause(cause, activeSlot)
        guard !isClearing else { return }
        collapse()
    }
}

/// 감정 영역 하나 안의 세부 감정을 고르는 팝오버.
struct DiaryMoodPickerPopover: View {
    let group: DiaryMoodGroup
    let selectedMood: DiaryMood?
    let onSelect: (DiaryMood) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(group.title)
                .font(.headline)
                .foregroundStyle(PopoverChrome.ink)
            Text(group.subtitle)
                .font(.caption)
                .foregroundStyle(PopoverChrome.inkSecondary)
            FlowLayout(spacing: 5) {
                ForEach(group.moods) { mood in
                    Button { onSelect(mood) } label: {
                        HStack(spacing: 4) {
                            Text(mood.emoji)
                            Text(mood.rawValue)
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(selectedMood == mood ? PopoverChrome.selectionInk : PopoverChrome.inkSecondary)
                        .padding(.horizontal, 9)
                        .frame(height: 29)
                        .background(
                            selectedMood == mood ? PopoverChrome.selectionFill : PopoverChrome.card,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
        .background(PopoverChrome.surface)
    }
}
