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
            lastAttempt?.outcome == "ok"
        }

        var hasFailure: Bool {
            attempts.contains { $0.outcome != "ok" }
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

                Text(group.task)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))

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
                if let model = record.model {
                    Text("(\(model))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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

            // 파서 지표 (추천 목표 개수)
            if let parse = record.parse {
                HStack(spacing: 6) {
                    Text("추천 목표 총 \(parse.modelReturned)개 중 최종 \(parse.kept)개 채택")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    if parse.badID > 0 {
                        Text("잘못된ID:\(parse.badID)")
                            .font(.system(size: 10).bold())
                            .foregroundStyle(.red)
                    }
                }
                .help("모델이 제안한 추천 목표 총 개수(\(parse.modelReturned)개) 중 유효성 검증을 통과한 최종 추천 목표 개수(\(parse.kept)개)")
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
