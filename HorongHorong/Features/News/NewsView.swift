import SwiftUI
import SwiftData
import AppKit

struct NewsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @AppStorage(Constants.NewsStorageKey.dataBasePath) private var dataBasePath = Constants.defaultNewsDataBasePath
    @AppStorage(Constants.NewsStorageKey.selectedProvider) private var selectedProvider = Constants.defaultNewsProvider
    @AppStorage(Constants.NewsStorageKey.ollamaModel) private var ollamaModel = Constants.defaultNewsOllamaModel
    @AppStorage(Constants.NewsStorageKey.ollamaEndpoint) private var ollamaEndpoint = Constants.defaultNewsOllamaEndpoint
    @AppStorage(Constants.NewsStorageKey.ollamaTimeout) private var ollamaTimeout = Constants.defaultNewsOllamaTimeout
    @AppStorage(Constants.NewsStorageKey.interestKeywords) private var interestKeywords = Constants.defaultNewsInterestKeywords
    @AppStorage(Constants.NewsStorageKey.youtubeChannelIds) private var youtubeChannelIdsRaw = ""
    @AppStorage(Constants.NewsStorageKey.maxItemsPerSource) private var maxItemsPerSource: Int = Constants.defaultNewsMaxItemsPerSource

    @State private var newChannelInput = ""
    @State private var showExecutionEnvironmentAlert = false
    @State private var executionEnvironmentAlertMessage = ""
    @State private var showOllamaInstallAlert = false
    @State private var ollamaInstallAlertMessage = ""
    @State private var isPreparingOllama = false
    @State private var ollamaInstallStatus = ""
    @State private var ollamaInstallProgress: Double?
    @State private var isRunButtonHovered = false
    @Query(sort: \NewsReportIndex.createdAt, order: .reverse) private var recentReports: [NewsReportIndex]
    @State private var selectedReport: NewsReportIndex?

    private let pipelineSteps = ["collect", "normalize", "dedupe", "classify", "rank", "summarize", "render"]
    private var pipelineService: NewsPipelineService { appState.newsPipelineService }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center) {
                        header
                        Spacer()
                        providerMenu
                    }

                    runButton

                    if isPreparingOllama {
                        ollamaInstallProgressSection
                    }
                    if pipelineService.isRunning {
                        statusSection
                    }
                    if !pipelineService.lastWarnings.isEmpty {
                        warningsSection
                    }
                    reportsSection
                    if pipelineService.lastErrorCode != nil {
                        errorSection
                    }
                }
                .padding(.trailing, 12)
            }

            if showExecutionEnvironmentAlert {
                popoverAlertOverlay
            }
            if showOllamaInstallAlert {
                ollamaInstallConfirmOverlay
            }
        }
        .onAppear {
            applyDefaultPathsIfNeeded()
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "newspaper")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(PopoverChrome.accent)
            Text("뉴스 큐레이션")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
        }
    }

    private var providerMenu: some View {
        Menu {
            ForEach(Constants.availableNewsProviders, id: \.self) { provider in
                Button {
                    selectedProvider = provider
                } label: {
                    Text(provider.capitalized)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("Provider")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                Text(selectedProvider.capitalized)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                if selectedProvider == "ollama" {
                    Text(cleanOllamaModel)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(PopoverChrome.inkSecondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 11)
            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous)
                    .stroke(PopoverChrome.divider, lineWidth: PopoverChrome.borderWidth)
            )
        }
        .buttonStyle(.plain)
    }

    private var runButton: some View {
        Button {
            if pipelineService.isRunning {
                pipelineService.cancelJob()
            } else {
                Task { await launchJob() }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: pipelineService.isRunning ? "stop.fill" : (isPreparingOllama ? "arrow.down.circle" : "sparkles"))
                    .font(.system(size: 10, weight: .bold))
                Text(pipelineService.isRunning ? "중단" : (isPreparingOllama ? "모델 준비 중" : "리포트 생성"))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .foregroundStyle(PopoverChrome.accentInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background {
                if PopoverChrome.isGamePixel || PopoverChrome.isWineLantern {
                    ZStack {
                        if PopoverChrome.isGamePixel {
                            RoundedRectangle(cornerRadius: PopoverChrome.controlRadius, style: .continuous)
                                .fill(PopoverChrome.pixelShadow)
                                .offset(x: 3, y: 3)
                        }
                        RoundedRectangle(cornerRadius: PopoverChrome.controlRadius, style: .continuous)
                            .fill(PopoverChrome.accent)
                    }
                } else {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.00, green: 0.59, blue: 0.22),
                                    Color(red: 0.94, green: 0.45, blue: 0.16),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: PopoverChrome.controlRadius, style: .continuous)
                    .stroke(PopoverChrome.isGamePixel ? PopoverChrome.border : Color.clear, lineWidth: PopoverChrome.borderWidth)
            )
            .shadow(
                color: PopoverChrome.isGamePixel ? .clear : PopoverChrome.accent.opacity(isRunButtonHovered ? 0.38 : 0.28),
                radius: PopoverChrome.isGamePixel ? 0 : (isRunButtonHovered ? 15 : 12),
                x: 0,
                y: PopoverChrome.isGamePixel ? 0 : (isRunButtonHovered ? 9 : 7)
            )
        }
        .buttonStyle(.plain)
        .offset(y: isRunButtonHovered ? -2 : 0)
        .animation(.easeOut(duration: 0.16), value: isRunButtonHovered)
        .onHover { isHovering in
            isRunButtonHovered = isHovering
        }
        .disabled(isPreparingOllama)
    }

    private var ollamaInstallProgressSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PopoverChrome.accent)
                Text(ollamaInstallStatus.isEmpty ? "Ollama 모델 준비 중..." : ollamaInstallStatus)
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .lineLimit(2)
                Spacer()
                if let progress = ollamaInstallProgress {
                    Text("\(Int(progress * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(PopoverChrome.inkTertiary)
                }
            }

            if let progress = ollamaInstallProgress {
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(.linear)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .popoverCard(padding: 10)
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.7)
                Text(stepLabel(pipelineService.currentStep))
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
                Spacer()
                Text("\(pipelineService.elapsedSeconds)초")
                    .font(.caption2)
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }
            HStack(spacing: 4) {
                ForEach(pipelineSteps, id: \.self) { step in
                    stepDot(step: step)
                }
            }
        }
        .popoverCard(padding: 10)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("최근 리포트")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)

            if recentReports.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "newspaper")
                        .foregroundStyle(PopoverChrome.inkTertiary)
                    Text("아직 생성된 리포트가 없습니다")
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.inkSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .popoverCard()
            } else {
                ForEach(recentReports.prefix(5)) { report in
                    reportRow(report: report)
                }
            }
        }
    }

    private func reportRow(report: NewsReportIndex) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(formatDate(report.reportDate))
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                Text(report.topTitle)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .lineLimit(2)
                    .foregroundStyle(PopoverChrome.ink)
            }
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .font(.system(size: 10, weight: .medium))
                Text("\(report.itemCount)개")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
            .foregroundStyle(PopoverChrome.inkSecondary)
        }
        .popoverCard(padding: 12, radius: 10)
        .background(
            selectedReport?.jobId == report.jobId
                ? PopoverChrome.accentSoft.opacity(0.22)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedReport = report
            NSWorkspace.shared.open(URL(fileURLWithPath: report.reportPath))
        }
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

    private var popoverAlertOverlay: some View {
        popoverModalOverlay {
            VStack(alignment: .leading, spacing: 12) {
                modalTitleRow(icon: "exclamationmark.triangle", title: "뉴스 리포트 실행 환경이 필요합니다")
                Text(executionEnvironmentAlertMessage)
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    Button("확인") {
                        showExecutionEnvironmentAlert = false
                    }
                    .buttonStyle(LanternPrimaryButtonStyle())
                }
            }
        }
    }

    private var ollamaInstallConfirmOverlay: some View {
        popoverModalOverlay {
            VStack(alignment: .leading, spacing: 12) {
                modalTitleRow(icon: "arrow.down.circle", title: "Ollama 모델 설치")
                Text(ollamaInstallAlertMessage)
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Spacer()
                    Button("취소") {
                        showOllamaInstallAlert = false
                    }
                    .buttonStyle(LanternSecondaryButtonStyle())
                    Button("설치 후 생성") {
                        showOllamaInstallAlert = false
                        Task { await installOllamaAndLaunchJob() }
                    }
                    .buttonStyle(LanternPrimaryButtonStyle())
                }
            }
        }
    }

    private func modalTitleRow(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PopoverChrome.accent)
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
        }
    }

    private func popoverModalOverlay<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
            content()
                .padding(14)
                .frame(maxWidth: 310, alignment: .leading)
                .background(PopoverChrome.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(PopoverChrome.border, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 10)
                .padding(.horizontal, 14)
        }
        .transition(.opacity)
        .zIndex(10)
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("설정")
                .font(.caption)
                .foregroundStyle(PopoverChrome.inkTertiary)

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
        .popoverCard()
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

    private var cleanOllamaModel: String {
        let trimmed = ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Constants.defaultNewsOllamaModel : trimmed
    }

    private var cleanOllamaEndpoint: String {
        let trimmed = ollamaEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Constants.defaultNewsOllamaEndpoint : trimmed
    }

    private func launchJob() async {
        applyDefaultPathsIfNeeded()
        if selectedProvider == "ollama" {
            await preflightOllamaOrPromptInstall()
            return
        }
        startPipelineJob()
    }

    private func preflightOllamaOrPromptInstall() async {
        isPreparingOllama = true
        ollamaInstallStatus = "Ollama 모델 설치 여부 확인 중..."
        ollamaInstallProgress = nil
        defer { isPreparingOllama = false }

        do {
            let installed = try await pipelineService.isOllamaModelInstalled(
                model: cleanOllamaModel,
                endpoint: cleanOllamaEndpoint
            )
            if installed {
                startPipelineJob()
                return
            }

            ollamaInstallAlertMessage = """
            선택한 Ollama 모델이 이 Mac에 설치되어 있지 않습니다.

            모델: \(cleanOllamaModel)

            모델을 다운로드한 뒤 리포트를 생성할까요?
            """
            showOllamaInstallAlert = true
        } catch {
            executionEnvironmentAlertMessage = error.localizedDescription
            showExecutionEnvironmentAlert = true
        }
    }

    private func installOllamaAndLaunchJob() async {
        applyDefaultPathsIfNeeded()
        isPreparingOllama = true
        ollamaInstallStatus = "Ollama 모델 다운로드 준비 중..."
        ollamaInstallProgress = nil
        defer { isPreparingOllama = false }

        do {
            try await pipelineService.installOllamaModel(
                model: cleanOllamaModel,
                dataBasePath: dataBasePath.trimmingCharacters(in: .whitespacesAndNewlines),
                progress: { progress in
                    ollamaInstallStatus = progress.message
                    ollamaInstallProgress = progress.fraction
                }
            )
            startPipelineJob()
        } catch {
            executionEnvironmentAlertMessage = error.localizedDescription
            showExecutionEnvironmentAlert = true
        }
    }

    private func startPipelineJob() {
        let resolvedRunnerPath = Constants.defaultNewsRunnerPath
        let resolvedDataBasePath = dataBasePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let keywords = interestKeywords
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        pipelineService.startJob(
            provider: selectedProvider,
            providerOptions: providerOptions,
            runnerPath: resolvedRunnerPath,
            dataBasePath: resolvedDataBasePath,
            interestKeywords: keywords,
            youtubeChannelIds: youtubeChannelIds,
            maxItemsPerSource: maxItemsPerSource,
            context: modelContext
        )
        if pipelineService.lastErrorCode == "E_ENV" || pipelineService.lastErrorCode == "E_PROVIDER_CLI" {
            executionEnvironmentAlertMessage = pipelineService.lastErrorMessage ?? "uv 또는 Python 3 실행 환경을 확인해주세요."
            showExecutionEnvironmentAlert = true
        }
    }

    private var providerOptions: NewsProviderOptionsPayload? {
        guard selectedProvider == "ollama" else { return nil }
        return NewsProviderOptionsPayload(
            model: cleanOllamaModel,
            endpoint: cleanOllamaEndpoint,
            timeout: ollamaTimeout
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
