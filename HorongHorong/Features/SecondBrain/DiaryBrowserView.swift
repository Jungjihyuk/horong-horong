import SwiftUI
import SwiftData

struct DiaryBrowserView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DiaryEntry.day, order: .reverse) private var entries: [DiaryEntry]
    @State private var visibleMonth: Date = Calendar.current.startOfDay(for: Date())
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var bodyDraft = ""
    @State private var editingEntry: DiaryEntry?
    @State private var saveTask: Task<Void, Never>?
    @State private var sleepTask: Task<Void, Never>?
    @State private var isPullingSleep = false

    private var calendar: Calendar { Calendar.current }

    private var entryMap: [Date: DiaryEntry] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.day, $0) })
    }

    private var selectedEntry: DiaryEntry? {
        let day = calendar.startOfDay(for: selectedDay)
        if let editingEntry, calendar.isDate(editingEntry.day, inSameDayAs: day) {
            return editingEntry
        }
        return entryMap[day]
    }

    var body: some View {
        HStack(spacing: 0) {
            calendarPane
            Divider().overlay(PopoverChrome.divider)
            editorPane
        }
        .onAppear {
            loadDraft()
            pullSleepIfNeeded()
        }
        .onChange(of: selectedDay) { _, _ in
            flush()
            loadDraft()
            pullSleepIfNeeded()
        }
        .onDisappear { flush() }
    }

    private var calendarPane: some View {
        let month = calendar.dateComponents([.year, .month], from: visibleMonth)
        let first = calendar.date(from: month) ?? visibleMonth
        let daysInMonth = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let pad = calendar.component(.weekday, from: first) - 1
        let cells: [Int?] = Array(repeating: nil, count: pad) + Array(1...daysInMonth)
        let today = calendar.startOfDay(for: Date())
        let weekdays = ["일", "월", "화", "수", "목", "금", "토"]

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { shiftMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                Spacer()
                Text(monthTitle)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                Spacer()
                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(PopoverChrome.inkSecondary)
            .padding(.horizontal, 16)
            .padding(.top, 18)

            HStack {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { index, name in
                    Text(name)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(index == 0 ? .red.opacity(0.7) : PopoverChrome.inkTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 10)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        let date = calendar.date(byAdding: .day, value: day - 1, to: first)
                            .map { calendar.startOfDay(for: $0) } ?? today
                        let entry = entryMap[date]
                        Button {
                            selectedDay = date
                            visibleMonth = date
                        } label: {
                            VStack(spacing: 2) {
                                Text("\(day)")
                                    .font(.system(size: 12, weight: date == selectedDay ? .bold : .medium, design: .rounded))
                                Text(entry?.mood?.emoji ?? " ")
                                    .font(.system(size: 11))
                                    .frame(height: 14)
                            }
                            .foregroundStyle(date == today ? PopoverChrome.accent : PopoverChrome.ink)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(date == selectedDay ? PopoverChrome.accentSoft.opacity(0.7) : .clear)
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
                selectedDay = today
                visibleMonth = today
            }
            .controlSize(.small)
            .padding(.horizontal, 16)

            let written = entries.filter { calendar.isDate($0.day, equalTo: first, toGranularity: .month) }.count
            Text("이 달에 \(written)일 기록")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
                .padding(.horizontal, 16)

            Spacer()
        }
        .frame(width: 280)
        .background(PopoverChrome.surfaceAlt)
    }

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(dayTitle)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.ink)
                    if calendar.isDateInToday(selectedDay) {
                        Text("오늘")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(PopoverChrome.accentInk)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(PopoverChrome.accent, in: Capsule())
                    }
                }
                Text(selectedEntry == nil ? "아직 비어 있어요" : "기록됨")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            HStack(alignment: .top, spacing: 24) {
                metaGroup(title: "기분") {
                    HStack(spacing: 6) {
                        ForEach(DiaryMood.allCases) { mood in
                            Button {
                                upsert { $0.mood = $0.mood == mood ? nil : mood }
                            } label: {
                                Text(mood.emoji)
                                    .font(.system(size: 18))
                                    .frame(width: 34, height: 34)
                                    .background(
                                        selectedEntry?.mood == mood ? PopoverChrome.accentSoft : PopoverChrome.card,
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
                            if HealthSleepStore.shared.isAvailable {
                                Button(isPullingSleep ? "가져오는 중…" : "건강 앱에서 가져오기") {
                                    pullSleep(force: true)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(PopoverChrome.accent)
                                .disabled(isPullingSleep)
                            }
                        }
                    }
                }
                metaGroup(title: "스트레스") {
                    HStack(spacing: 6) {
                        ForEach(1...5, id: \.self) { value in
                            Button {
                                upsert { $0.stress = $0.stress == value ? nil : value }
                            } label: {
                                Text("\(value)")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .frame(width: 28, height: 28)
                                    .foregroundStyle(selectedEntry?.stress == value ? PopoverChrome.accentInk : PopoverChrome.inkSecondary)
                                    .background(
                                        selectedEntry?.stress == value ? PopoverChrome.accent : PopoverChrome.card,
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

            Divider().overlay(PopoverChrome.divider)

            TextEditor(text: $bodyDraft)
                .font(.system(size: 15, design: .rounded))
                .scrollContentBackground(.hidden)
                .padding(16)
                .onChange(of: bodyDraft) { _, newValue in
                    upsert { $0.body = newValue }
                }

            HStack {
                Text("\(bodyDraft.count)자 · 자동 저장")
                Spacer()
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(PopoverChrome.inkTertiary)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(PopoverChrome.surface)
    }

    private func metaGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
            content()
        }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월"
        return formatter.string(from: visibleMonth)
    }

    private var dayTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월 d일 EEEE"
        return formatter.string(from: selectedDay)
    }

    private var sleepLabel: String {
        if let hours = selectedEntry?.sleepHours {
            return String(format: "%.1f시간", hours)
        }
        return "기록 없음"
    }

    private var sleepSourceCaption: String {
        switch selectedEntry?.sleepSource {
        case .healthKit:
            return "건강 앱 기록 · 직접 고쳐도 됩니다"
        case .manual:
            return "직접 입력함"
        case nil:
            return HealthSleepStore.shared.isAvailable
                ? "건강 앱에 없으면 직접 입력하세요"
                : "이 Mac에서는 건강 앱을 쓸 수 없어 직접 입력하세요"
        }
    }

    private var sleepBinding: Binding<Double> {
        Binding(
            get: { selectedEntry?.sleepHours ?? 7 },
            set: { value in
                upsert {
                    $0.sleepHours = value
                    $0.sleepSource = .manual
                }
            }
        )
    }

    private func shiftMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: visibleMonth) {
            visibleMonth = next
        }
    }

    private func loadDraft() {
        let day = calendar.startOfDay(for: selectedDay)
        editingEntry = entryMap[day]
        bodyDraft = editingEntry?.body ?? ""
    }

    private func pullSleepIfNeeded() {
        if selectedEntry?.sleepSource == .manual { return }
        pullSleep(force: false)
    }

    private func pullSleep(force: Bool) {
        sleepTask?.cancel()
        isPullingSleep = true
        let day = calendar.startOfDay(for: selectedDay)
        sleepTask = Task { @MainActor in
            defer { isPullingSleep = false }
            let hours = await HealthSleepStore.shared.sleepHours(on: day, calendar: calendar)
            guard !Task.isCancelled, let hours else { return }
            if !force, selectedEntry?.sleepSource == .manual { return }
            upsert {
                if !force, $0.sleepSource == .manual { return }
                $0.sleepHours = hours
                $0.sleepSource = .healthKit
            }
        }
    }

    private func upsert(_ mutate: (DiaryEntry) -> Void) {
        let day = calendar.startOfDay(for: selectedDay)
        let entry: DiaryEntry
        if let editingEntry, calendar.isDate(editingEntry.day, inSameDayAs: day) {
            entry = editingEntry
        } else if let existing = entryMap[day] {
            entry = existing
            editingEntry = existing
        } else {
            entry = DiaryEntry(day: day, calendar: calendar)
            modelContext.insert(entry)
            editingEntry = entry
        }
        mutate(entry)
        entry.updatedAt = Date()
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            try? modelContext.save()
        }
    }

    private func flush() {
        saveTask?.cancel()
        saveTask = nil
        try? modelContext.save()
    }
}
