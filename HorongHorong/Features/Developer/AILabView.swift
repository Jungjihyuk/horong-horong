import SwiftUI
import SwiftData
import HorongAI

/// 앱 내부에서 실제 AI 실행 기록(`RunRecord`) 및 평가 결과를 시각적으로 확인하는 AI 실험실 뷰
public struct AILabView: View {
    @Query private var allMemos: [Memo]
    @Query private var allGoals: [AchievementGoalRecord]

    /// 실사용 실행을 run_id + task 단위로 묶은 구조
    struct LiveRunGroup: Identifiable {
        let id: String
        let runId: String
        let task: String
        let startedAt: Date?
        let attempts: [RunRecord]

        var lastAttempt: RunRecord? {
            attempts.last
        }

        var isSuccess: Bool {
            Self.isCompletedModelOutcome(lastAttempt?.outcome)
        }

        var hasFailure: Bool {
            attempts.contains { !Self.isCompletedModelOutcome($0.outcome) }
        }

        private static func isCompletedModelOutcome(_ outcome: String?) -> Bool {
            switch outcome {
            case "ok", "guidance", "noSuggestion": true
            default: false
            }
        }

        /// 주간·월간을 동시에 돌렸나 하나씩 돌렸나 — `RunRecord.variant`.
        ///
        /// 같은 모델·같은 입력인데 소요 시간이 다르면 **이것부터 봐야 한다.** 전략이 다르면
        /// 애초에 다른 조건에서 잰 숫자라 나란히 놓고 비교하면 안 된다.
        var executionVariant: String? {
            attempts.compactMap(\.variant).first
        }

        var candidateCount: Int? {
            attempts.first?.inputSummary?.candidateCount
        }

        var itemCount: Int {
            attempts.first?.inputSummary?.itemCount ?? 0
        }

        var itemIDs: [String] {
            attempts.first?.inputSummary?.itemIDs ?? []
        }
    }

    /// 골든셋 케이스 (레거시/실험실 비교용)
    struct GoldenCase: Identifiable {
        let id: String
        let title: String
        let levels: [GoldenLevel]
    }

    struct GoldenLevel: Identifiable {
        let id = UUID()
        let name: String
        let model: String?
        let output: String
        let scores: [String: Double]
        let latency: Int
    }

    /// 사람이 남긴 평가 (key = "runId|attempt" 또는 "caseId|level")
    struct LabRating: Codable, Equatable {
        var verdict: String?   // "up" | "down"
        var note: String

        init(verdict: String? = nil, note: String = "") {
            self.verdict = verdict
            self.note = note
        }

        var isEmpty: Bool {
            verdict == nil && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    enum TabMode: String, CaseIterable, Identifiable {
        case live = "실사용 기록"
        case golden = "골든셋 매트릭스"
        var id: String { rawValue }
    }

    enum LiveFilter: String, CaseIterable, Identifiable {
        case all = "전체"
        case failed = "실패 포함"
        case ok = "성공만"
        case unrated = "미평가"
        var id: String { rawValue }
    }

    @State private var tabMode: TabMode = .live
    @State private var liveFilter: LiveFilter = .all
    @State private var taskFilter: String = "전체"
    @State private var liveRunGroups: [LiveRunGroup] = []
    @State private var goldenCases: [GoldenCase] = []
    @State private var isLoading = false
    @State private var selectedInputItemIDs: [String]? = nil
    @State private var ratings: [String: LabRating] = [:]

    @AppStorage(Constants.AppStorageKey.aiLabRatings)
    private var ratingsJSON: String = "{}"

    private let caseColumnWidth: CGFloat = 200
    private let minCellWidth: CGFloat = 260

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if tabMode == .live {
                liveMatrix
            } else {
                goldenMatrix
            }
        }
        .onAppear {
            loadRecords()
        }
        // 실험실을 **열어 둔 채** 다른 창에서 추천을 돌리는 게 보통이다. 그때 새 기록이
        // 안 들어와서 «룰 시도가 안 보인다» 로 읽혔다(실측 2026-08-20). 창이 다시 앞에
        // 오면 스스로 읽는다 — 새로고침 버튼을 누르는 걸 기억에 맡기지 않는다.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loadRecords()
        }
        .sheet(item: Binding(
            get: { selectedInputItemIDs.map { ItemIDsWrapper(ids: $0) } },
            set: { selectedInputItemIDs = $0?.ids }
        )) { wrapper in
            InputItemsDetailSheet(
                itemIDs: wrapper.ids,
                memos: allMemos,
                goals: allGoals
            )
        }
    }

    // MARK: - 헤더

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI 실험실")
                        .font(.title2.bold())
                    Text("실제 앱 구동 중 수집된 실행 기록(RunRecord)과 모델 응답을 분석하고 평가합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $tabMode) {
                    ForEach(TabMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            if tabMode == .live {
                liveToolbar
            } else {
                goldenToolbar
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var liveToolbar: some View {
        HStack(spacing: 8) {
            summaryChip(label: "총 실행", value: "\(liveRunGroups.count)", tint: .secondary)
            summaryChip(label: "최종 성공", value: "\(liveRunGroups.filter(\.isSuccess).count)", tint: .green)
            let failCount = liveRunGroups.filter { !$0.isSuccess }.count
            summaryChip(label: "실패", value: "\(failCount)", tint: failCount > 0 ? .red : .secondary)
            
            let allTasks = ["전체"] + Array(Set(liveRunGroups.map(\.task))).sorted()
            if allTasks.count > 2 {
                Picker("태스크", selection: $taskFilter) {
                    ForEach(allTasks, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
            }

            Spacer()

            Picker("", selection: $liveFilter) {
                ForEach(LiveFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Button {
                loadRecords()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .controlSize(.small)
            .help("기록 다시 불러오기")

            Button {
                revealRunsFolder()
            } label: {
                Image(systemName: "folder")
            }
            .controlSize(.small)
            .help("Finder에서 기록 폴더 열기")
        }
    }

    private var goldenToolbar: some View {
        HStack(spacing: 8) {
            summaryChip(label: "케이스", value: "\(goldenCases.count)", tint: .secondary)
            Spacer()
            Button("평가 초기화") { ratingsJSON = "{}" }
                .controlSize(.small)
        }
    }

    private func summaryChip(label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(tint)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
    }

    // MARK: - 실사용(Live) 매트릭스

    @ViewBuilder
    private var liveMatrix: some View {
        if filteredLiveGroups.isEmpty {
            ContentUnavailableView(
                liveRunGroups.isEmpty ? "수집된 실행 기록이 없습니다" : "조건에 맞는 실행 기록이 없습니다",
                systemImage: "waveform.path.ecg.rectangle"
            )
        } else {
            let maxAttempts = max(1, filteredLiveGroups.map { $0.attempts.count }.max() ?? 1)
            GeometryReader { geo in
                let cellW = max(minCellWidth, (geo.size.width - caseColumnWidth - 36) / CGFloat(maxAttempts))
                let tableWidth = caseColumnWidth + 20 + CGFloat(maxAttempts) * (cellW + 21)

                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 0) {
                        liveColumnHeader(maxAttempts: maxAttempts, cellWidth: cellW)
                        ScrollView(.vertical) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(filteredLiveGroups.enumerated()), id: \.element.id) { index, group in
                                    liveRow(group, maxAttempts: maxAttempts, cellWidth: cellW, isEven: index.isMultiple(of: 2))
                                    Divider()
                                }
                            }
                        }
                    }
                    .frame(width: max(tableWidth, geo.size.width), height: geo.size.height, alignment: .topLeading)
                }
            }
        }
    }

    private func liveColumnHeader(maxAttempts: Int, cellWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                Text("실행 ID / 태스크")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: caseColumnWidth, alignment: .leading)
                    .padding(.horizontal, 10)

                ForEach(1...maxAttempts, id: \.self) { attemptNum in
                    Divider()
                    Text("시도 \(attemptNum) (Attempt \(attemptNum))")
                        .font(.callout.bold())
                        .frame(width: cellWidth, alignment: .leading)
                        .padding(.horizontal, 10)
                }
            }
            .padding(.vertical, 8)
            Divider()
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(.bar)
    }

    private func liveRow(_ group: LiveRunGroup, maxAttempts: Int, cellWidth: CGFloat, isEven: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // 좌측 헤더: 실행 정보 및 입력 할일 조회 버튼
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(group.isSuccess ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(group.runId)
                        .font(.caption.monospaced().bold())
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    Text(group.task)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))

                    // 실행 전략. 없으면 이 값을 남기기 전(2026-08-19 이전)의 기록이다.
                    if let variant = group.executionVariant {
                        let isParallel = variant == "parallel"
                        Label(
                            isParallel ? "병렬" : "직렬",
                            systemImage: isParallel ? "arrow.trianglehead.branch" : "arrow.down"
                        )
                        .font(.caption2.bold())
                        .foregroundStyle(isParallel ? Color.orange : Color.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill((isParallel ? Color.orange : Color.secondary).opacity(0.12))
                        )
                        .help(
                            isParallel
                                ? "주간·월간을 동시에 보냈습니다. 로컬 모델은 요청을 하나씩만 처리하므로 뒤엣것이 큐에서 기다리다 타임아웃될 수 있습니다."
                                : "주간이 끝난 뒤 월간을 보냈습니다. 각자 타임아웃 예산을 온전히 씁니다."
                        )
                    }
                }

                if let startedAt = group.startedAt {
                    Text(startedAt.formatted(date: .numeric, time: .standard))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                if !group.itemIDs.isEmpty {
                    Button {
                        selectedInputItemIDs = group.itemIDs
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "list.bullet.rectangle")
                            Text("입력 항목 (\(group.itemCount)개)")
                        }
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.link)
                    .help("이 실행에 주입된 원본 할일/메모 내용 조회")
                }
            }
            .frame(width: caseColumnWidth, alignment: .leading)
            .padding(.horizontal, 10)

            // 시도별 셀
            ForEach(1...maxAttempts, id: \.self) { attemptNum in
                Divider()
                if let record = group.attempts.first(where: { ($0.attempt ?? 1) == attemptNum }) {
                    // `group.id` 는 `runId|task` 다. `runId` 만 쓰면 한 번의 묶음 실행에서 나온
                    // 주간·월간이 같은 칸을 공유해 한쪽을 누르면 양쪽이 같이 눌린다.
                    let ratingKey = "\(group.id)|\(attemptNum)"
                    LiveAttemptCell(
                        record: record,
                        rating: ratings[ratingKey] ?? LabRating(),
                        onVerdict: { v in
                            updateRating(key: ratingKey) { $0.verdict = ($0.verdict == v) ? nil : v }
                        },
                        onNote: { n in
                            updateRating(key: ratingKey) { $0.note = n }
                        },
                        onViewInputs: { ids in
                            selectedInputItemIDs = ids
                        }
                    )
                    .frame(width: cellWidth, alignment: .topLeading)
                    .padding(.horizontal, 10)
                } else {
                    Text("-")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(width: cellWidth, alignment: .center)
                        .padding(.horizontal, 10)
                }
            }
        }
        .padding(.vertical, 10)
        .background(isEven ? Color.clear : Color.primary.opacity(0.025))
    }

    private func formatSeconds(_ ms: Int) -> String {
        let sec = Double(ms) / 1000.0
        if sec >= 10 {
            return String(format: "%.1fs", sec)
        } else {
            return String(format: "%.2fs", sec)
        }
    }

    // MARK: - 골든셋 매트릭스 (더미/평가용)

    @ViewBuilder
    private var goldenMatrix: some View {
        if goldenCases.isEmpty {
            ContentUnavailableView("골든셋 결과가 없습니다", systemImage: "chart.bar.doc.horizontal")
        } else {
            List(goldenCases) { gCase in
                VStack(alignment: .leading, spacing: 6) {
                    Text(gCase.title)
                        .font(.headline)
                    ForEach(gCase.levels) { lvl in
                        HStack {
                            Text(lvl.name)
                                .font(.subheadline.bold())
                            if let model = lvl.model {
                                Text("(\(model))").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(formatSeconds(lvl.latency)).font(.caption).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("출력 (추천 결과)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                            Text(lvl.output)
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - 데이터 로딩 및 필터링

    private var filteredLiveGroups: [LiveRunGroup] {
        liveRunGroups.filter { group in
            if taskFilter != "전체" && group.task != taskFilter {
                return false
            }
            switch liveFilter {
            case .all:
                return true
            case .failed:
                return group.hasFailure
            case .ok:
                return group.isSuccess
            case .unrated:
                // 칸을 그릴 때와 **같은 식**으로 키를 만든다. 배열 순번(`idx`)을 쓰면
                // 1번 시도가 없는 그룹에서 실제 시도 번호와 어긋나 미평가 판정이 틀린다.
                return group.attempts.contains { record in
                    ratings["\(group.id)|\(record.attempt ?? 1)"] == nil
                }
            }
        }
    }

    private func loadRecords() {
        isLoading = true
        defer { isLoading = false }

        var runs: [String: [RunRecord]] = [:]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // 1. App Support / HorongHorong / runs/*.jsonl
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let baseDir = appSupport?.appendingPathComponent("HorongHorong")
        let runsDir = baseDir?.appendingPathComponent("runs")

        if let runsDir = runsDir, FileManager.default.fileExists(atPath: runsDir.path) {
            let files = (try? FileManager.default.contentsOfDirectory(at: runsDir, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "jsonl" {
                if let content = try? String(contentsOf: file, encoding: .utf8) {
                    for line in content.split(separator: "\n") {
                        if let data = line.data(using: .utf8),
                           let record = try? decoder.decode(RunRecord.self, from: data),
                           let runId = record.runId {
                            let taskName = record.task ?? "weekly_goal"
                            let groupKey = "\(runId)|\(taskName)"
                            runs[groupKey, default: []].append(record)
                        }
                    }
                }
            }
        }

        // 2. HorongHorong-Debug/runs/*.jsonl 도 함께 탐색 (개발 모드 실행분)
        let debugBaseDir = appSupport?.appendingPathComponent("HorongHorong-Debug")
        let debugRunsDir = debugBaseDir?.appendingPathComponent("runs")
        if let debugRunsDir = debugRunsDir, FileManager.default.fileExists(atPath: debugRunsDir.path) {
            let files = (try? FileManager.default.contentsOfDirectory(at: debugRunsDir, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "jsonl" {
                if let content = try? String(contentsOf: file, encoding: .utf8) {
                    for line in content.split(separator: "\n") {
                        if let data = line.data(using: .utf8),
                           let record = try? decoder.decode(RunRecord.self, from: data),
                           let runId = record.runId {
                            let taskName = record.task ?? "weekly_goal"
                            let groupKey = "\(runId)|\(taskName)"
                            // 중복 체크 후 추가
                            if let existing = runs[groupKey], existing.contains(where: { $0.startedAt == record.startedAt && $0.attempt == record.attempt }) {
                                continue
                            }
                            runs[groupKey, default: []].append(record)
                        }
                    }
                }
            }
        }

        // 그룹 리스트 변환 및 최신순 정렬
        liveRunGroups = runs.compactMap { key, attempts in
            let sortedAttempts = attempts.sorted { ($0.attempt ?? 1) < ($1.attempt ?? 1) }
            guard let first = sortedAttempts.first, let runId = first.runId else { return nil }
            return LiveRunGroup(
                id: key,
                runId: runId,
                task: first.task ?? "weekly_goal",
                startedAt: first.startedAt,
                attempts: sortedAttempts
            )
        }.sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }

        loadRatings()
    }

    private func loadRatings() {
        guard let data = ratingsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: LabRating].self, from: data) else { return }
        self.ratings = decoded
    }

    private func updateRating(key: String, mutate: (inout LabRating) -> Void) {
        var r = ratings[key] ?? LabRating()
        mutate(&r)
        ratings[key] = r
        saveRatings()
    }

    private func saveRatings() {
        // 빈 항목 정리
        let all = ratings.filter { _, v in
            v.verdict != nil || !v.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard let data = try? JSONEncoder().encode(all),
              let json = String(data: data, encoding: .utf8) else { return }
        ratingsJSON = json
    }

    private func revealRunsFolder() {
        guard let runsDir = try? SwiftDataStoreLocation.applicationDirectoryURL()
            .appendingPathComponent("runs", isDirectory: true) else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: runsDir.path)
    }
}

// MARK: - 시도(Attempt) 카드 셀

private struct LiveAttemptCell: View {
    let record: RunRecord
    let rating: AILabView.LabRating
    let onVerdict: (String) -> Void
    let onNote: (String) -> Void
    let onViewInputs: ([String]) -> Void

    @State private var isEditingNote = false
    @State private var noteDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 헤더: 공급자 + Outcome 배지
            HStack(alignment: .center, spacing: 6) {
                Text(record.provider ?? "unknown")
                    .font(.subheadline.bold())
                    // 룰 폴백은 **모델이 아니다.** 색을 달리해 한눈에 갈리게 한다.
                    .foregroundStyle(record.provider == "rule" ? Color.purple : Color.primary)
                if let model = record.model {
                    Text("(\(model))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                // 어느 룰이 만들었나 — `rule:context+keyword` 처럼 온다.
                if let recipe = record.recipe, recipe.hasPrefix("rule") {
                    Text(recipe.replacingOccurrences(of: "rule:", with: ""))
                        .font(.caption2.bold())
                        .foregroundStyle(Color.purple)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.purple.opacity(0.12)))
                        .help("모델이 하나도 못 만들어 규칙으로 묶은 결과입니다. 어느 규칙이 쓰였는지 보여줍니다.")
                }
                Spacer(minLength: 0)
                outcomeBadge
            }

            // 하이퍼파라미터
            if let params = record.parameters, !params.isEmpty {
                let formatted = params.sorted(by: { $0.key < $1.key }).map { k, v in
                    let valStr = v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))" : String(format: "%g", v)
                    return "\(k):\(valStr)"
                }.joined(separator: ", ")
                HStack(spacing: 4) {
                    Text("⚙️")
                        .font(.system(size: 9))
                    Text(formatted)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2.5)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.05)))
            }

            // 후보 / 입력 수치 & 클릭 시 원문 확인 버튼
            if let input = record.inputSummary {
                Button {
                    onViewInputs(input.itemIDs)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 10))
                        Text("입력 \(input.itemCount)개 (\(input.promptCharacters)자)")
                            .font(.system(size: 11, weight: .medium))
                        if let cand = input.candidateCount {
                            Text("(후보 \(cand)개 중)")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.05)))
                }
                .buttonStyle(.plain)
                .help("클릭하여 이 시도에 주입된 실제 메모/할일 원문 \(input.itemCount)개 보기")
            }

            // 파서 지표 — **왜 걸러졌는지까지** 보여준다.
            //
            // 예전에는 «2개 중 0개 채택» 까지만 보여주고 이유를 안 그려서, 기록에는 답이
            // 있는데 화면만 보고는 판단이 안 됐다(실측 2026-08-20). 원문을 열어 볼 필요가
            // 없어야 실험실이 제 값을 한다.
            if let parse = record.parse {
                VStack(alignment: .leading, spacing: 3) {
                    Text("모델 제안 \(parse.modelReturned)개 → 채택 \(parse.kept)개")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .help("모델이 만든 묶음 \(parse.modelReturned)개 중 검증을 통과해 화면에 나간 것이 \(parse.kept)개입니다.")
                    ForEach(parseNotes) { note in
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Image(systemName: note.symbol)
                                .font(.system(size: 9))
                            Text(note.text)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(note.tint)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(note.hint)
                    }
                }
            }

            // 토큰 사용량
            if let usage = record.usage, (usage.tokensIn != nil || usage.tokensOut != nil) {
                HStack(spacing: 4) {
                    Image(systemName: "number.circle")
                        .font(.system(size: 9))
                    Text("토큰 in:\(usage.tokensIn ?? 0) / out:\(usage.tokensOut ?? 0)")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.secondary)
            }

            // 생성 결과
            if !record.output.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 9))
                        Text("출력 (추천 결과)")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(.secondary)

                    Text(record.output)
                        .font(.caption)
                        .textSelection(.enabled)
                        .lineLimit(6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
            }

            // 소요 시간 & 평가 버튼
            HStack(spacing: 4) {
                verdictButton("hand.thumbsup", verdict: "up", tint: .green)
                verdictButton("hand.thumbsdown", verdict: "down", tint: .red)
                noteButton
                Spacer(minLength: 0)
                let genMs = record.timings?["generate"] ?? record.totalMs
                Text("생성 \(formatSeconds(genMs)) / 총 \(formatSeconds(record.totalMs))")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            if !rating.note.isEmpty {
                Text(rating.note)
                    .font(.system(size: 10))
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))
    }

    private func formatSeconds(_ ms: Int) -> String {
        let sec = Double(ms) / 1000.0
        if sec >= 10 {
            return String(format: "%.1fs", sec)
        } else {
            return String(format: "%.2fs", sec)
        }
    }

    /// 걸러진 이유 한 줄. **무슨 일이 있었는지**를 명사구로 말하고 개수를 괄호에 담는다.
    ///
    /// 이름을 줄여 쓰면(`2개미만 1`) 숫자가 무엇을 세는지 알 수 없다. 특히 `tooFewIDs` 만
    /// **묶음 수**이고 나머지는 **항목 수**라, 나란히 놓으면 같은 단위처럼 읽힌다.
    struct ParseNote: Identifiable {
        let id = UUID()
        let symbol: String
        let text: String
        let tint: Color
        let hint: String
    }

    /// 주간은 «할일», 월간은 «주간 목표» 를 묶는다. 같은 카운터라도 세는 대상이 다르다.
    private var itemNoun: String {
        record.task == "monthly_goal" ? "주간 목표" : "할일"
    }

    /// 묶음당 상한. 실행 시점의 설정값을 기록에서 읽는다 —
    /// 지금 설정을 읽으면 **그 사이 바뀐 값**을 보여주게 된다.
    private var maxItemsPerGoal: Int? {
        record.parameters?["max_items_per_goal"].map { Int($0) }
    }

    /// 0 인 것은 빼서 **일어난 일만** 남긴다. 영향이 큰 것부터 위로 둔다 —
    /// 묶음이 통째로 사라진 것과 항목 몇 개가 잘린 것은 무게가 다르다.
    private var parseNotes: [ParseNote] {
        guard let parse = record.parse else { return [] }
        var notes: [ParseNote] = []
        if parse.tooFewIDs > 0 {
            notes.append(ParseNote(
                symbol: "xmark.circle",
                text: "\(itemNoun.withParticle(.subject)) 1개뿐이라 목표 \(parse.tooFewIDs)개 제외",
                tint: .red,
                hint: "목표는 여러 \(itemNoun)을 묶어 하나의 결과로 만드는 것입니다. "
                    + "1개짜리는 그 \(itemNoun) 자체라 목표로 만들지 않습니다. "
                    + "모델이 억지로 묶기를 피했거나, 애초에 묶을 만한 것이 없는 입력일 수 있습니다."
            ))
        }
        if parse.badID > 0 {
            notes.append(ParseNote(
                symbol: "questionmark.circle",
                text: "존재하지 않는 \(itemNoun) \(parse.badID)개 생성",
                tint: .red,
                hint: "모델이 입력에 없던 항목 번호를 지어냈습니다(환각). 그만큼 묶음에서 빠졌습니다."
            ))
        }
        if parse.alreadyUsed > 0 {
            notes.append(ParseNote(
                symbol: "arrow.triangle.branch",
                text: "다른 목표에 이미 묶인 \(itemNoun) \(parse.alreadyUsed)개 제외",
                tint: .orange,
                hint: "한 \(itemNoun)은 목표 하나에만 들어갑니다. 앞선 목표가 이미 가져간 항목을 "
                    + "모델이 다른 목표에도 넣어, 나중 목표에서 뺐습니다. "
                    + "그 결과 나중 목표가 1개짜리가 되어 통째로 버려지기도 합니다."
            ))
        }
        if parse.overMaxMemo > 0 {
            // **몇 개 목표에서 잘렸는지는 세지 않는다.** 이 값은 잘려나간 항목의 총합이라
            // 한 목표에서 3개가 잘린 것과 세 목표에서 1개씩 잘린 것이 똑같이 3 으로 나온다.
            // 그래서 숫자 옆에 반드시 단위를 붙인다 — 목표 수로 읽히면 안 된다.
            let limitText = maxItemsPerGoal.map { " (묶음당 \($0)개까지)" } ?? ""
            notes.append(ParseNote(
                symbol: "scissors",
                text: "상한을 넘겨 \(itemNoun) \(parse.overMaxMemo)개 잘림\(limitText)",
                tint: .orange,
                hint: "모델이 설정보다 많이 묶어서 뒤엣것이 잘렸습니다. "
                    + "**버려진 것이 아니라 잘린 것**이라 추천 자체는 나옵니다. "
                    + "숫자는 잘려나간 \(itemNoun)의 **총합**입니다 — 한 목표에서 여러 개가 잘렸을 수도, "
                    + "여러 목표에서 하나씩 잘렸을 수도 있습니다. "
                    + "설정을 올리면 더 큰 묶음을 받을 수 있습니다."
            ))
        }
        return notes
    }

    private var outcomeBadge: some View {
        let outcome = record.outcome ?? "unknown"
        let detail = record.outcomeDetail
        let isOk = outcome == "ok"
        let isWarn = outcome == "parsedEmpty" || outcome == "validationFailed"
        let tint: Color = isOk ? .green : (isWarn ? .orange : .red)

        let (labelText, tooltip) = outcomeInfo(outcome: outcome, detail: detail)

        return Text(labelText)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(tint.opacity(0.12)))
            .help(tooltip)
    }

    private func outcomeInfo(outcome: String, detail: String?) -> (label: String, tooltip: String) {
        switch outcome {
        case "ok":
            return ("성공 (ok)", "목표 초안이 정상적으로 생성 및 파싱되었습니다.")
        case "generationFailed":
            if let detail = detail {
                switch detail {
                case "timeout":
                    return ("타임아웃 (timeout)", "60초 동안 모델이 응답하지 않아 시간 초과되었습니다.")
                case "connectionRefused":
                    return ("서버 연결 실패 (connectionRefused)", "로컬 Ollama 데몬이 꺼져 있거나 포트에 접속할 수 없습니다.")
                case "networkDisconnected":
                    return ("네트워크 단절", "네트워크 연결이 끊겼습니다.")
                case "networkError":
                    return ("네트워크 오류", "모델 통신 중 네트워크 오류가 발생했습니다.")
                default:
                    return ("생성 실패 (\(detail))", "LLM 추론 실패: \(detail)")
                }
            }
            return ("생성 실패 (generationFailed)", "LLM 추론 단계 실패 또는 60초 타임아웃이 발생했습니다.")
        case "serverUnavailable":
            return ("서버 불가 (serverUnavailable)", "Ollama 데몬이 꺼져 있거나 서버에 연결할 수 없습니다.")
        case "modelUnavailable":
            return ("모델 불가 (modelUnavailable)", "해당 기기에서 지원하지 않거나 모델 파일이 없습니다.")
        case "decodeFailed":
            if let detail = detail {
                switch detail {
                case "noJSON":
                    return ("JSON 누락 (noJSON)", "모델 응답 안에 JSON 객체({})가 전혀 없습니다. (자연어로만 답변)")
                case "malformed":
                    return ("문법 오류 (malformed)", "JSON 형식이 깨져 파싱할 수 없습니다.")
                case "missingKeys":
                    return ("필수 키 누락 (missingKeys)", "JSON에 title, memos 등 필수 필드가 빠졌습니다.")
                case "truncated":
                    return ("응답 잘림 (truncated)", "최대 토큰 길이에 도달해 JSON이 중간에 잘렸습니다.")
                default:
                    return ("해석 실패 (\(detail))", "JSON 디코딩 실패: \(detail)")
                }
            }
            return ("JSON 해석 실패", "모델 출력을 JSON으로 파싱하지 못했습니다.")
        case "parsedEmpty", "validationFailed":
            if let detail = detail {
                switch detail {
                case "emptyList":
                    return ("초안 목록 비어있음 (emptyList)", "모델이 빈 목록([])을 반환했습니다.")
                case "hallucinatedIDs":
                    return ("가짜 ID 환각 (hallucinatedIDs)", "입력에 없는 가짜 메모 ID를 생성하여 비즈니스 검증에서 모두 탈락했습니다.")
                case "tooFewMemos":
                    return ("메모 개수 부족 (tooFewMemos)", "목표당 최소 메모 묶음 기준에 미달하여 제외되었습니다.")
                case "duplicateMemos":
                    return ("중복 메모 (duplicateMemos)", "이미 사용된 메모를 중복 재사용하여 제외되었습니다.")
                default:
                    return ("검증 탈락 (\(detail))", "비즈니스 규칙 검증 실패: \(detail)")
                }
            }
            return ("유효 결과 없음 (parsedEmpty)", "JSON은 읽었으나 메모 ID 불일치/환각 등으로 쓸 수 있는 초안이 0개입니다.")
        default:
            return (detail != nil ? "\(outcome):\(detail!)" : outcome, outcome)
        }
    }

    private func verdictButton(_ symbol: String, verdict: String, tint: Color) -> some View {
        let isOn = rating.verdict == verdict
        return Button {
            onVerdict(verdict)
        } label: {
            Image(systemName: isOn ? "\(symbol).fill" : symbol)
                .font(.system(size: 11))
                .foregroundStyle(isOn ? tint : Color.secondary)
                .frame(width: 20, height: 18)
                .background(RoundedRectangle(cornerRadius: 4).fill(isOn ? tint.opacity(0.15) : Color.primary.opacity(0.05)))
        }
        .buttonStyle(.plain)
    }

    private var noteButton: some View {
        Button {
            noteDraft = rating.note
            isEditingNote = true
        } label: {
            Image(systemName: rating.note.isEmpty ? "square.and.pencil" : "text.bubble.fill")
                .font(.system(size: 11))
                .foregroundStyle(rating.note.isEmpty ? Color.secondary : Color.accentColor)
                .frame(width: 20, height: 18)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isEditingNote, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("실행 평가 메모")
                    .font(.caption.bold())
                TextEditor(text: $noteDraft)
                    .font(.caption)
                    .frame(width: 220, height: 90)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.15)))
                HStack {
                    Spacer()
                    Button("취소") { isEditingNote = false }
                    Button("저장") {
                        onNote(noteDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                        isEditingNote = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .controlSize(.small)
            }
            .padding(12)
        }
    }
}

// MARK: - 입력 할일/메모 원문 조회 시트

private struct ItemIDsWrapper: Identifiable {
    let id = UUID()
    let ids: [String]
}

private struct InputItemsDetailSheet: View {
    let itemIDs: [String]
    let memos: [Memo]
    let goals: [AchievementGoalRecord]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("주입된 원본 입력 항목")
                        .font(.title3.bold())
                    Text("이 실행 시 모델 프롬프트에 포함되었던 \(itemIDs.count)개의 항목 원문입니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("닫기") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(itemIDs, id: \.self) { rawID in
                        if let uuid = UUID(uuidString: rawID) {
                            if let memo = memos.first(where: { $0.id == uuid }) {
                                memoRow(memo)
                            } else if let goal = goals.first(where: { $0.id == uuid }) {
                                goalRow(goal)
                            } else {
                                missingRow(rawID)
                            }
                        } else {
                            missingRow(rawID)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 500, minHeight: 400)
    }

    private func memoRow(_ memo: Memo) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(memo.icon ?? "📝")
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(memo.content)
                    .font(.callout)
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    if let deadline = memo.deadline {
                        Text("마감: \(deadline.formatted(date: .numeric, time: .omitted))")
                    }
                    if memo.isCompleted == true {
                        Text("완료됨").foregroundStyle(.green)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
    }

    private func goalRow(_ goal: AchievementGoalRecord) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(goal.emoji)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.title)
                    .font(.callout.bold())
                    .textSelection(.enabled)
                Text("\(goal.cadence) 목표 · 연결 메모 \(goal.linkedMemoIDs.count)개")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
    }

    private func missingRow(_ idStr: String) -> some View {
        HStack {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.tertiary)
            Text("삭제되었거나 찾을 수 없는 항목 (ID: \(idStr))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(8)
    }
}
