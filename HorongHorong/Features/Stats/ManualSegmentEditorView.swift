import SwiftUI
import SwiftData

/// 특정 날짜의 `AppUsageSegment` 와 완료된 포모도로 기록을 수동으로 추가/편집/삭제하는 시트.
/// 편집은 각 행에 attached 된 popover, 추가는 별도 sheet 로 띄운다.
struct ManualSegmentEditorView: View {
    let date: Date
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var segments: [AppUsageSegment] = []
    @State private var focusSessions: [FocusSession] = []
    @State private var showAddSheet: Bool = false
    @State private var editError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if segments.isEmpty, focusSessions.isEmpty {
                emptyView
            } else {
                editorContent
            }
        }
        .frame(minWidth: 560, minHeight: 440)
        .onAppear(perform: load)
        .alert("저장할 수 없습니다", isPresented: Binding(
            get: { editError != nil },
            set: { if !$0 { editError = nil } }
        )) {
            Button("확인", role: .cancel) { editError = nil }
        } message: {
            Text(editError ?? "")
        }
        .sheet(isPresented: $showAddSheet) {
            SegmentFormSheet(
                title: "세그먼트 추가",
                initial: defaultInitial(),
                onSave: { draft in
                    if addSegment(from: draft) {
                        showAddSheet = false
                        load()
                    }
                },
                onCancel: { showAddSheet = false }
            )
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateHeaderText)
                    .font(.headline)
                Text("포모도로와 앱 실행 기록을 편집해도 차트가 자동으로 갱신됩니다")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                showAddSheet = true
            } label: {
                Label("추가", systemImage: "plus")
            }
            .controlSize(.regular)
            .buttonStyle(.borderedProminent)

            Button("닫기") { dismiss() }
                .controlSize(.regular)
        }
        .padding(14)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.badge.questionmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("이 날짜의 세그먼트 기록이 없습니다")
                .foregroundStyle(.secondary)
            Text("상단의 '추가' 로 수동 세그먼트를 만들 수 있어요")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editorContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !focusSessions.isEmpty {
                    sectionTitle("포모도로 기록")
                    ForEach(focusSessions, id: \.id) { session in
                        PomodoroEditRowView(
                            session: session,
                            childSegments: childSegments(for: session),
                            onSaveEdit: { draft in
                                if applyPomodoroEdit(on: session, draft: draft) {
                                    load()
                                    return true
                                }
                                return false
                            },
                            onDelete: { deletePomodoro(session); load() }
                        )
                        Divider()
                    }
                }

                if !segments.isEmpty {
                    sectionTitle("앱 실행 기록")
                    ForEach(segments, id: \.id) { seg in
                        SegmentRowView(
                            segment: seg,
                            onSaveEdit: { draft in
                                if applyEdit(on: seg, draft: draft) {
                                    load()
                                    return true
                                }
                                return false
                            },
                            onDelete: { delete(seg); load() }
                        )
                        Divider()
                    }
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    // MARK: - Data

    private func load() {
        let dayStart = Calendar.current.startOfDay(for: date)
        guard let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) else {
            segments = []
            focusSessions = []
            return
        }
        let descriptor = FetchDescriptor<AppUsageSegment>(
            predicate: #Predicate { $0.startTime < dayEnd && $0.endTime > dayStart },
            sortBy: [SortDescriptor(\.startTime)]
        )
        segments = (try? modelContext.fetch(descriptor)) ?? []

        let bufferStart = Calendar.current.date(byAdding: .hour, value: -4, to: dayStart) ?? dayStart
        let sessionDescriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.startedAt >= bufferStart && $0.startedAt < dayEnd },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        focusSessions = ((try? modelContext.fetch(sessionDescriptor)) ?? []).filter {
            guard isCompletedPomodoro($0), let end = focusEnd(for: $0) else { return false }
            return $0.startedAt < dayEnd && end > dayStart
        }
    }

    private func addSegment(from draft: SegmentDraft) -> Bool {
        guard validatePomodoroChildLimit(existing: nil, draft: draft) else {
            return false
        }

        let bundleId = "manual.\(draft.appName.lowercased().replacingOccurrences(of: " ", with: "-"))"
        let seg = AppUsageSegment(
            appName: draft.appName,
            bundleIdentifier: bundleId,
            category: draft.category,
            startTime: draft.start,
            endTime: draft.end,
            isManual: true
        )
        modelContext.insert(seg)
        syncRecord(
            bundleId: bundleId,
            appName: draft.appName,
            category: draft.category,
            date: draft.start,
            deltaSeconds: seg.durationSeconds
        )
        try? modelContext.save()
        return true
    }

    private func applyEdit(on seg: AppUsageSegment, draft: SegmentDraft) -> Bool {
        guard validatePomodoroChildLimit(existing: seg, draft: draft) else {
            return false
        }

        let oldBundle = seg.bundleIdentifier
        let oldApp = seg.appName
        let oldCat = seg.category
        let oldDate = seg.startTime
        let oldDuration = seg.durationSeconds

        let newBundle: String
        if seg.isManual {
            newBundle = "manual.\(draft.appName.lowercased().replacingOccurrences(of: " ", with: "-"))"
        } else {
            newBundle = oldBundle
        }

        seg.appName = draft.appName
        seg.bundleIdentifier = newBundle
        seg.category = draft.category
        seg.startTime = draft.start
        seg.endTime = draft.end

        // Record 재동기화: 기존에 반영된 만큼 빼고, 새 값으로 더한다.
        syncRecord(bundleId: oldBundle, appName: oldApp, category: oldCat, date: oldDate, deltaSeconds: -oldDuration)
        syncRecord(
            bundleId: newBundle,
            appName: draft.appName,
            category: draft.category,
            date: draft.start,
            deltaSeconds: seg.durationSeconds
        )
        try? modelContext.save()
        return true
    }

    private func applyPomodoroEdit(on session: FocusSession, draft: PomodoroDraft) -> Bool {
        guard validatePomodoroEdit(session: session, draft: draft) else {
            return false
        }
        guard let oldEnd = focusEnd(for: session) else {
            editError = "종료 시간이 없는 포모도로 기록은 수정할 수 없습니다."
            return false
        }

        let oldCategory = session.category ?? Constants.defaultFocusCategory
        let oldStart = session.startedAt
        let oldDuration = Int(oldEnd.timeIntervalSince(oldStart))
        let newDuration = Int(draft.end.timeIntervalSince(draft.start))

        session.category = draft.category
        session.startedAt = draft.start
        session.endedAt = draft.end
        session.focusMinutes = max(1, Int(ceil(draft.end.timeIntervalSince(draft.start) / 60)))
        session.completed = true

        syncFocusRecord(category: oldCategory, date: oldStart, deltaSeconds: -oldDuration)
        syncFocusRecord(category: draft.category, date: draft.start, deltaSeconds: newDuration)
        try? modelContext.save()
        return true
    }

    private func delete(_ seg: AppUsageSegment) {
        let bundleId = seg.bundleIdentifier
        let appName = seg.appName
        let category = seg.category
        let date = seg.startTime
        let duration = seg.durationSeconds
        modelContext.delete(seg)
        syncRecord(bundleId: bundleId, appName: appName, category: category, date: date, deltaSeconds: -duration)
        try? modelContext.save()
    }

    private func deletePomodoro(_ session: FocusSession) {
        guard let end = focusEnd(for: session) else { return }
        let start = session.startedAt

        for segment in segments {
            removeSegmentOverlap(segment, from: start, to: end)
        }

        deleteFocusRecord(for: session)
        modelContext.delete(session)
        try? modelContext.save()
    }

    private func removeSegmentOverlap(_ segment: AppUsageSegment, from start: Date, to end: Date) {
        let overlapStart = max(segment.startTime, start)
        let overlapEnd = min(segment.endTime, end)
        guard overlapEnd > overlapStart else { return }

        let removedSeconds = Int(overlapEnd.timeIntervalSince(overlapStart))
        let originalStart = segment.startTime
        let originalEnd = segment.endTime
        let bundleId = segment.bundleIdentifier
        let appName = segment.appName
        let category = segment.category
        let isManual = segment.isManual

        if overlapStart <= originalStart, overlapEnd >= originalEnd {
            modelContext.delete(segment)
        } else if overlapStart <= originalStart {
            segment.startTime = overlapEnd
        } else if overlapEnd >= originalEnd {
            segment.endTime = overlapStart
        } else {
            segment.endTime = overlapStart
            let tail = AppUsageSegment(
                appName: appName,
                bundleIdentifier: bundleId,
                category: category,
                startTime: overlapEnd,
                endTime: originalEnd,
                isManual: isManual
            )
            modelContext.insert(tail)
        }

        syncRecord(
            bundleId: bundleId,
            appName: appName,
            category: category,
            date: originalStart,
            deltaSeconds: -removedSeconds
        )
    }

    private func deleteFocusRecord(for session: FocusSession) {
        let category = session.category ?? Constants.defaultFocusCategory
        let bundleId = Constants.focusSessionBundleId(for: category)
        guard let end = focusEnd(for: session) else { return }
        let duration = Int(end.timeIntervalSince(session.startedAt))
        syncRecord(
            bundleId: bundleId,
            appName: Constants.focusSessionAppName,
            category: category,
            date: session.startedAt,
            deltaSeconds: -duration
        )
    }

    private func childSegments(for session: FocusSession) -> [AppUsageSegment] {
        guard let end = focusEnd(for: session) else { return [] }
        return segments.filter { overlaps($0.startTime, $0.endTime, session.startedAt, end) }
    }

    private func validatePomodoroChildLimit(existing: AppUsageSegment?, draft: SegmentDraft) -> Bool {
        let affectedSessions = focusSessions.filter { session in
            guard let end = focusEnd(for: session) else { return false }
            let overlapsDraft = overlaps(draft.start, draft.end, session.startedAt, end)
            let overlapsExisting = existing.map { overlaps($0.startTime, $0.endTime, session.startedAt, end) } ?? false
            return overlapsDraft || overlapsExisting
        }

        for session in affectedSessions {
            guard let end = focusEnd(for: session) else { continue }
            let sessionSeconds = Int(end.timeIntervalSince(session.startedAt))
            var childSeconds = 0

            for segment in segments {
                if let existing, segment.id == existing.id { continue }
                childSeconds += overlapSeconds(segment.startTime, segment.endTime, session.startedAt, end)
            }
            childSeconds += overlapSeconds(draft.start, draft.end, session.startedAt, end)

            if childSeconds > sessionSeconds {
                editError = "포모도로 '\(session.category ?? Constants.defaultFocusCategory)'의 하위 앱 기록 합계가 집중 시간 \(formatDuration(sessionSeconds))을 넘을 수 없습니다."
                return false
            }
        }

        return true
    }

    private func validatePomodoroEdit(session: FocusSession, draft: PomodoroDraft) -> Bool {
        guard draft.isValid else {
            editError = "포모도로 종료 시간은 시작 시간보다 늦어야 합니다."
            return false
        }

        if let overlapping = focusSessions.first(where: { other in
            guard other.id != session.id, let otherEnd = focusEnd(for: other) else { return false }
            return overlaps(draft.start, draft.end, other.startedAt, otherEnd)
        }) {
            editError = "다른 포모도로 '\(overlapping.category ?? Constants.defaultFocusCategory)' 기록과 시간이 겹칩니다."
            return false
        }

        let sessionSeconds = Int(draft.end.timeIntervalSince(draft.start))
        let childSeconds = segments.reduce(0) { total, segment in
            total + overlapSeconds(segment.startTime, segment.endTime, draft.start, draft.end)
        }
        if childSeconds > sessionSeconds {
            editError = "하위 앱 기록 합계 \(formatDuration(childSeconds))가 포모도로 시간 \(formatDuration(sessionSeconds))을 넘을 수 없습니다."
            return false
        }

        return true
    }

    private func isCompletedPomodoro(_ session: FocusSession) -> Bool {
        guard let endedAt = session.endedAt else { return false }
        let expectedSeconds = max(0, session.focusMinutes) * 60
        guard expectedSeconds > 0 else { return false }
        return session.completed || endedAt.timeIntervalSince(session.startedAt) >= TimeInterval(expectedSeconds)
    }

    private func focusEnd(for session: FocusSession) -> Date? {
        guard let endedAt = session.endedAt else { return nil }
        let expectedEnd = session.startedAt.addingTimeInterval(TimeInterval(max(0, session.focusMinutes) * 60))
        return min(endedAt, expectedEnd)
    }

    private func overlaps(_ lhsStart: Date, _ lhsEnd: Date, _ rhsStart: Date, _ rhsEnd: Date) -> Bool {
        lhsStart < rhsEnd && lhsEnd > rhsStart
    }

    private func overlapSeconds(_ lhsStart: Date, _ lhsEnd: Date, _ rhsStart: Date, _ rhsEnd: Date) -> Int {
        let start = max(lhsStart, rhsStart)
        let end = min(lhsEnd, rhsEnd)
        guard end > start else { return 0 }
        return Int(end.timeIntervalSince(start))
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }

    private func syncFocusRecord(category: String, date: Date, deltaSeconds: Int) {
        syncRecord(
            bundleId: Constants.focusSessionBundleId(for: category),
            appName: Constants.focusSessionAppName,
            category: category,
            date: date,
            deltaSeconds: deltaSeconds
        )
    }

    /// AppUsageRecord 에 증감분을 반영한다. 없으면 deltaSeconds > 0 일 때만 새로 생성.
    private func syncRecord(bundleId: String, appName: String, category: String, date: Date, deltaSeconds: Int) {
        guard deltaSeconds != 0 else { return }
        let dayStart = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<AppUsageRecord>(
            predicate: #Predicate { $0.bundleIdentifier == bundleId && $0.date == dayStart }
        )
        if let record = try? modelContext.fetch(descriptor).first {
            let newTotal = max(0, record.durationSeconds + deltaSeconds)
            if newTotal == 0 {
                modelContext.delete(record)
            } else {
                record.durationSeconds = newTotal
                if record.category != category { record.category = category }
            }
        } else if deltaSeconds > 0 {
            let record = AppUsageRecord(
                appName: appName,
                bundleIdentifier: bundleId,
                category: category,
                date: dayStart
            )
            record.durationSeconds = deltaSeconds
            modelContext.insert(record)
        }
    }

    private func defaultInitial() -> SegmentDraft {
        // 기본: 해당 날짜의 14:00~15:00, 카테고리는 첫 카테고리, 앱은 빈 문자열
        let cal = Calendar.current
        let start = cal.date(bySettingHour: 14, minute: 0, second: 0, of: date) ?? date
        let end = cal.date(byAdding: .hour, value: 1, to: start) ?? start
        return SegmentDraft(
            appName: "",
            category: Constants.allCategories.first ?? Constants.categoryName("기타"),
            start: start,
            end: end
        )
    }

    private var dateHeaderText: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "yyyy년 M월 d일 (E)"
        return fmt.string(from: date)
    }
}

// MARK: - Row

private struct SegmentRowView: View {
    let segment: AppUsageSegment
    let onSaveEdit: (SegmentDraft) -> Bool
    let onDelete: () -> Void

    @State private var showEditPopover: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(Constants.categoryEmoji(for: segment.category))
                .font(.title3)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(segment.appName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    if segment.isManual {
                        Text("수동")
                            .font(.caption2.bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(.orange)
                    }
                }
                Text(detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            Button {
                showEditPopover = true
            } label: {
                Image(systemName: "pencil")
                    .font(.callout)
            }
            .buttonStyle(.borderless)
            .help("편집")
            .popover(isPresented: $showEditPopover, arrowEdge: .trailing) {
                SegmentFormPopover(
                    title: "세그먼트 편집",
                    initial: SegmentDraft(
                        appName: segment.appName,
                        category: segment.category,
                        start: segment.startTime,
                        end: segment.endTime
                    ),
                    onSave: { draft in
                        if onSaveEdit(draft) {
                            showEditPopover = false
                        }
                    },
                    onCancel: { showEditPopover = false }
                )
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help("삭제")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var detailLine: String {
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        let s = timeFmt.string(from: segment.startTime)
        let e = timeFmt.string(from: segment.endTime)
        let dur = segment.durationSeconds
        let h = dur / 3600
        let m = (dur % 3600) / 60
        let durText = h > 0 ? "\(h)h \(m)m" : "\(m)m"
        return "\(s) – \(e) · \(segment.category) · \(durText)"
    }
}

private struct PomodoroEditRowView: View {
    let session: FocusSession
    let childSegments: [AppUsageSegment]
    let onSaveEdit: (PomodoroDraft) -> Bool
    let onDelete: () -> Void

    @State private var showEditPopover: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(Constants.categoryEmoji(for: category))
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(category)
                        .font(.callout.weight(.medium))
                    Text(timeRange)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                if childSegments.isEmpty {
                    Text("하위 앱 기록 없음")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("하위 앱 \(childSegments.count)개 · \(formatDuration(childTotalSeconds))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(formatDuration(durationSeconds))
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button {
                showEditPopover = true
            } label: {
                Image(systemName: "pencil")
                    .font(.callout)
            }
            .buttonStyle(.borderless)
            .help("포모도로 기록 편집")
            .popover(isPresented: $showEditPopover, arrowEdge: .trailing) {
                PomodoroFormPopover(
                    title: "포모도로 편집",
                    initial: PomodoroDraft(
                        category: category,
                        start: session.startedAt,
                        end: focusEnd
                    ),
                    onSave: { draft in
                        if onSaveEdit(draft) {
                            showEditPopover = false
                        }
                    },
                    onCancel: { showEditPopover = false }
                )
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help("포모도로 기록과 하위 앱 기록 삭제")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var category: String {
        session.category ?? Constants.defaultFocusCategory
    }

    private var focusEnd: Date {
        guard let endedAt = session.endedAt else { return session.startedAt }
        let expectedEnd = session.startedAt.addingTimeInterval(TimeInterval(max(0, session.focusMinutes) * 60))
        return min(endedAt, expectedEnd)
    }

    private var durationSeconds: Int {
        max(0, Int(focusEnd.timeIntervalSince(session.startedAt)))
    }

    private var childTotalSeconds: Int {
        childSegments.reduce(0) { total, segment in
            let start = max(segment.startTime, session.startedAt)
            let end = min(segment.endTime, focusEnd)
            guard end > start else { return total }
            return total + Int(end.timeIntervalSince(start))
        }
    }

    private var timeRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: session.startedAt)) – \(formatter.string(from: focusEnd))"
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }
}

// MARK: - Form types

struct PomodoroDraft {
    var category: String
    var start: Date
    var end: Date

    var isValid: Bool {
        !category.trimmingCharacters(in: .whitespaces).isEmpty && end > start
    }
}

struct SegmentDraft {
    var appName: String
    var category: String
    var start: Date
    var end: Date

    var isValid: Bool {
        !appName.trimmingCharacters(in: .whitespaces).isEmpty && end > start
    }
}

private struct PomodoroFormPopover: View {
    let title: String
    @State private var draft: PomodoroDraft
    let onSave: (PomodoroDraft) -> Void
    let onCancel: () -> Void

    init(title: String, initial: PomodoroDraft, onSave: @escaping (PomodoroDraft) -> Void, onCancel: @escaping () -> Void) {
        self.title = title
        self._draft = State(initialValue: initial)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        PomodoroFormBody(title: title, draft: $draft, onSave: onSave, onCancel: onCancel)
            .frame(width: 340)
            .padding(14)
    }
}

private struct PomodoroFormBody: View {
    let title: String
    @Binding var draft: PomodoroDraft
    let onSave: (PomodoroDraft) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            formGrid

            if draft.end <= draft.start {
                Text("⚠️ 시작 시간이 종료 시간보다 늦거나 같습니다")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("취소", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("저장") { onSave(draft) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.isValid)
            }
        }
    }

    private var formGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                Text("카테고리").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $draft.category) {
                    ForEach(Constants.allCategories, id: \.self) { cat in
                        Text("\(Constants.categoryEmoji(for: cat)) \(cat)").tag(cat)
                    }
                }
                .labelsHidden()
            }
            GridRow {
                Text("시작 시간").font(.caption).foregroundStyle(.secondary)
                DatePicker("", selection: $draft.start)
                    .datePickerStyle(.compact)
                    .labelsHidden()
            }
            GridRow {
                Text("종료 시간").font(.caption).foregroundStyle(.secondary)
                DatePicker("", selection: $draft.end)
                    .datePickerStyle(.compact)
                    .labelsHidden()
            }
        }
    }
}

/// Popover 안에 뜨는 컴팩트 편집 폼.
private struct SegmentFormPopover: View {
    let title: String
    @State private var draft: SegmentDraft
    let onSave: (SegmentDraft) -> Void
    let onCancel: () -> Void

    init(title: String, initial: SegmentDraft, onSave: @escaping (SegmentDraft) -> Void, onCancel: @escaping () -> Void) {
        self.title = title
        self._draft = State(initialValue: initial)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        SegmentFormBody(title: title, draft: $draft, onSave: onSave, onCancel: onCancel)
            .frame(width: 340)
            .padding(14)
    }
}

/// Sheet 로 뜨는 추가 폼 (popover 와 레이아웃 공유).
private struct SegmentFormSheet: View {
    let title: String
    @State private var draft: SegmentDraft
    let onSave: (SegmentDraft) -> Void
    let onCancel: () -> Void

    init(title: String, initial: SegmentDraft, onSave: @escaping (SegmentDraft) -> Void, onCancel: @escaping () -> Void) {
        self.title = title
        self._draft = State(initialValue: initial)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        SegmentFormBody(title: title, draft: $draft, onSave: onSave, onCancel: onCancel)
            .frame(minWidth: 380, minHeight: 260)
            .padding(18)
    }
}

private struct SegmentFormBody: View {
    let title: String
    @Binding var draft: SegmentDraft
    let onSave: (SegmentDraft) -> Void
    let onCancel: () -> Void
    @FocusState private var appFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            formGrid

            if draft.end <= draft.start {
                Text("⚠️ 시작 시간이 종료 시간보다 늦거나 같습니다")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("취소", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("저장") { onSave(draft) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.isValid)
            }
        }
        .onAppear { appFieldFocused = true }
    }

    private var formGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                Text("앱 이름").font(.caption).foregroundStyle(.secondary)
                TextField("예: 회의 메모", text: $draft.appName)
                    .textFieldStyle(.roundedBorder)
                    .focused($appFieldFocused)
            }
            GridRow {
                Text("카테고리").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $draft.category) {
                    ForEach(Constants.allCategories, id: \.self) { cat in
                        Text("\(Constants.categoryEmoji(for: cat)) \(cat)").tag(cat)
                    }
                }
                .labelsHidden()
            }
            GridRow {
                Text("시작 시간").font(.caption).foregroundStyle(.secondary)
                DatePicker("", selection: $draft.start)
                    .datePickerStyle(.compact)
                    .labelsHidden()
            }
            GridRow {
                Text("종료 시간").font(.caption).foregroundStyle(.secondary)
                DatePicker("", selection: $draft.end)
                    .datePickerStyle(.compact)
                    .labelsHidden()
            }
        }
    }
}
