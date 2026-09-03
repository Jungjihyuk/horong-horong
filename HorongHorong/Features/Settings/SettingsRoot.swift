import HorongAI
import HorongAIMLX
import SwiftUI

struct SettingsRoot: View {
    @Environment(\.dependencies) private var dependencies
    @State private var selection: SettingsTab = .general
    @State private var query: String = ""
    @State private var showResetConfirm: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var hostWindow: NSWindow?
    @AppStorage(Constants.AppStorageKey.appearanceMode)
    private var appearanceMode: String = Constants.defaultAppearanceMode
    @AppStorage(Constants.AppStorageKey.appearanceDensity)
    private var appearanceDensityRaw: String = Constants.defaultAppearanceDensity

    init(initialSelection: SettingsTab = .general) {
        _selection = State(initialValue: initialSelection)
    }

    /// 화면 모드를 SwiftUI ColorScheme 으로 (nil = 시스템 따라감).
    private var colorScheme: ColorScheme? {
        switch appearanceMode {
        case "dark":  return .dark
        case "light": return .light
        default:      return nil
        }
    }

    private var appearanceDensity: AppearanceDensity {
        AppearanceDensity.normalized(rawValue: appearanceDensityRaw)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SettingsSidebar(selection: $selection, query: $query)
                .navigationSplitViewColumnWidth(min: 200, ideal: SettingsTheme.sidebarWidth, max: 280)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            VStack(spacing: 0) {
                detailView
                Divider()
                footerBar
            }
        }
        .navigationTitle("설정 — \(selection.label)")
        .frame(
            minWidth: SettingsTheme.windowMinSize.width,
            minHeight: SettingsTheme.windowMinSize.height
        )
        .configureHostWindow { window in
            hostWindow = window
            configureWindowChrome(window)
        }
        .preferredColorScheme(colorScheme)
        .environment(\.appearanceDensity, appearanceDensity)
        .dynamicTypeSize(appearanceDensity.dynamicTypeSize)
        .controlSize(appearanceDensity.controlSize)
        .appearanceAccentTint(.adaptive)
        .onChange(of: appearanceMode) { _, newValue in
            applyAppearance(newValue, to: hostWindow)
        }
        .onChange(of: columnVisibility) { _, _ in
            configureWindowChrome(hostWindow)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .companionOnboardingPerform)
        ) { notification in
            // 온보딩이 설명하는 페이지로 옮겨준다.
            guard let action = notification.object as? String,
                  action.hasPrefix("settings.show:"),
                  let tab = SettingsTab(rawValue: String(action.dropFirst("settings.show:".count))),
                  SettingsTab.visibleCases.contains(tab)
            else { return }
            selection = tab
        }
        .alert("기본값으로 복원하시겠어요?", isPresented: $showResetConfirm) {
            Button("취소", role: .cancel) {}
            Button("복원", role: .destructive) {
                resetToDefaults(for: selection)
            }
        } message: {
            Text("\(selection.label) 페이지의 설정만 기본값으로 되돌립니다.")
        }
    }

    private func collapseSidebar() {
        withAnimation { columnVisibility = .detailOnly }
    }

    private func expandSidebar() {
        withAnimation { columnVisibility = .all }
    }

    private func configureWindowChrome(_ window: NSWindow?) {
        guard let window else { return }

        // 최소화/확대 + fullSizeContentView 로 사이드바 배경이 트래픽 라이트 영역까지 확장된다.
        window.styleMask.insert([.miniaturizable, .resizable, .fullSizeContentView])
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        if window.horongTrafficLightController == nil {
            window.horongTrafficLightController = TrafficLightInsetController(window: window, dx: 6, dy: -4)
        }
        if window.horongSidebarToggleController == nil {
            window.horongSidebarToggleController = SettingsSidebarToggleController(window: window)
        }
        window.horongSidebarToggleController?.update(isSidebarVisible: columnVisibility == .all) {
            if columnVisibility == .all {
                collapseSidebar()
            } else {
                expandSidebar()
            }
        }
        applyAppearance(appearanceMode, to: window)
    }

    /// 설정 윈도우 *한 개만* 라이트/다크/시스템 모드를 따르도록 NSWindow.appearance 를 갱신한다.
    /// NSApp.appearance 를 건드리지 않아 팝오버·통계 윈도우는 영향을 받지 않는다.
    private func applyAppearance(_ mode: String, to window: NSWindow?) {
        guard let window else { return }
        switch mode {
        case "dark":
            window.appearance = NSAppearance(named: .darkAqua)
        case "light":
            window.appearance = NSAppearance(named: .aqua)
        default:
            window.appearance = nil  // 시스템 따라감
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .general:    GeneralPage()
        case .appearance: AppearancePage()
        case .timer:      TimerPage()
        case .hotkey:     HotkeyPage()
        case .category:
            if let dependencies {
                CategoryMappingPage(
                    repository: dependencies.appUsageRepository,
                    statsRepository: dependencies.statsRecordRepository
                )
            }
        case .stats:
            if let dependencies {
                StatsPage(repository: dependencies.statsRecordRepository)
            }
        case .focus:
            if let dependencies {
                FocusPage(repository: dependencies.statsRecordRepository)
            }
        case .achievement: AchievementPage()
        case .news:       NewsPage()
        case .lab:      LabPage()
        case .companion:  CompanionPage()
        case .memo:
            if let dependencies {
                MemoPage(reminderImports: dependencies.reminderImportRepository)
            }
        case .data:       DataPage()
        case .about:      AboutPage()
        case .ailab:
            if let dependencies {
                AILabView(repository: dependencies.achievementRepository)
            }
        }
    }

    private var footerBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
            Text("모든 변경 사항은 즉시 적용됩니다")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("기본값으로 복원") {
                showResetConfirm = true
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.03))
    }

    private func resetToDefaults(for tab: SettingsTab) {
        let defaults = UserDefaults.standard
        switch tab {
        case .appearance:
            defaults.removeObject(forKey: Constants.AppStorageKey.appearanceMode)
            defaults.removeObject(forKey: Constants.AppStorageKey.appearanceDensity)
            defaults.removeObject(forKey: Constants.AppStorageKey.popoverTheme)
            defaults.removeObject(forKey: Constants.AppStorageKey.menubarIcon)
            defaults.removeObject(forKey: Constants.AppStorageKey.appIcon)
            defaults.removeObject(forKey: Constants.AppStorageKey.warmLanternAccent)
            defaults.removeObject(forKey: Constants.AppStorageKey.wineLanternAccent)
            defaults.removeObject(forKey: Constants.AppStorageKey.gamePixelAccent)
            AppIconManager.apply(.horong)
        case .timer:
            defaults.removeObject(forKey: Constants.AppStorageKey.pomodoroFocusMinutes)
            defaults.removeObject(forKey: Constants.AppStorageKey.pomodoroBreakMinutes)
            defaults.removeObject(forKey: Constants.AppStorageKey.longFocusFocusMinutes)
            defaults.removeObject(forKey: Constants.AppStorageKey.longFocusBreakMinutes)
            defaults.removeObject(forKey: Constants.AppStorageKey.customFocusMinutes)
            defaults.removeObject(forKey: Constants.AppStorageKey.customBreakMinutes)
            defaults.removeObject(forKey: Constants.AppStorageKey.postBreakTransitionPromptMode)
            defaults.removeObject(forKey: Constants.AppStorageKey.postBreakTransitionPromptDelayMinutes)
            defaults.removeObject(forKey: Constants.AppStorageKey.timerCompletionNotificationStyle)
            defaults.removeObject(forKey: Constants.AppStorageKey.menubarLabelStyle)
            defaults.removeObject(forKey: Constants.AppStorageKey.menubarTimeStyle)
        case .stats:
            defaults.removeObject(forKey: Constants.AppStorageKey.timelineStartHour)
            defaults.removeObject(forKey: Constants.AppStorageKey.timelineEndHour)
            defaults.removeObject(forKey: Constants.AppStorageKey.timelineBucketMinutes)
        case .focus:
            defaults.removeObject(forKey: Constants.AppStorageKey.companionFocusNudgeEnabled)
            defaults.removeObject(forKey: Constants.AppStorageKey.companionFocusNudgeMessages)
            defaults.removeObject(forKey: Constants.AppStorageKey.companionFocusNudgeLastMessage)
            defaults.removeObject(forKey: Constants.AppStorageKey.companionFocusNudgeDetectionMode)
            defaults.removeObject(forKey: Constants.AppStorageKey.companionFocusNudgeRequiredFeedbackCount)
            defaults.removeObject(forKey: Constants.AppStorageKey.companionFocusNudgeManualFocusPercent)
            defaults.removeObject(forKey: Constants.AppStorageKey.companionFocusNudgeManualMaxAppSwitches)
            defaults.removeObject(forKey: Constants.AppStorageKey.companionFocusNudgeFrequencyMode)
            defaults.removeObject(forKey: Constants.AppStorageKey.companionFocusNudgeMaximumPerSession)
            defaults.removeObject(forKey: Constants.AppStorageKey.companionFocusNudgePendingEvents)
            defaults.removeObject(forKey: Constants.AppStorageKey.companionFocusNudgeSessionState)
        case .achievement:
            defaults.removeObject(forKey: Constants.AppStorageKey.achievementSuggestionCount)
            defaults.removeObject(forKey: Constants.AppStorageKey.achievementSuggestionMaxTodoCount)
            defaults.removeObject(forKey: Constants.AppStorageKey.achievementMonthlySuggestionMinWeeklyGoalCount)
            defaults.removeObject(forKey: Constants.AppStorageKey.achievementMonthlySuggestionCount)
            defaults.removeObject(forKey: Constants.AppStorageKey.achievementSuggestionExcludedMemoIcons)
            defaults.removeObject(forKey: Constants.AppStorageKey.achievementTimelineSortOrder)
            defaults.removeObject(forKey: Constants.AppStorageKey.achievementDismissedSuggestionKeys)
            defaults.removeObject(forKey: Constants.AppStorageKey.achievementJourneyMaxFlagCount)
            defaults.removeObject(forKey: Constants.AppStorageKey.achievementSuggestionProvider)
            defaults.removeObject(forKey: Constants.AppStorageKey.achievementSuggestionMLXModel)
            defaults.removeObject(forKey: Constants.AppStorageKey.achievementSuggestionOllamaModel)
            defaults.removeObject(forKey: Constants.AppStorageKey.achievementJourneyFlagSelections)
        case .news:
            defaults.removeObject(forKey: Constants.NewsStorageKey.interestKeywords)
            defaults.removeObject(forKey: Constants.NewsStorageKey.selectedProvider)
        case .lab:
            defaults.removeObject(forKey: Constants.AppStorageKey.agentRootDirectoryPath)
            defaults.removeObject(forKey: Constants.AppStorageKey.selectedAgentType)
            defaults.removeObject(forKey: Constants.AppStorageKey.planDayCount)
            defaults.removeObject(forKey: Constants.AppStorageKey.interestKeywords)
        case .companion:
            defaults.removeObject(forKey: Constants.AppStorageKey.companionEnabled)
            defaults.removeObject(forKey: Constants.AppStorageKey.companionSelectedIdentifier)
            defaults.removeObject(forKey: Constants.AppStorageKey.companionRoamingRegion)
            defaults.removeObject(forKey: Constants.AppStorageKey.companionHideDuringFocus)
            defaults.removeObject(forKey: Constants.AppStorageKey.companionBriefingEnabled)
            defaults.removeObject(forKey: Constants.AppStorageKey.companionBriefingHour)
            defaults.removeObject(forKey: Constants.AppStorageKey.companionBriefingMinute)
        case .memo:
            defaults.removeObject(forKey: Constants.AppStorageKey.remindersImportEnabled)
            defaults.removeObject(forKey: Constants.AppStorageKey.remindersImportSelectedCalendarIDs)
        case .category:
            defaults.removeObject(forKey: Constants.AppStorageKey.hiddenDefaultCategoryRuleBundleIDs)
            defaults.removeObject(forKey: Constants.AppStorageKey.unmappedAppHandling)
            for category in Constants.allCategories {
                IdleThresholdStore.shared.resetToDefault(category: category)
            }
        default:
            break
        }
    }
}

private struct AchievementPage: View {
    @AppStorage(Constants.AppStorageKey.achievementSuggestionCount)
    private var weeklySuggestionLimit: Int = Constants.defaultAchievementSuggestionCount
    @AppStorage(Constants.AppStorageKey.achievementSuggestionMaxTodoCount)
    private var maxTodosPerWeeklyGoal: Int = Constants.defaultAchievementSuggestionMaxTodoCount
    @AppStorage(Constants.AppStorageKey.achievementMonthlySuggestionMinWeeklyGoalCount)
    private var minWeeklyGoalsForMonthlySuggestions: Int = Constants.defaultAchievementMonthlySuggestionMinWeeklyGoalCount
    @AppStorage(Constants.AppStorageKey.achievementMonthlySuggestionCount)
    private var monthlySuggestionLimit: Int = Constants.defaultAchievementMonthlySuggestionCount
    @AppStorage(Constants.AppStorageKey.achievementMinTodosForWeeklySuggestions)
    private var minTodosForWeeklySuggestions: Int = Constants.defaultAchievementMinTodosForWeeklySuggestions
    @AppStorage(Constants.AppStorageKey.achievementMaxWeeklyGoalsPerMonthlyGoal)
    private var maxWeeklyGoalsPerMonthlyGoal: Int = Constants.defaultAchievementMaxWeeklyGoalsPerMonthlyGoal
    @AppStorage(Constants.AppStorageKey.achievementSuggestionExcludedMemoIcons)
    private var excludedMemoIconsRaw: String = Constants.defaultAchievementSuggestionExcludedMemoIconsRaw
    @AppStorage(Constants.AppStorageKey.achievementJourneyMaxFlagCount)
    private var journeyMaxFlagCount: Int = Constants.defaultAchievementJourneyMaxFlagCount
    @AppStorage(Constants.AppStorageKey.rewardWeeklyGoalPoints)
    private var rewardWeeklyGoalPoints: Int = Constants.defaultRewardWeeklyGoalPoints
    @AppStorage(Constants.AppStorageKey.achievementSuggestionProvider)
    private var suggestionProvider: String = Constants.defaultAchievementSuggestionProvider
    @AppStorage(Constants.AppStorageKey.achievementSuggestionMLXModel)
    private var suggestionMLXModel: String = Constants.defaultAchievementSuggestionMLXModel
    @AppStorage(Constants.AppStorageKey.achievementSuggestionOllamaModel)
    private var suggestionOllamaModel: String = Constants.defaultAchievementSuggestionOllamaModel
    @AppStorage(Constants.NewsStorageKey.ollamaEndpoint)
    private var ollamaEndpoint: String = Constants.defaultNewsOllamaEndpoint

    var body: some View {
        SettingsPageScroll {
            SettingsPageHeader(title: SettingsTab.achievement.label, subtitle: SettingsTab.achievement.subtitle)

            SettingsGroupCard("추천 모델") {
                SettingsRow(
                    "추천 엔진",
                    subtitle: "Apple 온디바이스는 빠르고 준비가 필요 없습니다. MLX는 더 많은 할일을 한 번에 보고 묶음을 더 잘 찾지만 느리고 메모리를 씁니다."
                ) {
                    Picker("", selection: $suggestionProvider) {
                        Text("Apple 온디바이스").tag(Constants.AchievementSuggestionProviderKind.appleFoundation.rawValue)
                        Text("MLX (앱 내장)").tag(Constants.AchievementSuggestionProviderKind.mlx.rawValue)
                        Text("Ollama").tag(Constants.AchievementSuggestionProviderKind.ollama.rawValue)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }

                // 모델 피커는 카드 목록이라 SettingsRow 의 오른쪽 슬롯에 넣으면 잘린다.
                // 행 밖에서 전체 폭을 쓰도록 둔다.
                if suggestionProvider == Constants.AchievementSuggestionProviderKind.mlx.rawValue {
                    pickerBlock(
                        title: "MLX 모델",
                        subtitle: "성취 탭에서는 추천 받을 때만 잠깐 모델을 메모리에 올리고 사용이 끝나면 해제합니다."
                    ) {
                        MLXModelPicker(
                            model: $suggestionMLXModel,
                            options: Constants.availableAchievementMLXModelOptions
                        )
                    }
                }

                if suggestionProvider == Constants.AchievementSuggestionProviderKind.ollama.rawValue {
                    pickerBlock(
                        title: "Ollama 모델",
                        subtitle: "가중치가 Ollama 프로세스에 올라가 앱 메모리를 쓰지 않습니다. 앱 안에서는 못 올리는 큰 모델도 쓸 수 있습니다."
                    ) {
                        OllamaModelPicker(
                            model: $suggestionOllamaModel,
                            endpoint: ollamaEndpoint,
                            dataBasePath: Constants.defaultNewsDataBasePath
                        )
                    }
                }
            }

            SettingsGroupCard("주간 목표 추천") {
                SettingsRow(
                    "추천 시작 기준",
                    subtitle: "할일이 이 개수 이상 있을 때부터 주간 목표 추천을 보여줍니다."
                ) {
                    suggestionStepper(value: $minTodosForWeeklySuggestions, range: Constants.achievementMinTodosForWeeklySuggestionsRange)
                }
                SettingsRow(
                    "한 번에 보여줄 최대 주간 목표 수",
                    subtitle: "할일을 묶어 한 번에 보여줄 주간 목표 초안의 최대 개수입니다."
                ) {
                    suggestionStepper(value: $weeklySuggestionLimit, range: Constants.achievementSuggestionCountRange)
                }

                SettingsRow(
                    "주간 목표 하나에 묶을 최대 할일 수",
                    subtitle: "값이 클수록 더 큰 주간 목표 초안이 만들어집니다."
                ) {
                    suggestionStepper(value: $maxTodosPerWeeklyGoal, range: Constants.achievementSuggestionMaxTodoCountRange)
                }
            }

            SettingsGroupCard("월간 목표 추천") {
                SettingsRow(
                    "추천 시작 기준",
                    subtitle: "주간 목표가 이 개수 이상 있을 때부터 월간 목표 추천을 함께 보여줍니다."
                ) {
                    suggestionStepper(value: $minWeeklyGoalsForMonthlySuggestions, range: Constants.achievementMonthlySuggestionMinWeeklyGoalCountRange)
                }

                SettingsRow(
                    "한 번에 보여줄 최대 월간 목표 수",
                    subtitle: "주간 목표들을 다시 묶어 제안할 월간 목표 초안의 최대 개수입니다."
                ) {
                    suggestionStepper(value: $monthlySuggestionLimit, range: Constants.achievementMonthlySuggestionCountRange)
                }

                SettingsRow(
                    "월간 목표 하나에 묶을 최대 주간 목표 수",
                    subtitle: "값이 클수록 더 큰 월간 목표 초안이 만들어집니다."
                ) {
                    suggestionStepper(value: $maxWeeklyGoalsPerMonthlyGoal, range: Constants.achievementMaxWeeklyGoalsPerMonthlyGoalRange)
                }
            }

            SettingsGroupCard("추천 제외 카테고리") {
                Text("할일보다 보관 성격이 강한 메모 카테고리는 목표 추천과 수동 연결 목록에서 제외합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)

                ForEach(MemoIcon.options, id: \.self) { icon in
                    SettingsRow(
                        "\(icon) \(MemoIcon.label(for: icon))",
                        subtitle: excludedMemoIcons.contains(icon) ? "목표 연결에서 제외됨" : "목표 연결에 포함됨"
                    ) {
                        Toggle("", isOn: Binding(
                            get: { excludedMemoIcons.contains(icon) },
                            set: { isExcluded in
                                var next = excludedMemoIcons
                                if isExcluded {
                                    next.insert(icon)
                                } else {
                                    next.remove(icon)
                                }
                                excludedMemoIconsRaw = encodeExcludedMemoIcons(next)
                            }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                }
            }

            SettingsGroupCard("여정") {
                SettingsRow(
                    "최대 깃발 개수",
                    subtitle: "여정 길 위에 직접 지정할 수 있는 월간 목표 깃발 수입니다."
                ) {
                    Text("\(clampedJourneyMaxFlagCount)개")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                    Stepper(
                        "\(clampedJourneyMaxFlagCount)개",
                        value: Binding(
                            get: { clampedJourneyMaxFlagCount },
                            set: { journeyMaxFlagCount = clamped($0, in: Constants.achievementJourneyMaxFlagCountRange) }
                        ),
                        in: Constants.achievementJourneyMaxFlagCountRange
                    )
                    .labelsHidden()
                }
            }

            SettingsGroupCard("보상") {
                SettingsRow(
                    "주간 목표 달성 포인트",
                    subtitle: "주간 목표를 달성하고 «보상 받기»를 누를 때 호롱불에 채워지는 포인트입니다."
                ) {
                    Text("\(clampedRewardWeeklyGoalPoints)P")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                    Stepper(
                        "\(clampedRewardWeeklyGoalPoints)P",
                        value: Binding(
                            get: { clampedRewardWeeklyGoalPoints },
                            set: { rewardWeeklyGoalPoints = clamped($0, in: Constants.rewardWeeklyGoalPointsRange) }
                        ),
                        in: Constants.rewardWeeklyGoalPointsRange
                    )
                    .labelsHidden()
                }
            }

            SettingsGroupCard("적용 방식") {
                Text("추천은 목표 초안만 만듭니다. 할일을 주간 목표로 묶고, 주간 목표가 충분히 쌓이면 월간 목표 초안도 함께 제안합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
        }
        .onAppear(perform: normalizeValues)
        .onChange(of: weeklySuggestionLimit) { _, _ in normalizeValues() }
        .onChange(of: maxTodosPerWeeklyGoal) { _, _ in normalizeValues() }
        .onChange(of: minWeeklyGoalsForMonthlySuggestions) { _, _ in normalizeValues() }
        .onChange(of: monthlySuggestionLimit) { _, _ in normalizeValues() }
        .onChange(of: minTodosForWeeklySuggestions) { _, _ in normalizeValues() }
        .onChange(of: maxWeeklyGoalsPerMonthlyGoal) { _, _ in normalizeValues() }
        .onChange(of: excludedMemoIconsRaw) { _, _ in normalizeValues() }
        .onChange(of: journeyMaxFlagCount) { _, _ in normalizeValues() }
        .onChange(of: rewardWeeklyGoalPoints) { _, _ in normalizeValues() }
        // 공급자를 떠나면 그쪽이 붙잡고 있던 가중치를 내린다. 안 내리면 Ollama 로 한 번 돌린 뒤
        // MLX 로 바꿔도 Ollama 쪽 모델이 그대로 남는다(실측 2026-08-19: 1.9GB, 만료 16시간 뒤).
        .onChange(of: suggestionProvider) { oldValue, newValue in
            guard oldValue != newValue else { return }
            unloadSuggestionModel(of: oldValue)
        }
        .onChange(of: suggestionOllamaModel) { oldValue, newValue in
            guard suggestionProvider == Constants.AchievementSuggestionProviderKind.ollama.rawValue,
                  oldValue != newValue else { return }
            unloadOllamaSuggestionModel(oldValue)
        }
        .onChange(of: suggestionMLXModel) { oldValue, newValue in
            guard suggestionProvider == Constants.AchievementSuggestionProviderKind.mlx.rawValue,
                  oldValue != newValue else { return }
            unloadMLXSuggestionModel()
        }
    }

    private var normalizedOllamaEndpoint: String {
        let trimmed = ollamaEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Constants.defaultNewsOllamaEndpoint : trimmed
    }

    /// 떠난 공급자가 붙잡고 있던 모델을 내린다.
    ///
    /// **새 공급자의 모델을 미리 올리지는 않는다.** 컴패니언(`CompanionPage`)은 대화가 즉답이라
    /// 미리 올려 두지만, 성취는 추천 버튼을 누를 때만 쓴다 — 설정 화면에서 골라 보기만 해도
    /// 수 GB 가 메모리에 올라오면 안 된다. 화면에 적어 둔 약속이 그것이다:
    /// «추천 받을 때만 잠깐 모델을 메모리에 올리고 사용이 끝나면 해제합니다».
    private func unloadSuggestionModel(of provider: String) {
        switch Constants.AchievementSuggestionProviderKind(rawValue: provider) {
        case .ollama:
            unloadOllamaSuggestionModel(suggestionOllamaModel)
        case .mlx:
            unloadMLXSuggestionModel()
        case .appleFoundation, .none:
            // AFM 은 시스템이 들고 있다. 앱이 내릴 수 있는 것이 없다.
            break
        }
    }

    /// Ollama 는 가중치가 남의 프로세스에 살아서 `keep_alive: 0` 한 줄로 내린다.
    ///
    /// 유휴 타임아웃에 기대지 않는 이유: 그 값은 **서버 설정**이라 앱이 모른다.
    /// 기본은 5분이지만 실측한 이 맥은 16시간을 잡고 있었다.
    private func unloadOllamaSuggestionModel(_ model: String) {
        guard !model.isEmpty else { return }
        let endpoint = normalizedOllamaEndpoint
        Task { await OllamaChatClient.unload(endpoint: endpoint, model: model) }
    }

    /// MLX 는 가중치가 **이 앱의 메모리**에 올라오므로, 놓아 주지 않으면 앱이 살아 있는 내내 남는다.
    private func unloadMLXSuggestionModel() {
        #if canImport(MLXLLM)
        Task { await MLXModelStore.shared.unload() }
        #endif
    }

    /// 전체 폭이 필요한 컨트롤용 블록. `SettingsRow` 는 컨트롤을 오른쪽 좁은 슬롯에 두므로
    /// 카드 목록 같은 넓은 컴포넌트는 여기에 담는다.
    @ViewBuilder
    private func pickerBlock<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func suggestionStepper(value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text("\(clamped(value.wrappedValue, in: range))개")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
            Stepper("", value: value, in: range).labelsHidden()
        }
    }


    private var clampedJourneyMaxFlagCount: Int {
        clamped(journeyMaxFlagCount, in: Constants.achievementJourneyMaxFlagCountRange)
    }

    private var clampedRewardWeeklyGoalPoints: Int {
        clamped(rewardWeeklyGoalPoints, in: Constants.rewardWeeklyGoalPointsRange)
    }

    private var excludedMemoIcons: Set<String> {
        let raw = excludedMemoIconsRaw == Constants.legacyAchievementSuggestionExcludedMemoIconsRaw
            ? Constants.defaultAchievementSuggestionExcludedMemoIconsRaw
            : excludedMemoIconsRaw
        let icons = raw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { MemoIcon.options.contains($0) }
        return Set(icons)
    }

    private func normalizeValues() {
        weeklySuggestionLimit = clamped(weeklySuggestionLimit, in: Constants.achievementSuggestionCountRange)
        maxTodosPerWeeklyGoal = clamped(maxTodosPerWeeklyGoal, in: Constants.achievementSuggestionMaxTodoCountRange)
        minWeeklyGoalsForMonthlySuggestions = clamped(minWeeklyGoalsForMonthlySuggestions, in: Constants.achievementMonthlySuggestionMinWeeklyGoalCountRange)
        monthlySuggestionLimit = clamped(monthlySuggestionLimit, in: Constants.achievementMonthlySuggestionCountRange)
        minTodosForWeeklySuggestions = clamped(minTodosForWeeklySuggestions, in: Constants.achievementMinTodosForWeeklySuggestionsRange)
        maxWeeklyGoalsPerMonthlyGoal = clamped(maxWeeklyGoalsPerMonthlyGoal, in: Constants.achievementMaxWeeklyGoalsPerMonthlyGoalRange)
        journeyMaxFlagCount = clampedJourneyMaxFlagCount
        rewardWeeklyGoalPoints = clampedRewardWeeklyGoalPoints
        excludedMemoIconsRaw = encodeExcludedMemoIcons(excludedMemoIcons)
    }

    private func clamped(_ value: Int, in range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func encodeExcludedMemoIcons(_ icons: Set<String>) -> String {
        MemoIcon.options
            .filter { icons.contains($0) }
            .joined(separator: ",")
    }
}
