import SwiftUI

/// 앱 내부에서 평가 결과를 시각적으로 확인하는 AI 실험실 뷰 (Phase 6 목표 선행 구현)
///
/// `Evals/eval-report.py` 가 만드는 정적 HTML 매트릭스와 같은 구조(행=케이스, 열=레벨/모델)를
/// 앱 안에 옮겨오되, 각 셀에서 바로 👍 / 👎 / 메모로 사람 평가를 남길 수 있게 한다.
public struct AILabView: View {
    // 임시 더미 데이터 모델 (실제 연동 전 레이아웃 확인용)
    struct LabCase: Identifiable {
        let id: String
        let title: String
        let levels: [LabLevel]
    }

    struct LabLevel: Identifiable {
        let id = UUID()
        let name: String
        let model: String?
        let output: String
        let scores: [String: Double]
        let latency: Int
    }

    /// 사람이 남긴 평가. 케이스 + 레벨 단위로 저장한다.
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

    /// 열을 무엇으로 나눌지. eval-report.py 의 두 탭과 같은 축이다.
    enum CompareAxis: String, CaseIterable, Identifiable {
        case level, model
        var id: String { rawValue }
        var label: String {
            switch self {
            case .level: return "컨텍스트 레벨"
            case .model: return "모델"
            }
        }
    }

    enum CaseFilter: String, CaseIterable, Identifiable {
        case all, warning, unrated
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "전체"
            case .warning: return "주의"
            case .unrated: return "미평가"
            }
        }
    }

    @State private var cases: [LabCase] = [
        LabCase(id: "tone-01", title: "테마 어디서 바꿔?", levels: [
            LabLevel(name: "L0", model: "mlx-llama3", output: "설정에서 바꿀 수 있어요.", scores: ["honorific": 1.0, "sentenceCount": 1.0, "groundedness": 0.2], latency: 379),
            LabLevel(name: "L1", model: "gpt-4o-mini", output: "설정 → 외관에서 바꾸실 수 있어요.", scores: ["honorific": 1.0, "sentenceCount": 1.0, "groundedness": 0.9], latency: 640)
        ]),
        LabCase(id: "tone-02", title: "야 설정가서 바꿔라", levels: [
            LabLevel(name: "L0", model: "mlx-llama3", output: "야, 설정가서 바꿔라", scores: ["honorific": 0.0, "sentenceCount": 1.0, "groundedness": 0.2], latency: 400),
            LabLevel(name: "L1", model: "gpt-4o-mini", output: "외관 설정 탭에서 변경이 가능합니다. 감사합니다.", scores: ["honorific": 1.0, "sentenceCount": 1.0, "groundedness": 0.9], latency: 800)
        ]),
        LabCase(id: "qa-01", title: "야", levels: [
            LabLevel(name: "L0", model: "mlx-llama3", output: "네?", scores: ["honorific": 1.0, "sentenceCount": 1.0, "groundedness": 0.2], latency: 400),
            LabLevel(name: "L1", model: "gpt-4o-mini", output: "네, 호롱호롱입니다. 무엇을 도와드릴까요?", scores: ["honorific": 1.0, "sentenceCount": 1.0, "groundedness": 0.9], latency: 800)
        ]),
        LabCase(id: "qa-02", title: "너는 누구야", levels: [
            LabLevel(name: "L0", model: "mlx-llama3", output: "저는 AI 어시스턴트입니다.", scores: ["honorific": 1.0, "sentenceCount": 1.0, "groundedness": 0.2], latency: 400),
            LabLevel(name: "L1", model: "gpt-4o-mini", output: "저는 호롱호롱 앱의 AI 컴패니언 '루미롱'입니다.", scores: ["honorific": 1.0, "sentenceCount": 1.0, "groundedness": 0.9], latency: 800)
        ]),
        LabCase(id: "qa-03", title: "너는 무슨 모델이야?", levels: [
            LabLevel(name: "L0", model: "mlx-llama3", output: "저는 언어 모델입니다.", scores: ["honorific": 1.0, "sentenceCount": 1.0, "groundedness": 0.2], latency: 400),
            LabLevel(name: "L1", model: "gpt-4o-mini", output: "저는 설정하신 Apple 온디바이스(또는 MLX/Ollama) 모델로 구동되고 있습니다.", scores: ["honorific": 1.0, "sentenceCount": 1.0, "groundedness": 0.9], latency: 800)
        ]),
        LabCase(id: "qa-04", title: "카테고리 매핑 하는 법 설명해줘", levels: [
            LabLevel(name: "L0", model: "mlx-llama3", output: "카테고리는 설정에서 매핑합니다.", scores: ["honorific": 1.0, "sentenceCount": 1.0, "groundedness": 0.2], latency: 400),
            LabLevel(name: "L1", model: "gpt-4o-mini", output: "설정 → 카테고리 매핑 탭에서 특정 앱이나 웹사이트를 원하시는 카테고리에 연결하실 수 있습니다.", scores: ["honorific": 1.0, "sentenceCount": 1.0, "groundedness": 0.9], latency: 800)
        ]),
        LabCase(id: "qa-05", title: "몰입 기능 설명해줘", levels: [
            LabLevel(name: "L0", model: "mlx-llama3", output: "몰입은 집중하는 기능입니다.", scores: ["honorific": 1.0, "sentenceCount": 1.0, "groundedness": 0.2], latency: 400),
            LabLevel(name: "L1", model: "gpt-4o-mini", output: "몰입 기능은 세션마다 몰입도를 재고, 기준선 아래로 떨어지면 루미롱이 말을 걸어주는 집중 넛지 기능입니다.", scores: ["honorific": 1.0, "sentenceCount": 1.0, "groundedness": 0.9], latency: 800)
        ]),
        LabCase(id: "qa-06", title: "몰입에서 집중 넛지는 뭐야?", levels: [
            LabLevel(name: "L0", model: "mlx-llama3", output: "집중하라고 알림을 주는 것입니다.", scores: ["honorific": 1.0, "sentenceCount": 1.0, "groundedness": 0.2], latency: 400),
            LabLevel(name: "L1", model: "gpt-4o-mini", output: "집중 넛지는 몰입도가 설정된 기준선 밑으로 떨어졌을 때, 화면 위에서 루미롱이 동기를 부여하는 잔소리를 해주는 기능입니다.", scores: ["honorific": 1.0, "sentenceCount": 1.0, "groundedness": 0.9], latency: 800)
        ]),
        LabCase(id: "qa-07", title: "뉴스 리포트 생성 기능 설명해줘", levels: [
            LabLevel(name: "L0", model: "mlx-llama3", output: "뉴스를 모아서 리포트로 줍니다.", scores: ["honorific": 1.0, "sentenceCount": 1.0, "groundedness": 0.2], latency: 400),
            LabLevel(name: "L1", model: "gpt-4o-mini", output: "설정 → 뉴스 탭에서 관심사 키워드를 등록해두면, 정해진 수집 간격마다 요약 에이전트가 뉴스를 모아 일일 리포트를 자동 생성해 줍니다.", scores: ["honorific": 1.0, "sentenceCount": 1.0, "groundedness": 0.9], latency: 800)
        ]),
        LabCase(id: "qa-08", title: "미리알림 연동하는 법 설명해줘", levels: [
            LabLevel(name: "L0", model: "mlx-llama3", output: "미리알림 앱을 켜서 연결하세요.", scores: ["honorific": 1.0, "sentenceCount": 1.0, "groundedness": 0.2], latency: 400),
            LabLevel(name: "L1", model: "gpt-4o-mini", output: "설정 → 메모 탭에서 '미리알림 가져오기'를 켜고 연동할 캘린더를 선택하시면 됩니다.", scores: ["honorific": 1.0, "sentenceCount": 1.0, "groundedness": 0.9], latency: 800)
        ]),
        LabCase(id: "qa-09", title: "AI Agent 기능이 뭐야?", levels: [
            LabLevel(name: "L0", model: "mlx-llama3", output: "AI가 작업을 대신 해줍니다.", scores: ["honorific": 1.0, "sentenceCount": 1.0, "groundedness": 0.2], latency: 400),
            LabLevel(name: "L1", model: "gpt-4o-mini", output: "AI Agent 기능은 Codex, Claude, Antigravity 등의 모델을 활용해 터미널 명령을 실행하거나 자동화된 실험을 수행할 수 있게 해주는 기능입니다.", scores: ["honorific": 1.0, "sentenceCount": 1.0, "groundedness": 0.9], latency: 800)
        ]),
        LabCase(id: "qa-10", title: "성취 설정에서 모델 설정 하는 법 알려줘", levels: [
            LabLevel(name: "L0", model: "mlx-llama3", output: "성취 설정에서 모델을 선택하세요.", scores: ["honorific": 1.0, "sentenceCount": 1.0, "groundedness": 0.2], latency: 400),
            LabLevel(name: "L1", model: "gpt-4o-mini", output: "설정 → 성취 탭의 '추천 엔진'에서 Apple 온디바이스, MLX, Ollama 중 하나를 선택하실 수 있습니다.", scores: ["honorific": 1.0, "sentenceCount": 1.0, "groundedness": 0.9], latency: 800)
        ]),
        LabCase(id: "qa-11", title: "루미롱 활용법 알려줘", levels: [
            LabLevel(name: "L0", model: "mlx-llama3", output: "루미롱은 비서입니다.", scores: ["honorific": 1.0, "sentenceCount": 1.0, "groundedness": 0.2], latency: 400),
            LabLevel(name: "L1", model: "gpt-4o-mini", output: "루미롱은 화면 위에 띄워두고 대화를 나누거나, 집중 모드일 때 숨기기, 오늘 일정 브리핑 받기 등 설정 → 루미롱 탭에서 다양하게 커스텀하여 활용할 수 있습니다.", scores: ["honorific": 1.0, "sentenceCount": 1.0, "groundedness": 0.9], latency: 800)
        ]),
        LabCase(id: "qa-12", title: "Apple 온디바이스, MLX, Ollama 이거 차이가 뭐야?", levels: [
            LabLevel(name: "L0", model: "mlx-llama3", output: "각각 다른 모델 제공자입니다.", scores: ["honorific": 1.0, "sentenceCount": 1.0, "groundedness": 0.2], latency: 400),
            LabLevel(name: "L1", model: "gpt-4o-mini", output: "Apple 온디바이스는 빠르고 준비가 필요 없지만, MLX는 더 많은 할 일을 묶을 수 있는 대신 메모리를 쓰고, Ollama는 앱 외부 프로세스로 큰 모델을 구동할 수 있습니다.", scores: ["honorific": 1.0, "sentenceCount": 1.0, "groundedness": 0.9], latency: 800)
        ])
    ]

    @State private var axis: CompareAxis = .level
    @State private var filter: CaseFilter = .all
    @State private var expandedCases: Set<String> = []

    /// 평가는 JSON 한 덩어리로 저장한다. 키는 "케이스ID|레벨".
    @AppStorage(Constants.AppStorageKey.aiLabRatings)
    private var ratingsJSON: String = "{}"

    private let caseColumnWidth: CGFloat = 168
    private let minCellWidth: CGFloat = 210

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            matrix
        }
    }

    // MARK: - 헤더

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI 실험실")
                        .font(.title2.bold())
                    Text("케이스별 응답을 나란히 놓고 비교하면서 바로 평가를 남깁니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $axis) {
                    ForEach(CompareAxis.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            HStack(spacing: 8) {
                summaryChip(label: "케이스", value: "\(cases.count)", tint: .secondary)
                summaryChip(label: "주의", value: "\(warningCount)", tint: warningCount > 0 ? .orange : .secondary)
                summaryChip(label: "평가", value: "\(ratedCount)/\(totalResultCount)", tint: ratedCount == totalResultCount ? .green : .secondary)
                Spacer()
                Picker("", selection: $filter) {
                    ForEach(CaseFilter.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Button("평가 초기화") { ratingsJSON = "{}" }
                    .controlSize(.small)
                    .disabled(ratedCount == 0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
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

    // MARK: - 매트릭스

    @ViewBuilder
    private var matrix: some View {
        if filteredCases.isEmpty {
            ContentUnavailableView("조건에 맞는 케이스가 없습니다", systemImage: "line.3.horizontal.decrease.circle")
        } else {
            // 가로 스크롤을 바깥에 두면 열 머리와 본문이 같이 움직이고,
            // 세로 스크롤은 안쪽이라 열 머리가 위에 고정된 채로 남는다.
            GeometryReader { geo in
                let width = cellWidth(containerWidth: geo.size.width)
                let tableWidth = caseColumnWidth + 20 + CGFloat(columns.count) * (width + 21)
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 0) {
                        columnHeader(cellWidth: width)
                        ScrollView(.vertical) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(filteredCases.enumerated()), id: \.element.id) { index, labCase in
                                    row(labCase, cellWidth: width, isEven: index.isMultiple(of: 2))
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

    /// 열이 몇 개든 가로 스크롤 없이 폭을 꽉 채우게. 좁아지면 minCellWidth 에서 멈추고 스크롤한다.
    /// 케이스 열 + 좌우 padding(20) + 세로 스크롤바(16) + 셀마다 padding(20) + 구분선(1) 을 뺀 나머지를 열 수로 나눈다.
    private func cellWidth(containerWidth: CGFloat) -> CGFloat {
        guard !columns.isEmpty else { return minCellWidth }
        let available = containerWidth - caseColumnWidth - 36 - CGFloat(columns.count) * 21
        return max(minCellWidth, available / CGFloat(columns.count))
    }

    private func columnHeader(cellWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                Text("케이스 / 질문")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: caseColumnWidth, alignment: .leading)
                    .padding(.horizontal, 10)

                ForEach(columns, id: \.self) { column in
                    Divider()
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(column)
                                .font(.callout.bold())
                            if axis == .level, let desc = AILabFormat.levelDescription(column) {
                                Text(desc)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(columnSummary(column))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: cellWidth, alignment: .leading)
                    .padding(.horizontal, 10)
                }
            }
            .padding(.vertical, 8)
            Divider()
        }
        // HStack 안의 Divider 가 남은 세로 공간을 다 먹지 않도록 콘텐츠 높이로 고정한다.
        .fixedSize(horizontal: false, vertical: true)
        .background(.bar)
    }

    private func row(_ labCase: LabCase, cellWidth: CGFloat, isEven: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            AILabCaseCell(
                labCase: labCase,
                isExpanded: expandedCases.contains(labCase.id),
                ratedCount: labCase.levels.filter { rating(labCase.id, $0.name) != nil }.count,
                onToggle: { toggleExpanded(labCase.id) }
            )
            .frame(width: caseColumnWidth, alignment: .leading)
            .padding(.horizontal, 10)

            ForEach(columns, id: \.self) { column in
                Divider()
                if let level = level(in: labCase, column: column) {
                    AILabResultCell(
                        level: level,
                        isExpanded: expandedCases.contains(labCase.id),
                        rating: rating(labCase.id, level.name) ?? LabRating(),
                        onVerdict: { verdict in
                            updateRating(labCase.id, level.name) { $0.verdict = ($0.verdict == verdict) ? nil : verdict }
                        },
                        onNote: { note in
                            updateRating(labCase.id, level.name) { $0.note = note }
                        }
                    )
                    .frame(width: cellWidth, alignment: .topLeading)
                    .padding(.horizontal, 10)
                } else {
                    Text("데이터 없음")
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

    // MARK: - 열 / 행 계산

    private func columnKey(_ level: LabLevel) -> String {
        axis == .level ? level.name : (level.model ?? "unknown")
    }

    private var columns: [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for labCase in cases {
            for level in labCase.levels where !seen.contains(columnKey(level)) {
                seen.insert(columnKey(level))
                result.append(columnKey(level))
            }
        }
        return result.sorted()
    }

    private func level(in labCase: LabCase, column: String) -> LabLevel? {
        labCase.levels.first { columnKey($0) == column }
    }

    private var filteredCases: [LabCase] {
        switch filter {
        case .all:
            return cases
        case .warning:
            return cases.filter { hasWarning($0) }
        case .unrated:
            return cases.filter { labCase in
                labCase.levels.contains { rating(labCase.id, $0.name) == nil }
            }
        }
    }

    private func hasWarning(_ labCase: LabCase) -> Bool {
        labCase.levels.contains { $0.scores.values.contains { $0 < 0.5 } }
    }

    private var warningCount: Int { cases.filter { hasWarning($0) }.count }

    private var totalResultCount: Int { cases.reduce(0) { $0 + $1.levels.count } }

    private var ratedCount: Int {
        cases.reduce(0) { sum, labCase in
            sum + labCase.levels.filter { rating(labCase.id, $0.name) != nil }.count
        }
    }

    /// 열 머리에 붙는 요약: 평균 점수 · 평균 지연.
    private func columnSummary(_ column: String) -> String {
        let levels = filteredCases.compactMap { level(in: $0, column: column) }
        guard !levels.isEmpty else { return "데이터 없음" }
        let scores = levels.flatMap { $0.scores.values }
        let avgScore = scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
        let avgLatency = levels.reduce(0) { $0 + $1.latency } / levels.count
        return String(format: "평균 %.2f · %dms", avgScore, avgLatency)
    }

    private func toggleExpanded(_ caseId: String) {
        if expandedCases.contains(caseId) {
            expandedCases.remove(caseId)
        } else {
            expandedCases.insert(caseId)
        }
    }

    // MARK: - 평가 저장

    private var ratings: [String: LabRating] {
        guard let data = ratingsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: LabRating].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func rating(_ caseId: String, _ levelName: String) -> LabRating? {
        ratings["\(caseId)|\(levelName)"]
    }

    private func updateRating(_ caseId: String, _ levelName: String, _ transform: (inout LabRating) -> Void) {
        let key = "\(caseId)|\(levelName)"
        var all = ratings
        var value = all[key] ?? LabRating()
        transform(&value)
        if value.isEmpty {
            all.removeValue(forKey: key)
        } else {
            all[key] = value
        }
        guard let data = try? JSONEncoder().encode(all),
              let json = String(data: data, encoding: .utf8) else { return }
        ratingsJSON = json
    }
}

// MARK: - 케이스(행 머리) 셀

private struct AILabCaseCell: View {
    let labCase: AILabView.LabCase
    let isExpanded: Bool
    let ratedCount: Int
    let onToggle: () -> Void

    private var worstScore: Double {
        labCase.levels.flatMap { $0.scores.values }.min() ?? 1.0
    }

    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(AILabFormat.color(for: worstScore))
                        .frame(width: 6, height: 6)
                    Text(labCase.id)
                        .font(.caption.bold())
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                Text(labCase.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(isExpanded ? nil : 2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text("평가 \(ratedCount)/\(labCase.levels.count)")
                    .font(.system(size: 9))
                    .foregroundStyle(ratedCount == labCase.levels.count ? Color.green : Color.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "접기" : "펼쳐서 전체 응답 보기")
    }
}

// MARK: - 결과 셀 (응답 + 점수 + 평가)

private struct AILabResultCell: View {
    let level: AILabView.LabLevel
    let isExpanded: Bool
    let rating: AILabView.LabRating
    let onVerdict: (String) -> Void
    let onNote: (String) -> Void

    @State private var isEditingNote = false
    @State private var noteDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(level.output)
                .font(.caption)
                .textSelection(.enabled)
                .lineLimit(isExpanded ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                .help(level.output)

            HStack(spacing: 4) {
                ForEach(level.scores.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    AILabScoreChip(key: key, value: value)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 4) {
                verdictButton("hand.thumbsup", verdict: "up", tint: .green)
                verdictButton("hand.thumbsdown", verdict: "down", tint: .red)
                noteButton
                Spacer(minLength: 0)
                Text("\(level.latency)ms")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            if !rating.note.isEmpty {
                Text(rating.note)
                    .font(.system(size: 10))
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(isExpanded ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
        .help(verdict == "up" ? "좋은 응답" : "나쁜 응답")
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
        .help("메모 남기기")
        .popover(isPresented: $isEditingNote, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(level.name) 메모")
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

// MARK: - 점수 chip

private struct AILabScoreChip: View {
    let key: String
    let value: Double

    var body: some View {
        HStack(spacing: 3) {
            Text(AILabFormat.shortName(key))
            Text(String(format: "%.1f", value))
                .fontWeight(.semibold)
        }
        .font(.system(size: 10))
        .foregroundStyle(AILabFormat.color(for: value))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 4).fill(AILabFormat.color(for: value).opacity(0.12)))
        .help("\(AILabFormat.fullName(key)) \(String(format: "%.2f", value))")
    }
}

// MARK: - 표기 규칙 (eval-report.py 와 동일한 임계값)

private enum AILabFormat {
    static func fullName(_ key: String) -> String {
        switch key {
        case "honorific": return "존댓말 비율"
        case "sentenceCount": return "문장 수 제한"
        case "groundedness": return "사실 기반"
        case "pairF1": return "F1 스코어"
        case "predictedGroups": return "추천 목표 개수"
        default: return key
        }
    }

    static func shortName(_ key: String) -> String {
        switch key {
        case "honorific": return "존대"
        case "sentenceCount": return "문장"
        case "groundedness": return "사실"
        case "pairF1": return "F1"
        case "predictedGroups": return "개수"
        default: return key
        }
    }

    static func color(for value: Double) -> Color {
        if value >= 0.99 { return .green }
        if value <= 0.01 { return .red }
        if value < 0.5 { return .orange }
        return .yellow
    }

    static func levelDescription(_ level: String) -> String? {
        switch level {
        case "L0": return "Prompt-only"
        case "L1": return "Structured-context"
        case "L2": return "Lexical-retrieval"
        case "L3": return "Hybrid-retrieval"
        case "L4": return "Graph-augmented"
        default: return nil
        }
    }
}

struct AILabView_Previews: PreviewProvider {
    static var previews: some View {
        AILabView()
            .frame(width: 720, height: 620)
    }
}
