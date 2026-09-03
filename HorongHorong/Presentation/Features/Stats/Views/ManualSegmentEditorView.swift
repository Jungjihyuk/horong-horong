import SwiftUI

private enum StatsEditorFormatters {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월 d일 (E)"
        return formatter
    }()
}

/// 특정 날짜의 앱 실행 구간과 완료된 포모도로 기록을 수동으로 추가/편집/삭제하는 시트.
/// 편집은 각 행에 attached 된 popover, 추가는 별도 sheet 로 띄운다.
struct ManualSegmentEditorView: View {
    let date: Date
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: StatsRecordEditorViewModel
    @State private var showAddSheet: Bool = false

    init(date: Date, repository: StatsRecordEditorRepository) {
        self.date = date
        _viewModel = State(initialValue: StatsRecordEditorViewModel(repository: repository))
    }

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
        .onAppear { viewModel.load(date: date) }
        .alert("저장할 수 없습니다", isPresented: Binding(
            get: { viewModel.editError != nil },
            set: { if !$0 { viewModel.editError = nil } }
        )) {
            Button("확인", role: .cancel) { viewModel.editError = nil }
        } message: {
            Text(viewModel.editError ?? "")
        }
        .sheet(isPresented: $showAddSheet) {
            SegmentFormSheet(
                title: "세그먼트 추가",
                initial: defaultInitial(),
                onSave: { draft in
                    if viewModel.addSegment(draft, date: date) {
                        showAddSheet = false
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
                            childSegments: viewModel.childSegments(for: session),
                            onSaveEdit: { draft in
                                viewModel.updateFocusSession(
                                    id: session.id,
                                    draft: draft,
                                    date: date
                                )
                            },
                            onDelete: {
                                viewModel.deleteFocusSession(id: session.id, date: date)
                            }
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
                                viewModel.updateSegment(id: seg.id, draft: draft, date: date)
                            },
                            onDelete: { viewModel.deleteSegment(id: seg.id, date: date) }
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

    private var segments: [StatsEditableSegment] { viewModel.segments }
    private var focusSessions: [StatsEditableFocusSession] { viewModel.focusSessions }

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
        StatsEditorFormatters.day.string(from: date)
    }
}

// MARK: - Row

private struct SegmentRowView: View, Equatable {
    let segment: StatsEditableSegment
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
                    if segment.isManual || segment.isUserModified {
                        Text(segment.isManual ? "직접 추가" : "사용자 수정")
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
                        start: segment.start,
                        end: segment.end
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
        let s = StatsEditorFormatters.time.string(from: segment.start)
        let e = StatsEditorFormatters.time.string(from: segment.end)
        let dur = segment.durationSeconds
        let h = dur / 3600
        let m = (dur % 3600) / 60
        let durText = h > 0 ? "\(h)h \(m)m" : "\(m)m"
        return "\(s) – \(e) · \(segment.category) · \(durText)"
    }

    nonisolated static func == (lhs: SegmentRowView, rhs: SegmentRowView) -> Bool {
        lhs.segment == rhs.segment
    }
}

private struct PomodoroEditRowView: View, Equatable {
    let session: StatsEditableFocusSession
    let childSegments: [StatsEditableSegment]
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
                        start: session.start,
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
        session.category
    }

    private var focusEnd: Date {
        session.end
    }

    private var durationSeconds: Int {
        session.durationSeconds
    }

    private var childTotalSeconds: Int {
        childSegments.reduce(0) { total, segment in
            let start = max(segment.start, session.start)
            let end = min(segment.end, focusEnd)
            guard end > start else { return total }
            return total + Int(end.timeIntervalSince(start))
        }
    }

    private var timeRange: String {
        "\(StatsEditorFormatters.time.string(from: session.start)) – \(StatsEditorFormatters.time.string(from: focusEnd))"
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }

    nonisolated static func == (lhs: PomodoroEditRowView, rhs: PomodoroEditRowView) -> Bool {
        lhs.session == rhs.session && lhs.childSegments == rhs.childSegments
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
