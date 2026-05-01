import SwiftUI
import SwiftData
import AppKit

struct NewsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(Constants.NewsStorageKey.dataBasePath) private var dataBasePath = Constants.defaultNewsDataBasePath
    @AppStorage(Constants.NewsStorageKey.selectedProvider) private var selectedProvider = Constants.defaultNewsProvider
    @AppStorage(Constants.NewsStorageKey.interestKeywords) private var interestKeywords = Constants.defaultNewsInterestKeywords
    @AppStorage(Constants.NewsStorageKey.youtubeChannelIds) private var youtubeChannelIdsRaw = ""

    @State private var pipelineService = NewsPipelineService()
    @State private var newChannelInput = ""
    @Query(sort: \NewsReportIndex.createdAt, order: .reverse) private var recentReports: [NewsReportIndex]
    @State private var selectedReport: NewsReportIndex?

    private let pipelineSteps = ["collect", "normalize", "dedupe", "classify", "rank", "summarize", "render"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                Divider()
                runSection
                if pipelineService.isRunning {
                    statusSection
                }
                if !pipelineService.lastWarnings.isEmpty {
                    warningsSection
                }
                Divider()
                reportsSection
                if pipelineService.lastErrorCode != nil {
                    Divider()
                    errorSection
                }
                Divider()
                settingsSection
            }
        }
        .onAppear {
            applyDefaultPathsIfNeeded()
        }
    }

    private var header: some View {
        Label("뉴스 큐레이션", systemImage: "newspaper")
            .font(.headline)
    }

    private var runSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Provider")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $selectedProvider) {
                    ForEach(Constants.availableNewsProviders, id: \.self) { provider in
                        Text(provider.capitalized).tag(provider)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            if pipelineService.isRunning {
                Button("중단") { pipelineService.cancelJob() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            } else {
                Button("리포트 생성") { launchJob() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.7)
                Text(stepLabel(pipelineService.currentStep))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(pipelineService.elapsedSeconds)초")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 4) {
                ForEach(pipelineSteps, id: \.self) { step in
                    stepDot(step: step)
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func stepDot(step: String) -> some View {
        let currentIdx = pipelineSteps.firstIndex(of: pipelineService.currentStep) ?? -1
        let thisIdx = pipelineSteps.firstIndex(of: step) ?? 0
        let color: Color = thisIdx < currentIdx ? .green
            : thisIdx == currentIdx ? .accentColor
            : .secondary.opacity(0.3)
        return Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .help(step)
    }

    private var warningsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(pipelineService.lastWarnings, id: \.self) { warning in
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text(warning)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private var reportsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("최근 리포트")
                .font(.caption)
                .foregroundStyle(.secondary)

            if recentReports.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "newspaper")
                        .foregroundStyle(.secondary)
                    Text("아직 생성된 리포트가 없습니다")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
            } else {
                ForEach(recentReports.prefix(5)) { report in
                    reportRow(report: report)
                }
            }
        }
    }

    private func reportRow(report: NewsReportIndex) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(formatDate(report.reportDate))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(report.topTitle)
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(report.itemCount)개")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: report.reportPath))
                } label: {
                    Image(systemName: "doc.text")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selectedReport?.jobId == report.jobId
                    ? Color.accentColor.opacity(0.1)
                    : Color.secondary.opacity(0.05))
        )
        .onTapGesture { selectedReport = report }
    }

    private var errorSection: some View {
        HStack(spacing: 6) {
            Image(systemName: "xmark.circle")
                .foregroundStyle(.red)
                .font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                Text(pipelineService.lastErrorCode ?? "오류")
                    .font(.caption)
                    .bold()
                if let msg = pipelineService.lastErrorMessage {
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(8)
        .background(Color.red.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("설정")
                .font(.caption)
                .foregroundStyle(.secondary)

            runnerPathPreview
            pathField(title: "리포트 저장 경로", path: $dataBasePath)

            VStack(alignment: .leading, spacing: 4) {
                Text("관심사 키워드")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                TextField("예: AI, 개발, 생산성, 자동화", text: $interestKeywords)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }

            youtubeChannelSection
        }
    }

    private var youtubeChannelSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YouTube 채널")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if youtubeChannelIds.isEmpty {
                Text("등록된 채널 없음")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                ForEach(youtubeChannelIds, id: \.self) { channelId in
                    HStack(spacing: 4) {
                        Image(systemName: "play.rectangle")
                            .font(.caption2)
                            .foregroundStyle(.red)
                        Text(channelId)
                            .font(.caption2)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            removeChannel(channelId)
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 4) {
                TextField("채널 ID 또는 URL", text: $newChannelInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption2)
                    .onSubmit { addChannel() }
                Button("추가") { addChannel() }
                    .controlSize(.mini)
                    .disabled(newChannelInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var runnerPathPreview: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Runner")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(Constants.defaultNewsRunnerPath.isEmpty ? "자동 감지 실패" : Constants.defaultNewsRunnerPath)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    private func pathField(title: String, path: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            HStack(spacing: 4) {
                TextField("경로", text: path)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption2)
                Button("변경") {
                    if let selected = selectDirectory() {
                        path.wrappedValue = selected
                    }
                }
                .controlSize(.mini)
            }
        }
    }

    private var youtubeChannelIds: [String] {
        youtubeChannelIdsRaw
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func launchJob() {
        applyDefaultPathsIfNeeded()
        let resolvedRunnerPath = Constants.defaultNewsRunnerPath
        let resolvedDataBasePath = dataBasePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let keywords = interestKeywords
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        pipelineService.startJob(
            provider: selectedProvider,
            runnerPath: resolvedRunnerPath,
            dataBasePath: resolvedDataBasePath,
            interestKeywords: keywords.isEmpty ? Constants.defaultNewsInterestKeywords.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } : keywords,
            youtubeChannelIds: youtubeChannelIds,
            context: modelContext
        )
    }

    private func applyDefaultPathsIfNeeded() {
        if dataBasePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            dataBasePath = Constants.defaultNewsDataBasePath
        }
    }

    private func addChannel() {
        let raw = newChannelInput.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        let channelId = extractChannelId(from: raw)
        guard !channelId.isEmpty, !youtubeChannelIds.contains(channelId) else {
            newChannelInput = ""
            return
        }
        var ids = youtubeChannelIds
        ids.append(channelId)
        youtubeChannelIdsRaw = ids.joined(separator: ",")
        newChannelInput = ""
    }

    private func removeChannel(_ channelId: String) {
        var ids = youtubeChannelIds
        ids.removeAll { $0 == channelId }
        youtubeChannelIdsRaw = ids.joined(separator: ",")
    }

    private func extractChannelId(from input: String) -> String {
        if let url = URL(string: input) {
            let components = url.pathComponents
            if let idx = components.firstIndex(of: "channel"), components.indices.contains(idx + 1) {
                return components[idx + 1]
            }
            if let idx = components.firstIndex(of: "@"), components.indices.contains(idx + 1) {
                return "@" + components[idx + 1]
            }
            if let last = components.last, last.hasPrefix("UC") {
                return last
            }
        }
        return input
    }

    private func stepLabel(_ step: String) -> String {
        switch step {
        case "queued":        return "대기 중..."
        case "collect":       return "뉴스 수집 중..."
        case "normalize":     return "정규화 중..."
        case "dedupe":        return "중복 제거 중..."
        case "classify":      return "카테고리 분류 중..."
        case "rank":          return "중요도 정렬 중..."
        case "summarize":     return "요약 생성 중..."
        case "render":        return "리포트 작성 중..."
        case "index":         return "인덱싱 중..."
        case "success":       return "✅ 완료"
        case "partial_success": return "⚠️ 부분 성공"
        case "failed":        return "❌ 실패"
        default: return step.isEmpty ? "준비 중..." : step
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter.string(from: date)
    }

    private func selectDirectory() -> String? {
        let panel = NSOpenPanel()
        panel.prompt = "선택"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
