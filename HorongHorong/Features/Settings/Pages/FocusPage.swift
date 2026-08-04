import Charts
import SwiftData
import SwiftUI

/// 설정 → 몰입.
///
/// 지난 14일 세션의 몰입도를 그대로 보여주고, 그 위에 사용자가 직접 기준선을 긋게 한다.
/// 판정 규칙을 글로 설명하는 대신 자기 기록 위에서 선을 옮겨보게 하는 것이 이 화면의 목적이다.
struct FocusPage: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage(Constants.AppStorageKey.companionFocusNudgeEnabled)
    private var isEnabled: Bool = Constants.defaultCompanionFocusNudgeEnabled
    @AppStorage(Constants.AppStorageKey.companionFocusNudgeMessages)
    private var messages: String = ""

    @State private var samples: [FocusScoreSample] = []
    /// 드래그 중에도 매 프레임 바뀌는 값. 저장은 손을 뗄 때만 한다.
    @State private var threshold = FocusScoreThreshold.fallback
    /// nil 이면 전체. 카테고리를 고르면 그 카테고리 세션만 보고 기준선도 따로 잡는다.
    @State private var selectedCategory: String?
    @State private var pairStore = CategoryPairStore.shared

    private static let chartHeight: CGFloat = 200

    var body: some View {
        SettingsPageScroll {
            SettingsPageHeader(title: SettingsTab.focus.label, subtitle: SettingsTab.focus.subtitle)

            SettingsGroupCard("집중 넛지") {
                SettingsRow(
                    "몰입도가 기준선 아래로 떨어지면 말 걸기",
                    subtitle: "집중 시작 5분 뒤부터 봅니다. 한 세션에 한 번만 나타납니다."
                ) {
                    Toggle("", isOn: $isEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            SettingsGroupCard("지난 \(FocusScoreHistory.dayCount)일 몰입도") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("몰입도 = 집중 카테고리(와 짝 카테고리)에 쓴 시간 ÷ 세션 전체 시간. "
                        + "자리를 비운 시간도 세션에 포함됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    categoryPicker
                    pairSuggestionRow

                    if !visibleSamples.isEmpty {
                        // 기준선 값은 그래프 안이 아니라 밖에 둔다. 선이 위아래 끝으로 가면
                        // 그래프 안의 라벨은 잘려서 읽을 수 없다.
                        HStack(spacing: 6) {
                            Text("기준선")
                                .font(.callout)
                            Text("\(Int((threshold * 100).rounded()))%")
                                .font(.callout.monospacedDigit().bold())
                                .foregroundStyle(Color.accentColor)
                            Text("· 선을 위아래로 끌어 조절하세요")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if visibleSamples.isEmpty {
                        emptyChartPlaceholder
                    } else {
                        chart
                        Text(captionText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }

            SettingsGroupCard("해줄 말") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("한 줄에 하나씩 적어주세요. 적은 순서대로 돌아가며, 같은 말이 연달아 나오지 않습니다.\n"
                        + "비워두면 집중이 안 되는지 부드럽게 묻는 기본 문구를 씁니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TextEditor(text: $messages)
                        .font(.system(size: 12))
                        .frame(height: 72)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(0.06))
                        )
                        .disabled(!isEnabled)

                    HStack {
                        Text(messagePreview)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer(minLength: 8)
                        Text("\(messages.count)/\(Constants.companionFocusNudgeMessagesMaxLength)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(
                                messages.count > Constants.companionFocusNudgeMessagesMaxLength
                                    ? AnyShapeStyle(Color.red)
                                    : AnyShapeStyle(.tertiary)
                            )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .task { load() }
    }

    // MARK: - 카테고리

    /// 기록이 있는 카테고리만 고를 수 있게 한다. 세션이 없는 카테고리는 그래프가 비어 의미가 없다.
    private var availableCategories: [String] {
        Array(Set(samples.map(\.category))).sorted()
    }

    private var visibleSamples: [FocusScoreSample] {
        guard let selectedCategory else { return samples }
        return samples.filter { $0.category == selectedCategory }
    }

    @ViewBuilder
    private var categoryPicker: some View {
        if !availableCategories.isEmpty {
            HStack(spacing: 8) {
                Picker("", selection: $selectedCategory) {
                    Text("전체").tag(String?.none)
                    ForEach(availableCategories, id: \.self) { category in
                        Text(category).tag(String?.some(category))
                    }
                }
                .labelsHidden()
                .fixedSize()

                if let selectedCategory {
                    if FocusThresholdStore.shared.hasCustomThreshold(for: selectedCategory) {
                        Button("전체 기준선 따르기") {
                            FocusThresholdStore.shared.resetThreshold(for: selectedCategory)
                            threshold = FocusThresholdStore.shared.overall
                        }
                        .controlSize(.small)
                    } else {
                        Text("전체 기준선을 따르는 중 · 선을 끌면 이 카테고리만 따로 정해집니다")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .onChange(of: selectedCategory) { _, _ in
                threshold = FocusThresholdStore.shared.threshold(for: selectedCategory)
            }
        }
    }

    /// 집중 카테고리와 실제 쓰는 앱이 어긋나면 몰입도가 낮게 나온다. 기준선을 낮추는 대신
    /// 짝으로 묶어 지표를 바로잡도록 그 자리에서 제안한다.
    /// 고른 카테고리가 있으면 그 카테고리, 전체 보기면 가장 크게 어긋난 카테고리 하나.
    private var pairSuggestion: FocusPairSuggestion? {
        if let selectedCategory {
            return FocusPairSuggester.suggestion(
                category: selectedCategory,
                samples: samples,
                isPaired: { pairStore.contains($0, $1) }
            )
        }
        return FocusPairSuggester.strongestSuggestion(
            samples: samples,
            isPaired: { pairStore.contains($0, $1) }
        )
    }

    @ViewBuilder
    private var pairSuggestionRow: some View {
        if let suggestion = pairSuggestion {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                Text("\(suggestion.category) 세션에서 \(Int((suggestion.share * 100).rounded()))% 를 "
                    + "\(suggestion.partner) 앱에 쓰고 있어요. 딴짓이 아니라면 짝으로 묶어주세요.")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("짝으로 묶기") {
                    pairStore.add(suggestion.category, suggestion.partner)
                    load()
                }
                .controlSize(.small)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.08))
            )
        }
    }

    // MARK: - 그래프

    private var chart: some View {
        Chart {
            ForEach(visibleSamples) { sample in
                BarMark(
                    x: .value("시각", sample.startedAt),
                    y: .value("몰입도", sample.score.value * 100),
                    width: .fixed(6)
                )
                .foregroundStyle(sample.score.value < threshold ? Color.red.opacity(0.8) : Color.accentColor)
                .cornerRadius(2)
            }

            // 막대보다 뒤에 선언해야 선이 위에 그려진다.
            RuleMark(y: .value("기준선", threshold * 100))
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
        }
        // 도메인을 고정하지 않으면 값을 좌표로 되돌릴 때 기준이 흔들린다.
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let percent = value.as(Int.self) {
                        Text("\(percent)%")
                    }
                }
            }
        }
        .frame(height: Self.chartHeight)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    // fill(.clear) 만으로는 제스처가 잡히지 않는다.
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                updateThreshold(at: drag.location.y, proxy: proxy, geometry: geometry)
                            }
                            .onEnded { _ in persistThreshold() }
                    )
            }
        }
        // 암시적 애니메이션이 붙으면 선이 커서를 늦게 따라와 굼뜨게 느껴진다.
        .animation(nil, value: threshold)
    }

    private var emptyChartPlaceholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.bar")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("아직 완료한 포모도로가 없어요.\n집중을 한 번 마치면 여기에 몰입도가 쌓입니다.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.chartHeight)
    }

    /// 드래그 y 좌표를 몰입도로 되돌린다.
    ///
    /// `proxy.value(atY:)` 는 plot 영역 기준 좌표를 받으므로 GeometryReader 좌표에서 원점을 빼야 한다.
    /// 이걸 빼먹으면 축 라벨 높이만큼 선이 어긋난다.
    private func updateThreshold(at y: CGFloat, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let localY = y - geometry[plotFrame].origin.y
        guard let percent: Double = proxy.value(atY: localY) else { return }
        threshold = FocusScoreThreshold.clamped(percent / 100)
    }

    /// 저장은 손을 뗄 때만 한다. `CompanionController` 가 UserDefaults 변경을 듣고 있어
    /// 드래그하는 내내 쓰면 오버레이가 매 프레임 다시 설정된다.
    private func persistThreshold() {
        if let selectedCategory {
            FocusThresholdStore.shared.setThreshold(threshold, for: selectedCategory)
        } else {
            FocusThresholdStore.shared.overall = threshold
        }
    }

    private var captionText: String {
        let scores = visibleSamples.map(\.score.value)
        let count = FocusScoreThreshold.belowCount(scores, threshold: threshold)
        let scope = selectedCategory.map { "\($0) 세션" } ?? "지난 \(FocusScoreHistory.dayCount)일"
        guard count > 0 else {
            return "이 기준이면 \(scope) 동안 잔소리를 듣지 않았어요."
        }
        return "이 기준이면 \(scope) 중 \(count)번 잔소리를 들었어요."
    }

    private var messagePreview: String {
        let parsed = FocusScoreMessages.parse(messages)
        guard parsed.isEmpty else {
            return "등록한 말 \(parsed.count)개를 돌아가며 씁니다."
        }
        return "기본 문구 예: \(FocusScoreMessages.fallback[0])"
    }

    private func load() {
        samples = FocusScoreHistory.samples(modelContext: modelContext)

        if UserDefaults.standard.object(
            forKey: Constants.AppStorageKey.companionFocusScoreThreshold
        ) == nil {
            // 첫 전체 기준선은 내 기록에서 뽑고 곧바로 저장한다.
            // 그래야 화면과 판정이 처음부터 같은 값을 본다.
            FocusThresholdStore.shared.overall = FocusScoreThreshold.percentileDefault(
                samples.map(\.score.value)
            )
        }
        threshold = FocusThresholdStore.shared.threshold(for: selectedCategory)
    }
}
