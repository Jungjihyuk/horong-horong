import SwiftUI
import SwiftData

/// 특정 날짜의 `AppUsageSegment` 를 수동으로 추가/편집/삭제하는 시트.
/// 편집은 각 행에 attached 된 popover, 추가는 별도 sheet 로 띄운다.
struct ManualSegmentEditorView: View {
    let date: Date
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var segments: [AppUsageSegment] = []
    @State private var showAddSheet: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if segments.isEmpty {
                emptyView
            } else {
                segmentList
            }
        }
        .frame(minWidth: 560, minHeight: 440)
        .onAppear(perform: load)
        .sheet(isPresented: $showAddSheet) {
            SegmentFormSheet(
                title: "세그먼트 추가",
                initial: defaultInitial(),
                onSave: { draft in
                    addSegment(from: draft)
                    showAddSheet = false
                    load()
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
                Text("세그먼트를 편집해도 차트가 자동으로 갱신됩니다")
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

    private var segmentList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(segments, id: \.id) { seg in
                    SegmentRowView(
                        segment: seg,
                        onSaveEdit: { draft in applyEdit(on: seg, draft: draft); load() },
                        onDelete: { delete(seg); load() }
                    )
                    Divider()
                }
            }
        }
    }

    // MARK: - Data

    private func load() {
        let dayStart = Calendar.current.startOfDay(for: date)
        guard let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) else {
            segments = []
            return
        }
        let descriptor = FetchDescriptor<AppUsageSegment>(
            predicate: #Predicate { $0.startTime >= dayStart && $0.startTime < dayEnd },
            sortBy: [SortDescriptor(\.startTime)]
        )
        segments = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func addSegment(from draft: SegmentDraft) {
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
    }

    private func applyEdit(on seg: AppUsageSegment, draft: SegmentDraft) {
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
    let onSaveEdit: (SegmentDraft) -> Void
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
                        onSaveEdit(draft)
                        showEditPopover = false
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

// MARK: - Form types

struct SegmentDraft {
    var appName: String
    var category: String
    var start: Date
    var end: Date

    var isValid: Bool {
        !appName.trimmingCharacters(in: .whitespaces).isEmpty && end > start
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
