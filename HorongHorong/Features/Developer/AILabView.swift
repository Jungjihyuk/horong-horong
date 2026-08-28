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
        case golden = "골든셋 평가"
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
    @State private var goldenSummary: GoldenEvalReport.Summary = .empty
    @State private var isLoadingGolden = false
    @State private var isLoading = false
    @State private var selectedInputItemIDs: [String]? = nil
    @State private var ratings: [String: LabRating] = [:]

    @AppStorage(Constants.AppStorageKey.aiLabRatings)
    private var ratingsJSON: String = "{}"

    /// 골든셋 채점 결과가 있는 `Evals/` 경로. 한 번 고르면 기억한다.
    @AppStorage(Constants.AppStorageKey.aiLabEvalsDirectory)
    private var evalsDirectory: String = ""

    private let goldenModelColumnWidth: CGFloat = 168
    private let goldenValueColumnWidth: CGFloat = 104

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
            loadGoldenSummary()
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
            summaryChip(label: "모델", value: "\(goldenSummary.rows.count)", tint: .secondary)
            summaryChip(label: "모델당 실행", value: "\(goldenSummary.coverage)", tint: .secondary)
            if !goldenSummary.excluded.isEmpty {
                summaryChip(label: "미완주 제외", value: "\(goldenSummary.excluded.count)", tint: .orange)
            }
            Spacer()
            Button {
                loadGoldenSummary()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .controlSize(.small)
            .help("채점 결과 다시 불러오기")

            Button("Evals 폴더") { chooseEvalsDirectory() }
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

    // MARK: - 골든셋 평가

    /// `Evals/` 를 지정받아 채점 결과를 모델 비교표로 보여준다.
    ///
    /// **열 이름과 지표 정의는 `eval-report.py` 를 그대로 따른다.** 같은 데이터를 두 화면이
    /// 다른 이름으로 부르면 이야기가 통하지 않는다.
    ///
    /// 폴더를 받는 이유는 **결과가 gitignore 된 산출물**이라서다(`Evals/results/`).
    /// 앱에 번들할 수 없으니 개발 머신의 저장소를 한 번 가리켜 두고 기억한다.
    @ViewBuilder
    private var goldenMatrix: some View {
        if evalsDirectory.isEmpty {
            ContentUnavailableView {
                Label("Evals 폴더를 지정하세요", systemImage: "folder.badge.questionmark")
            } description: {
                Text("골든셋 채점 결과는 저장소의 Evals/results/ 에 있습니다.\n버전 관리에 올리지 않는 실행 산출물이라 앱에 담겨 있지 않습니다.")
            } actions: {
                Button("Evals 폴더 선택") { chooseEvalsDirectory() }
            }
        } else if isLoadingGolden {
            VStack(spacing: 10) {
                ProgressView()
                Text("채점 결과와 원문을 읽는 중…").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if goldenSummary.rows.isEmpty {
            ContentUnavailableView {
                Label("채점 결과가 없습니다", systemImage: "chart.bar.doc.horizontal")
            } description: {
                Text("\(evalsDirectory)/results/ 에서 완주한 실행을 찾지 못했습니다.\nmake goal-eval-matrix 로 골든셋을 돌린 뒤 다시 불러오세요.")
            } actions: {
                Button("다른 폴더 선택") { chooseEvalsDirectory() }
            }
        } else {
            // **받은 만큼만 차지한다.** 표가 필요로 하는 폭을 그대로 요구하면 그 폭이 창의
            // 최소 너비가 되어 `NavigationSplitView` 가 사이드바를 밀어낸다(실측 2026-08-28).
            // 넓은 표를 다루는 실사용 기록 탭과 같은 방식으로 맞춘다.
            GeometryReader { geo in
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 24) {
                        goldenCapabilityGrid
                        goldenTypeBreakdown
                        goldenMissingBreakdown
                        goldenJudgeTable
                        goldenContextTable
                        goldenParseTable
                        goldenFootnote
                    }
                    .padding(20)
                    .frame(width: max(goldenWidestTable + 40, geo.size.width), alignment: .topLeading)
                }
            }
        }
    }

    /// 표마다 열 수와 이름 길이가 달라 **열 폭을 따로 잡는다.** 하나로 묶으면 긴 이름이
    /// 중간에서 잘리거나(`context_dependen`/`t`), 열이 적은 표가 의미 없이 늘어난다.
    private func goldenTableWidth(columns: Int, columnWidth: CGFloat) -> CGFloat {
        goldenModelColumnWidth + columnWidth * CGFloat(columns)
    }

    /// 가로 스크롤 범위. 가장 넓은 표(LLM judge)에 맞춘다.
    private var goldenWidestTable: CGFloat {
        goldenTableWidth(columns: GoldenEvalReport.judgeMetrics.count + 2, columnWidth: 92)
    }

    /// 능력 격자 — 열마다 대상 집합이 다르다. 유형마다 정답의 성격이 달라
    /// 가로로 더한 값은 정의되지 않으므로 전체 평균 열은 두지 않는다.
    private var goldenCapabilityGrid: some View {
        let s = goldenSummary
        // 「안내 대상 일치도」가 가장 긴 이름이다. 여백 16pt 를 빼고도 담기는 폭.
        let w: CGFloat = 112
        let total = goldenTableWidth(columns: 9, columnWidth: w)
        return VStack(alignment: .leading, spacing: 8) {
            goldenSectionHead("능력 격자", "열마다 대상 집합이 다릅니다")
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    goldenGroupCell("", width: goldenModelColumnWidth)
                    goldenGroupCell("목표 연결", width: w * 2)
                    goldenGroupCell("안내", width: w * 4, leadingDivider: true)
                    goldenGroupCell("보류 및 자제", width: w * 2, leadingDivider: true)
                    goldenGroupCell("실행 시간", width: w, leadingDivider: true)
                }
                .frame(width: total, alignment: .leading)
                .padding(.top, 6)

                goldenHeaderRow([
                    ("모델", ""),
                    ("목표 연결 점수", "\(s.groupingCount)건"),
                    ("함정 회피", "\(s.groupingCount)건"),
                    ("안내 대상 일치도", "\(s.guidanceCount)건"),
                    ("정답 안내 (TP)", "\(s.guidanceCount)건"),
                    ("잘못 안내 (FP)", "\(s.guidanceCount)건"),
                    ("놓친 안내 (FN)", "\(s.guidanceCount)건"),
                    ("거절", "\(s.refusalCount)건"),
                    ("자제", "\(s.restraintCount)건"),
                    ("초", ""),
                ], columnWidth: w, tableWidth: total)

                ForEach(Array(s.rows.enumerated()), id: \.element.id) { index, row in
                    goldenRow(index: index, model: row.model, provider: row.provider, columnWidth: w, tableWidth: total, values: [
                        .score(row.groupingScore), .score(row.trapAvoidance),
                        .score(row.guidance), .count(row.guidanceTP), .count(row.guidanceFP), .count(row.guidanceFN),
                        .score(row.refusal), .score(row.restraint),
                        .seconds(row.seconds),
                    ])
                }
            }
            .frame(width: total, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
            goldenNote("각 지표의 정의는 eval-report 의 용어 탭과 같습니다. 「잘못 묶은 쌍 (FP)」 은 아직 넣지 않았습니다.", width: total)
        }
    }

    /// 유형별 분해 — 경계선 왼쪽 둘은 «묶어야», 오른쪽 둘은 «묶지 말아야» 정답이다.
    private var goldenTypeBreakdown: some View {
        let w: CGFloat = 172
        let total = goldenTableWidth(columns: GoldenEvalReport.typeOrder.count, columnWidth: w)
        return VStack(alignment: .leading, spacing: 8) {
            goldenSectionHead("유형별 분해", "유형마다 주력 지표 하나")
            VStack(spacing: 0) {
                goldenHeaderRow([("모델", "")] + GoldenEvalReport.typeOrder.map { ($0, goldenPrimaryLabel($0)) },
                                columnWidth: w, tableWidth: total)
                ForEach(Array(goldenSummary.rows.enumerated()), id: \.element.id) { index, row in
                    goldenRow(index: index, model: row.model, provider: row.provider, columnWidth: w, tableWidth: total,
                              values: GoldenEvalReport.typeOrder.map { type in
                                  row.byType[type].map { GoldenCell.score($0) } ?? .missing
                              })
                }
            }
            .frame(width: total, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
            goldenNote("경계선 왼쪽 두 유형은 목표를 연결해야 정답이고, 오른쪽 두 유형은 연결하지 말아야 정답입니다.", width: total)
        }
    }

    /// 안내 기준 분해 — 메모별 `missing` 기준을 «메모 ID · 기준명» 쌍으로 비교한 결정적 지표.
    private var goldenMissingBreakdown: some View {
        let w: CGFloat = 150
        let total = goldenTableWidth(columns: 4, columnWidth: w)
        return VStack(alignment: .leading, spacing: 8) {
            goldenSectionHead("안내 기준 분해", "메모별 missing 기준 쌍 · specific · measurable · time_bound")
            VStack(spacing: 0) {
                goldenHeaderRow([
                    ("모델", ""), ("정답 기준 (TP)", ""), ("잘못 추가한 기준 (FP)", ""),
                    ("놓친 기준 (FN)", ""), ("기준 F1", ""),
                ], columnWidth: w, tableWidth: total)
                ForEach(Array(goldenSummary.rows.enumerated()), id: \.element.id) { index, row in
                    goldenRow(index: index, model: row.model, provider: row.provider, columnWidth: w, tableWidth: total, values: [
                        .count(row.missingTP), .count(row.missingFP), .count(row.missingFN), .score(row.missingF1),
                    ])
                }
            }
            .frame(width: total, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
            goldenNote("안내 문장 자체의 품질은 평가하지 않습니다. 그것은 LLM judge 가 맡습니다.", width: total)
        }
    }

    /// LLM judge 품질 점수 — 0~5점 루브릭의 케이스별 평균.
    @ViewBuilder
    private var goldenJudgeTable: some View {
        let judged = goldenSummary.rows.filter { $0.judgeCount > 0 }
        let w: CGFloat = 92
        let total = goldenTableWidth(columns: GoldenEvalReport.judgeMetrics.count + 2, columnWidth: w)
        VStack(alignment: .leading, spacing: 8) {
            goldenSectionHead("LLM judge 품질 점수", goldenSummary.judgeMeta.map {
                "\($0.judge) · \($0.judgeModel) · 루브릭 \($0.rubricVersion) · 파일 \($0.fileCount)개"
            } ?? "판정 결과 없음")
            if judged.isEmpty {
                goldenNote("표시할 성공한 LLM judge 결과가 없습니다. make llm-judge 실행 후 다시 불러오세요.", width: total)
            } else {
                VStack(spacing: 0) {
                    goldenHeaderRow([("모델", "")]
                        + GoldenEvalReport.judgeMetrics.map { (GoldenEvalReport.judgeLabels[$0] ?? $0, "") }
                        + [("평균", ""), ("건수", "")], columnWidth: w, tableWidth: total)
                    ForEach(Array(judged.enumerated()), id: \.element.id) { index, row in
                        goldenRow(index: index, model: row.model, provider: row.provider, columnWidth: w, tableWidth: total,
                                  values: GoldenEvalReport.judgeMetrics.map { key in
                                      row.judgeScores[key].map { GoldenCell.rubric($0) } ?? .missing
                                  } + [
                                      row.judgeAverage.map { GoldenCell.rubric($0) } ?? .missing,
                                      .count(Double(row.judgeCount)),
                                  ])
                    }
                }
                .frame(width: total, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
                goldenNote("결정적 지표와 별도로 생성된 목표·안내 문장의 품질을 봅니다. 대시(—)는 그 항목을 적용하지 않은 경우입니다.", width: total)
            }
        }
    }

    /// 맥락 효과 — 같은 케이스의 두 recipe 를 짝지어 차이를 낸다.
    private var goldenContextTable: some View {
        let w: CGFloat = 112
        let total = goldenTableWidth(columns: 4, columnWidth: w)
        return VStack(alignment: .leading, spacing: 8) {
            goldenSectionHead("맥락 효과", "짝지어 비교 · 대상 \(goldenSummary.contextPairs)쌍")
            VStack(spacing: 0) {
                goldenHeaderRow([
                    ("모델", ""), ("개선", "쌍"), ("무변", "쌍"), ("악화", "쌍"), ("평균 차이", ""),
                ], columnWidth: w, tableWidth: total)
                ForEach(Array(goldenSummary.rows.enumerated()), id: \.element.id) { index, row in
                    goldenRow(index: index, model: row.model, provider: row.provider, columnWidth: w, tableWidth: total, values: [
                        .count(Double(row.contextUp)), .count(Double(row.contextFlat)),
                        .count(Double(row.contextDown)), .delta(row.contextMean),
                    ])
                }
            }
            .frame(width: total, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
            goldenNote("promptOnly 와 promptWithContext 를 같은 케이스끼리 짝지어 목표 연결 점수의 차이를 냅니다. context 키는 있으나 persona·profile 이 비어 두 프롬프트가 같아지는 케이스는 제외합니다.", width: total)
        }
    }

    /// 파싱 진단 — 파서가 모델 응답을 후보 목록으로 바꿀 때 세는 값.
    @ViewBuilder
    private var goldenParseTable: some View {
        let w: CGFloat = 120
        let total = goldenTableWidth(columns: GoldenEvalReport.parseKeys.count, columnWidth: w)
        VStack(alignment: .leading, spacing: 8) {
            goldenSectionHead("파싱 진단", "모델당 \(goldenSummary.coverage)건 누적 · 원문의 parsed 단계에서 집계")
            if !goldenSummary.hasTraces {
                goldenNote("원문(trace) 기록을 찾지 못했습니다. Evals/results/traces/ 가 있어야 이 표를 채울 수 있습니다.", width: total)
            } else {
                VStack(spacing: 0) {
                    goldenHeaderRow([("모델", "")] + GoldenEvalReport.parseKeys.map { ($0, "") },
                                    columnWidth: w, tableWidth: total)
                    ForEach(Array(goldenSummary.rows.enumerated()), id: \.element.id) { index, row in
                        goldenRow(index: index, model: row.model, provider: row.provider, columnWidth: w, tableWidth: total,
                                  values: GoldenEvalReport.parseKeys.map { key in
                                      row.parse[key].map { GoldenCell.count(Double($0)) } ?? .missing
                                  })
                    }
                }
                .frame(width: total, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
                goldenNote("modelReturned 와 kept 의 차이가 파서에서 버려진 양입니다. 오른쪽 네 열이 버려진 이유별 내역입니다.", width: total)
            }
        }
    }

    private var goldenFootnote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("모델 \(goldenSummary.rows.count)개 · 모델당 \(goldenSummary.coverage)건 · 결과 파일 \(goldenSummary.fileCount)개 · 정답지 \(goldenSummary.caseCount)개")
            if !goldenSummary.excluded.isEmpty {
                Text("케이스를 다 돌지 못해 제외: \(goldenSummary.excluded.joined(separator: ", "))")
                    .foregroundStyle(.orange)
            }
            Text(evalsDirectory).foregroundStyle(.tertiary)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func goldenNote(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: width, alignment: .leading)
    }

    private func goldenPrimaryLabel(_ type: String) -> String {
        switch GoldenEvalReport.primaryMetric[type] {
        case "groupingScore": "목표 연결"
        case "guidanceF1": "안내"
        case "noSuggestionCorrect": "거절"
        default: ""
        }
    }

    private func goldenSectionHead(_ title: String, _ scope: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.headline)
            Text(scope).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func goldenGroupCell(_ title: String, width: CGFloat, leadingDivider: Bool = false) -> some View {
        Text(title)
            .font(.caption2.bold())
            .foregroundStyle(.secondary)
            .frame(width: width)
            .overlay(alignment: .leading) {
                if leadingDivider { Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 1) }
            }
    }

    /// 머리글 한 줄. 아래 첨자는 **그 열의 대상 건수** — 열마다 분모가 다르다는 표시다.
    ///
    /// **여백은 칸 폭 안에서 뺀다.** 바깥에 두면 실제 칸이 `columnWidth + 16` 이 되어
    /// 표 전체 폭이 선언값보다 커지고, 오른쪽 끝이 잘리며 배경 줄무늬가 어긋난다.
    private func goldenHeaderRow(
        _ titles: [(String, String)], columnWidth: CGFloat, tableWidth: CGFloat
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, item in
                VStack(alignment: index == 0 ? .leading : .trailing, spacing: 1) {
                    Text(item.0)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        // 식별자는 중간에서 끊기면 다른 낱말처럼 보인다. 줄바꿈 대신 꼬리를 자른다.
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(item.0)
                    if !item.1.isEmpty {
                        Text(item.1).font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                }
                .frame(width: (index == 0 ? goldenModelColumnWidth : columnWidth) - 16,
                       alignment: index == 0 ? .leading : .trailing)
                .padding(.horizontal, 8)
            }
        }
        .frame(width: tableWidth, alignment: .leading)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// 칸 하나가 무엇인가. **«측정 안 함» 과 «0점» 을 절대 같은 칸으로 그리지 않는다.**
    private enum GoldenCell {
        /// 0~1 점수.
        case score(Double)
        /// 0~5 루브릭 점수.
        case rubric(Double)
        case count(Double)
        case seconds(Double)
        /// 부호가 뜻을 가지는 차이값.
        case delta(Double)
        case missing
    }

    private func goldenRow(
        index: Int, model: String, provider: String,
        columnWidth: CGFloat, tableWidth: CGFloat, values: [GoldenCell]
    ) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.replacingOccurrences(of: "mlx-community/", with: "mlx/"))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(provider).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: goldenModelColumnWidth - 16, alignment: .leading)
            .padding(.horizontal, 8)

            ForEach(Array(values.enumerated()), id: \.offset) { _, cell in
                goldenCellText(cell)
                    .frame(width: columnWidth - 16, alignment: .trailing)
                    .padding(.horizontal, 8)
            }
        }
        .frame(width: tableWidth, alignment: .leading)
        .padding(.vertical, 7)
        .background(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.025))
    }

    @ViewBuilder
    private func goldenCellText(_ cell: GoldenCell) -> some View {
        switch cell {
        case .score(let value):
            Text(String(format: "%.3f", value))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(value >= 0.7 ? Color.green : value >= 0.4 ? Color.primary : Color.orange)
        case .rubric(let value):
            Text(String(format: "%.2f", value))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(value >= 4.0 ? Color.green : value >= 3.0 ? Color.primary : Color.orange)
        case .count(let value):
            Text(String(format: "%.0f", value))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
        case .seconds(let value):
            Text(String(format: "%.2f", value))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
        case .delta(let value):
            Text(String(format: "%+.3f", value))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(value > 0.001 ? Color.green : value < -0.001 ? Color.orange : .secondary)
        case .missing:
            Text("—")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    private func chooseEvalsDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "선택"
        panel.message = "저장소의 Evals 폴더를 선택하세요 (results/ 와 golden/cases/ 가 들어 있는 곳)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        evalsDirectory = url.path
        loadGoldenSummary()
    }

    /// 원문 수천 개를 읽으므로 **화면을 잡아두지 않는다.** 집계를 백그라운드로 보내고 결과만 받는다.
    private func loadGoldenSummary() {
        if evalsDirectory.isEmpty, let guessed = Self.repositoryEvalsDirectory() {
            evalsDirectory = guessed.path
        }
        let path = evalsDirectory
        guard !path.isEmpty else {
            goldenSummary = .empty
            return
        }
        isLoadingGolden = true
        Task {
            let summary = await Task.detached(priority: .userInitiated) {
                GoldenEvalReport.summarize(evalsDirectory: URL(fileURLWithPath: path))
            }.value
            goldenSummary = summary
            isLoadingGolden = false
        }
    }

    /// 개발 빌드에서 저장소의 `Evals/` 를 스스로 찾는다.
    ///
    /// `#filePath` 는 빌드한 기계의 소스 경로라 **개발 중에만** 쓸모가 있다. 릴리스에서는
    /// 그 경로가 없으므로 자연히 실패하고 폴더 선택으로 넘어간다.
    /// 골든셋 하네스가 저장소를 찾는 방식과 같다(→ `GoldenSet.repositoryRoot`).
    private static func repositoryEvalsDirectory(from filePath: String = #filePath) -> URL? {
        var url = URL(fileURLWithPath: filePath)
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent("Evals", isDirectory: true)
            if GoldenEvalReport.looksLikeEvalsDirectory(candidate) { return candidate }
        }
        return nil
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

    /// 골든셋 하네스가 남긴 기록인가. **실사용 기록 탭은 이것을 세면 안 된다.**
    ///
    /// 골든셋은 제품 코드 경로를 그대로 지나 앱 실행 기록에도 쌓인다. 실측 2026-08-28:
    /// 7,610행 중 6,962행(91.5%)이 골든셋이었고 실사용은 648행뿐이었다.
    ///
    /// `source` 와 실행 id 를 함께 보는 이유는 **이미 쌓인 기록 때문**이다.
    /// 태그를 붙이기 전에 남은 줄은 전부 `source == "live"` 라 id 접두사로만 가려낼 수 있다.
    private static func isGoldenRecord(_ record: RunRecord) -> Bool {
        record.source == "golden" || AIRunLog.isGoldenRun(record.runId)
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
                           let runId = record.runId,
                           !Self.isGoldenRecord(record) {
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
                           let runId = record.runId,
                           !Self.isGoldenRecord(record) {
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
