import SwiftUI
import AppKit

/*
 뉴스 리포트 팝오버의 화면 표현과 수동 생성 진입 흐름을 담당한다.

 이 파일의 책임
 - Provider·예상/실제 사용량·생성 단계·경고·오류·최근 리포트를 팝오버에 표시한다.
 - 뉴스 설정을 `AppStorage`에 반영하고, 최근 리포트와 실행 기록을 SwiftData에서 조회한다.
 - 리포트 생성·중단 요청을 전달하고, Ollama 모델의 설치 여부 확인과 사용자 동의·진행 상태를 조율한다.
 - YouTube 채널 입력을 정리하고, 선택한 리포트를 전체 리포트 창에서 열도록 연결한다.

 이 파일의 책임이 아닌 것
 - 뉴스 수집·정규화·중복 제거·분류·정렬·요약·Markdown 생성은 뉴스 Python 에이전트가 담당한다.
 - 에이전트 프로세스 실행, 진행 상태 수신과 작업·리포트 인덱스 저장은 `NewsPipelineService`가 담당한다.
 - 실행 인자 조립과 마지막 실행 시각 기록은 `NewsPipelineLaunchConfiguration`이 담당한다.
 - 자동 실행 시점 결정은 `NewsScheduler`, 전체 리포트 탐색은 `NewsReportArchiveWindow`가 담당한다.

 현재는 화면 표시만 하지 않고 수동 실행 전 확인과 시작까지 조율한다. 이 흐름이 다른 화면에서도
 필요해지거나 복잡해지면 View에 더 쌓지 말고 별도 ViewModel 또는 실행 조율 타입으로 옮긴다.
 */

struct NewsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.appearanceDensity) private var appearanceDensity
    @AppStorage(Constants.NewsStorageKey.dataBasePath) private var dataBasePath = Constants.defaultNewsDataBasePath
    @AppStorage(Constants.NewsStorageKey.selectedProvider) private var selectedProvider = Constants.defaultNewsProvider
    @AppStorage(Constants.NewsStorageKey.ollamaModel) private var ollamaModel = Constants.defaultNewsOllamaModel
    @AppStorage(Constants.NewsStorageKey.ollamaEndpoint) private var ollamaEndpoint = Constants.defaultNewsOllamaEndpoint
    @AppStorage(Constants.NewsStorageKey.ollamaTimeout) private var ollamaTimeout = Constants.defaultNewsOllamaTimeout
    @AppStorage(Constants.NewsStorageKey.interestKeywords) private var interestKeywords = Constants.defaultNewsInterestKeywords
    @AppStorage(Constants.NewsStorageKey.youtubeChannelIds) private var youtubeChannelIdsRaw = ""
    @AppStorage(Constants.NewsStorageKey.schedule) private var schedule = Constants.defaultNewsSchedule
    @AppStorage(Constants.NewsStorageKey.scheduleNextSlotAt) private var nextSlotAtRaw: Double = 0

    @State private var newChannelInput = ""
    @State private var showExecutionEnvironmentAlert = false
    @State private var executionEnvironmentAlertMessage = ""
    @State private var showRateLimitAlert = false
    @State private var showOllamaInstallAlert = false
    @State private var ollamaInstallAlertMessage = ""
    @State private var isPreparingOllama = false
    @State private var ollamaInstallStatus = ""
    @State private var ollamaInstallProgress: Double?
    @State private var isRunButtonHovered = false
    @AppStorage(Constants.NewsStorageKey.maxItemsPerSource) private var maxItemsPerSource = Constants.defaultNewsMaxItemsPerSource
    @State private var viewModel: NewsViewModel
    /// 고른 리포트의 `jobId`. 보관함 창에 무엇을 열지 알려줄 때만 쓴다.
    @State private var selectedReportID: String?
    @State private var hostWindow: NSWindow?

    init(repository: NewsRepository, pipeline: NewsPipelineGateway) {
        _viewModel = State(initialValue: NewsViewModel(repository: repository, pipeline: pipeline))
    }

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

                    // 실행 중에는 예측 대신 진행 상황(statusSection)을 보여준다.
                    if !pipelineService.isRunning, let usageEstimate {
                        NewsUsageEstimateLabel(estimate: usageEstimate)
                    }

                    if let usage = viewModel.lastReportedUsage {
                        NewsUsageActualLabel(usage: usage)
                    }

                    if let nextCollectionText {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 9))
                            Text("다음 자동 수집 \(nextCollectionText)")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(PopoverChrome.inkSecondary)
                    }

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
            .popoverScrollbar()

            if showExecutionEnvironmentAlert {
                popoverAlertOverlay
            }
            if showRateLimitAlert {
                rateLimitAlertOverlay
            }
            if showOllamaInstallAlert {
                ollamaInstallConfirmOverlay
            }
        }
        .onAppear {
            applyDefaultPathsIfNeeded()
            viewModel.reload()
        }
        .configureHostWindow { window in
            hostWindow = window
        }
        .onReceive(NotificationCenter.default.publisher(for: .newsPipelineJobFinished)) { _ in
            // `@Query` 를 걷어낸 자리. 리포트와 실행 이력은 파이프라인이 끝날 때만 늘어난다.
            viewModel.reload()
            if pipelineService.lastJobStatus == "failed", let err = pipelineService.lastErrorMessage {
                let lowerErr = err.lowercased()
                if lowerErr.contains("rate limit") || lowerErr.contains("usage limit") || lowerErr.contains("429") || lowerErr.contains("exceeded") || err.contains("한도") || err.contains("제한") {
                    showRateLimitAlert = true
                }
            }
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

    /// 자동 수집이 예약되어 있을 때만 다음 시각을 보여준다. `수동` 모드면 nil.
    private var nextCollectionText: String? {
        guard Constants.NewsScheduleMode.normalized(rawValue: schedule) != .manual,
              nextSlotAtRaw > 0 else { return nil }
        return NewsSchedulePlan.displayText(for: Date(timeIntervalSince1970: nextSlotAtRaw))
    }

    /// 자동 수집이 도는 중이라는 것을 라벨로 구분한다.
    /// 중복 실행 방지는 이미 되어 있다 — 실행 중에는 버튼 자체가 `중단` 으로 바뀐다.
    private var runButtonTitle: String {
        if pipelineService.isRunning {
            return NewsScheduler.shared.isAutoRunInFlight ? "자동 수집 중… 중단" : "중단"
        }
        return isPreparingOllama ? "모델 준비 중" : "리포트 생성"
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
                Text(runButtonTitle)
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
                        .fill(PopoverChrome.primaryButtonFill)
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
        let availableReports = availableRecentReports

        return VStack(alignment: .leading, spacing: appearanceDensity.popoverMetric(8)) {
            HStack(spacing: 8) {
                Text("최근 리포트")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                Spacer()
                Button {
                    openReportArchive(report: nil)
                } label: {
                    HStack(spacing: 3) {
                        Text("모든 리포트")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8.5, weight: .bold))
                    }
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                }
                .buttonStyle(.plain)
            }

            if availableReports.isEmpty {
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
                ForEach(availableReports.prefix(5)) { report in
                    reportRow(report: report)
                }
            }
        }
    }

    private var availableRecentReports: [NewsReport] {
        viewModel.availableReports(dataBasePath: dataBasePath)
    }

    private func reportRow(report: NewsReport) -> some View {
        Button {
            selectedReportID = report.jobId
            openReportArchive(report: report)
        } label: {
            HStack(alignment: .center, spacing: appearanceDensity.popoverMetric(10)) {
                VStack(alignment: .leading, spacing: appearanceDensity.popoverMetric(2)) {
                    Text(formatDate(report.reportDate))
                        .font(.system(size: appearanceDensity.popoverMetric(10.5), weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                    Text(report.topTitle)
                        .font(.system(size: appearanceDensity.popoverMetric(12.5), weight: .medium, design: .rounded))
                        .lineLimit(2)
                        .foregroundStyle(PopoverChrome.ink)
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10, weight: .medium))
                    Text("\(report.itemCount)개")
                        .font(.system(size: appearanceDensity.popoverMetric(11), weight: .medium, design: .rounded))
                }
                .foregroundStyle(PopoverChrome.inkSecondary)
            }
            .popoverCard(padding: appearanceDensity.popoverMetric(12), radius: 10)
            .background(
                selectedReportID == report.jobId
                    ? PopoverChrome.accentSoft.opacity(0.22)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private func openReportArchive(report: NewsReport?) {
        NewsReportArchiveSelection.shared.select(reportID: report?.jobId)
        HubWindowPresenter.present(
            tab: .news,
            appState: appState,
            popoverWindow: hostWindow,
            openWindow: openWindow
        )
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

    private var rateLimitAlertOverlay: some View {
        popoverModalOverlay {
            VStack(alignment: .leading, spacing: 12) {
                modalTitleRow(icon: "exclamationmark.triangle.fill", title: "토큰 사용량 제한 초과")
                Text("구독제 Provider의 사용량 한도(5시간당 한도 또는 주간 한도 등)를 초과하여 더 이상 리포트를 생성할 수 없습니다. 한도가 초기화된 후 다시 시도해주세요.")
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                if let msg = pipelineService.lastErrorMessage {
                    ScrollView {
                        Text(msg)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(PopoverChrome.inkTertiary)
                    }
                    .frame(maxHeight: 60)
                }

                HStack {
                    Spacer()
                    Button("확인") {
                        showRateLimitAlert = false
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

    /// 현재 설정으로 실행했을 때의 예상 소모량.
    private var usageEstimate: NewsUsageEstimate? {
        viewModel.usageEstimate(
            provider: selectedProvider,
            interestKeywords: interestKeywordList,
            youtubeChannelIds: youtubeChannelIds,
            maxItemsPerSource: maxItemsPerSource
        )
    }

    private var interestKeywordList: [String] {
        interestKeywords
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
        viewModel.launchPipeline()
        if pipelineService.lastErrorCode == "E_ENV" || pipelineService.lastErrorCode == "E_PROVIDER_CLI" {
            executionEnvironmentAlertMessage = pipelineService.lastErrorMessage ?? "uv 또는 Python 3 실행 환경을 확인해주세요."
            showExecutionEnvironmentAlert = true
        }
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
