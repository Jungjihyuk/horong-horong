import XCTest
import SwiftData
import UserNotifications
@testable import 호롱호롱

final class ConstantsDefaultsTests: XCTestCase {
    func testAllDistributionsShowTheDockIcon() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        for relativePath in ["HorongHorong/Info.plist", "HorongHorong/Info-AppStore.plist"] {
            let data = try Data(contentsOf: projectRoot.appendingPathComponent(relativePath))
            let plist = try XCTUnwrap(
                PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            )
            XCTAssertEqual(plist["LSUIElement"] as? Bool, false, relativePath)
        }
    }

    func testAppearanceDensityDefaultsToComfortable() {
        XCTAssertEqual(
            Constants.defaultAppearanceDensity,
            AppearanceDensity.comfortable.rawValue
        )
        XCTAssertEqual(
            AppearanceDensity.normalized(rawValue: "unsupported"),
            .comfortable
        )
    }

    func testGlobalHotkeyDefaultsMatchDisplayedShortcuts() {
        XCTAssertEqual(
            HotkeyCombo.defaultMenuBarPopover.displayParts,
            ["⌃", "⌥", "Space"]
        )
        XCTAssertEqual(
            HotkeyCombo.defaultTimerToggle.displayParts,
            ["⌃", "⌥", "P"]
        )
    }

    func testAppearanceDensityMetricsScaleInOrder() {
        let compact = AppearanceDensity.compact
        let comfortable = AppearanceDensity.comfortable
        let spacious = AppearanceDensity.spacious

        XCTAssertLessThan(compact.rowVerticalPadding, comfortable.rowVerticalPadding)
        XCTAssertLessThan(comfortable.rowVerticalPadding, spacious.rowVerticalPadding)
        XCTAssertLessThan(compact.rowTitleFontSize, comfortable.rowTitleFontSize)
        XCTAssertLessThan(comfortable.rowTitleFontSize, spacious.rowTitleFontSize)
        XCTAssertLessThan(compact.pageContentSpacing, comfortable.pageContentSpacing)
        XCTAssertLessThan(comfortable.pageContentSpacing, spacious.pageContentSpacing)
        XCTAssertLessThan(compact.popoverMetric(12), comfortable.popoverMetric(12))
        XCTAssertLessThan(comfortable.popoverMetric(12), spacious.popoverMetric(12))
        XCTAssertLessThan(compact.informationMetric(12), comfortable.informationMetric(12))
        XCTAssertLessThan(comfortable.informationMetric(12), spacious.informationMetric(12))

        XCTAssertEqual(comfortable.rowVerticalPadding, 10)
        XCTAssertEqual(comfortable.pageContentSpacing, 18)
        XCTAssertEqual(comfortable.pageVerticalPadding, 24)
        XCTAssertEqual(comfortable.pageTitleFontSize, 28)
        XCTAssertEqual(comfortable.popoverMetric(12), 12)
        XCTAssertEqual(comfortable.informationMetric(12), 12)
        XCTAssertGreaterThan(compact.popoverMetric(12), compact.informationMetric(12))
        XCTAssertLessThan(spacious.popoverMetric(12), spacious.informationMetric(12))
    }

    func testAppearanceAccentPalettesHaveFourUniqueOptionsPerTheme() {
        for theme in Constants.PopoverTheme.allCases {
            let options = AppearanceAccentPalette.options(for: theme)
            XCTAssertEqual(options.count, 4, "\(theme.rawValue) 팔레트 개수")
            XCTAssertEqual(Set(options.map(\.id)).count, options.count)
            XCTAssertTrue(options.contains { $0.id == AppearanceAccentPalette.defaultID(for: theme) })
        }
    }

    func testAppearanceAccentDefaultsPreserveCurrentThemeColors() {
        XCTAssertEqual(
            AppearanceAccentPalette.option(for: .warmLantern, id: "invalid").popoverRGB,
            0xF0782E
        )
        XCTAssertEqual(
            AppearanceAccentPalette.option(for: .wineLantern, id: "invalid").popoverRGB,
            0xA23A52
        )
        XCTAssertEqual(
            AppearanceAccentPalette.option(for: .gamePixel, id: "invalid").popoverRGB,
            0x7A52D6
        )
    }

    func testAppearanceAccentSelectionsAreStoredPerTheme() throws {
        let suiteName = "AppearanceAccentPaletteTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("bamboo", forKey: AppearanceAccentPalette.storageKey(for: .warmLantern))
        defaults.set("brass", forKey: AppearanceAccentPalette.storageKey(for: .wineLantern))
        defaults.set("heart", forKey: AppearanceAccentPalette.storageKey(for: .gamePixel))

        XCTAssertEqual(AppearanceAccentPalette.selectedOption(for: .warmLantern, defaults: defaults).id, "bamboo")
        XCTAssertEqual(AppearanceAccentPalette.selectedOption(for: .wineLantern, defaults: defaults).id, "brass")
        XCTAssertEqual(AppearanceAccentPalette.selectedOption(for: .gamePixel, defaults: defaults).id, "heart")
    }

    @MainActor
    func testAppearanceAccentStoreObservesThemeAndAccentChanges() throws {
        let suiteName = "AppearanceAccentStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let notificationCenter = NotificationCenter()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(Constants.PopoverTheme.warmLantern.rawValue, forKey: Constants.AppStorageKey.popoverTheme)
        defaults.set("bamboo", forKey: Constants.AppStorageKey.warmLanternAccent)
        let store = AppearanceAccentStore(defaults: defaults, notificationCenter: notificationCenter)
        XCTAssertEqual(store.theme, .warmLantern)
        XCTAssertEqual(store.option.id, "bamboo")

        defaults.set(Constants.PopoverTheme.wineLantern.rawValue, forKey: Constants.AppStorageKey.popoverTheme)
        defaults.set("sage", forKey: Constants.AppStorageKey.wineLanternAccent)
        notificationCenter.post(name: UserDefaults.didChangeNotification, object: defaults)

        XCTAssertEqual(store.theme, .wineLantern)
        XCTAssertEqual(store.option.id, "sage")
    }

    func testAppearanceAccentColorsMeetControlContrastTargets() {
        let lightBackground: UInt32 = 0xFFFFFF
        let darkBackground: UInt32 = 0x1E1E1E

        for theme in Constants.PopoverTheme.allCases {
            for option in AppearanceAccentPalette.options(for: theme) {
                XCTAssertGreaterThanOrEqual(
                    AppearanceAccentPalette.contrastRatio(option.settingsLightRGB, lightBackground),
                    4.5,
                    "\(theme.rawValue).\(option.id) 라이트 강조 색 대비"
                )
                XCTAssertGreaterThanOrEqual(
                    AppearanceAccentPalette.contrastRatio(option.settingsDarkRGB, darkBackground),
                    4.5,
                    "\(theme.rawValue).\(option.id) 다크 강조 색 대비"
                )
                XCTAssertGreaterThanOrEqual(
                    AppearanceAccentPalette.contrastRatio(option.popoverRGB, option.accentInkRGB),
                    4.5,
                    "\(theme.rawValue).\(option.id) 버튼 글자 대비"
                )
                for gradientRGB in [option.buttonTopRGB, option.buttonBottomRGB].compactMap({ $0 }) {
                    XCTAssertGreaterThanOrEqual(
                        AppearanceAccentPalette.contrastRatio(gradientRGB, option.accentInkRGB),
                        4.5,
                        "\(theme.rawValue).\(option.id) 그라데이션 버튼 글자 대비"
                    )
                }
            }
        }
    }

    func testMondayWeekStartUsesMondayThroughSunday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 5, day: 31, hour: 12))!
        let expectedMonday = calendar.date(from: DateComponents(year: 2026, month: 5, day: 25))!

        XCTAssertEqual(Constants.mondayWeekStart(for: sunday, calendar: calendar), expectedMonday)
    }

    func testTimerPresetDefaultsMatchDocumentedValues() {
        XCTAssertEqual(Constants.PomodoroPreset.pomodoro.focusMinutes, 50)
        XCTAssertEqual(Constants.PomodoroPreset.pomodoro.breakMinutes, 5)
        XCTAssertEqual(Constants.PomodoroPreset.longFocus.focusMinutes, 100)
        XCTAssertEqual(Constants.PomodoroPreset.longFocus.breakMinutes, 10)
        XCTAssertEqual(Constants.PomodoroPreset.custom.focusMinutes, 60)
        XCTAssertEqual(Constants.PomodoroPreset.custom.breakMinutes, 10)
    }

    func testPomodoroReflectionDefaultsToDisabled() {
        XCTAssertFalse(Constants.defaultPomodoroReflectionEnabled)
    }

    func testUnmappedAppsDefaultToPendingClassification() {
        XCTAssertEqual(
            Constants.defaultUnmappedAppHandling,
            .pendingClassification
        )
    }

    func testTimerCompletionNotificationDefaultsToSystemOnly() {
        XCTAssertEqual(Constants.defaultTimerCompletionNotificationStyle, .system)
        XCTAssertEqual(
            Set(Constants.TimerCompletionNotificationStyle.allCases),
            Set([.system, .horong])
        )
    }

    func testTimerCompletionNotificationUsesTitleSubtitleAndBody() {
        let focus = Constants.focusCompletionNotificationContent(focusMinutes: 50)
        XCTAssertEqual(focus.title, "포모도로 완료")
        XCTAssertEqual(focus.subtitle, "50분 집중 완료")
        XCTAssertEqual(focus.body, "집중 기록을 저장했어요. 잠시 쉬어가세요.")

        let rest = Constants.breakCompletionNotificationContent
        XCTAssertEqual(rest.title, "휴식 끝!")
        XCTAssertEqual(rest.subtitle, "다시 집중할 준비가 되셨나요?")
        XCTAssertFalse(rest.body.isEmpty)
    }

    func testTodayPlanningReminderDefaultsToDisabled() {
        XCTAssertFalse(Constants.defaultTodayPlanningReminderEnabled)
        XCTAssertEqual(Constants.defaultTodayPlanningReminderDelayMinutes, 5)
        XCTAssertEqual(Constants.todayPlanningReminderDelaySeconds(for: 5), 5 * 60)
        XCTAssertEqual(Constants.todayPlanningReminderDelaySeconds(for: 0), 60)
        XCTAssertEqual(Constants.todayPlanningReminderDelaySeconds(for: 61), 60 * 60)
    }

    func testNotificationAlertAvailabilityRequiresPermissionAndEnabledAlerts() {
        XCTAssertEqual(
            NotificationManager.alertAuthorizationState(
                authorizationStatus: .authorized,
                alertSetting: .enabled,
                alertStyle: .banner
            ),
            .available
        )
        XCTAssertEqual(
            NotificationManager.alertAuthorizationState(
                authorizationStatus: .notDetermined,
                alertSetting: .disabled,
                alertStyle: .none
            ),
            .notDetermined
        )
        XCTAssertEqual(
            NotificationManager.alertAuthorizationState(
                authorizationStatus: .denied,
                alertSetting: .enabled,
                alertStyle: .banner
            ),
            .unavailable
        )
        XCTAssertEqual(
            NotificationManager.alertAuthorizationState(
                authorizationStatus: .authorized,
                alertSetting: .disabled,
                alertStyle: .banner
            ),
            .unavailable
        )
        XCTAssertEqual(
            NotificationManager.alertAuthorizationState(
                authorizationStatus: .authorized,
                alertSetting: .enabled,
                alertStyle: .none
            ),
            .unavailable
        )
    }

    @MainActor
    func testTodayPlanningReminderRequiresAnActiveMemoStartingToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 17, hour: 12)
        )!
        let todayTask = Memo(content: "오늘 할 일")
        todayTask.startDate = calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 17, hour: 18)
        )

        XCTAssertTrue(
            TodayPlanningReminderPolicy.hasTodayTask(
                in: [todayTask],
                now: now,
                calendar: calendar
            )
        )

        todayTask.startDate = nil
        todayTask.deadline = now
        XCTAssertFalse(
            TodayPlanningReminderPolicy.hasTodayTask(
                in: [todayTask],
                now: now,
                calendar: calendar
            ),
            "마감만 오늘인 할 일과 기한 없는 할 일은 오늘 계획으로 세지 않는다"
        )

        todayTask.startDate = calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 16, hour: 18)
        )
        XCTAssertFalse(
            TodayPlanningReminderPolicy.hasTodayTask(
                in: [todayTask],
                now: now,
                calendar: calendar
            ),
            "이전 날짜에 시작한 미완료 할 일은 오늘 계획으로 세지 않는다"
        )
    }

    @MainActor
    func testTodayTaskPredicateUsesTheSameEligibilityAsPlanningReminder() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 19, hour: 12)
        )!
        let memo = Memo(content: "오늘 할 일")
        memo.startDate = now

        XCTAssertTrue(
            TodayPlanningReminderPolicy.isTodayTask(
                memo,
                now: now,
                calendar: calendar
            )
        )

        memo.isCompletedValue = true
        XCTAssertFalse(
            TodayPlanningReminderPolicy.isTodayTask(
                memo,
                now: now,
                calendar: calendar
            )
        )

        memo.isCompletedValue = false
        memo.startDate = nil
        XCTAssertFalse(
            TodayPlanningReminderPolicy.isTodayTask(
                memo,
                now: now,
                calendar: calendar
            )
        )
    }

    @MainActor
    func testTodayPlanningReminderIgnoresCompletedAndArchivedTodayTasks() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 17, hour: 12)
        )!
        let completed = Memo(content: "완료한 일")
        completed.startDate = now
        completed.isCompletedValue = true
        let deleted = Memo(content: "지운 오늘 할 일")
        deleted.startDate = now
        deleted.deletedAt = now

        XCTAssertFalse(
            TodayPlanningReminderPolicy.hasTodayTask(
                in: [completed, deleted],
                now: now,
                calendar: calendar
            )
        )
    }

    @MainActor
    func testTodayPlanningReminderDoesNotPromptWhenActiveTodayTaskExists() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 17, hour: 12)
        )!
        let task = Memo(content: "오늘 할 일")
        task.startDate = now

        XCTAssertFalse(
            TodayPlanningReminderPolicy.shouldPrompt(
                isEnabled: true,
                memos: [task],
                lastPromptedAt: nil,
                now: now,
                calendar: calendar
            )
        )

        task.isCompletedValue = true
        XCTAssertTrue(
            TodayPlanningReminderPolicy.shouldPrompt(
                isEnabled: true,
                memos: [task],
                lastPromptedAt: nil,
                now: now,
                calendar: calendar
            )
        )
    }

    @MainActor
    func testTodayPlanningReminderUsesStartDateInsteadOfDeadline() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 17, hour: 12)
        )!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        let startsToday = Memo(content: "시작일 우선")
        startsToday.startDate = now
        startsToday.deadline = yesterday
        let dueToday = Memo(content: "마감일만 오늘")
        dueToday.startDate = tomorrow
        dueToday.deadline = now

        XCTAssertTrue(
            TodayPlanningReminderPolicy.hasTodayTask(
                in: [startsToday],
                now: now,
                calendar: calendar
            )
        )
        XCTAssertFalse(
            TodayPlanningReminderPolicy.hasTodayTask(
                in: [dueToday],
                now: now,
                calendar: calendar
            )
        )
    }

    @MainActor
    func testTodayPlanningReminderPromptsAtMostOncePerCalendarDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 17, hour: 12)
        )!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!

        XCTAssertTrue(
            TodayPlanningReminderPolicy.shouldPrompt(
                isEnabled: true,
                memos: [],
                lastPromptedAt: nil,
                now: now,
                calendar: calendar
            )
        )
        XCTAssertTrue(
            TodayPlanningReminderPolicy.shouldPrompt(
                isEnabled: true,
                memos: [],
                lastPromptedAt: yesterday,
                now: now,
                calendar: calendar
            )
        )
        XCTAssertFalse(
            TodayPlanningReminderPolicy.shouldPrompt(
                isEnabled: true,
                memos: [],
                lastPromptedAt: now,
                now: now,
                calendar: calendar
            )
        )
        XCTAssertFalse(
            TodayPlanningReminderPolicy.shouldPrompt(
                isEnabled: false,
                memos: [],
                lastPromptedAt: nil,
                now: now,
                calendar: calendar
            )
        )
    }

    @MainActor
    func testTodayPlanningReminderDailyQuotaResetsAtLocalMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let justBeforeMidnight = calendar.date(
            from: DateComponents(
                year: 2026,
                month: 7,
                day: 17,
                hour: 23,
                minute: 59,
                second: 59
            )
        )!
        let midnight = calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 18, hour: 0)
        )!
        let endOfDay = calendar.date(
            from: DateComponents(
                year: 2026,
                month: 7,
                day: 18,
                hour: 23,
                minute: 59,
                second: 59
            )
        )!

        XCTAssertTrue(
            TodayPlanningReminderPolicy.shouldPrompt(
                isEnabled: true,
                memos: [],
                lastPromptedAt: justBeforeMidnight,
                now: midnight,
                calendar: calendar
            )
        )
        XCTAssertFalse(
            TodayPlanningReminderPolicy.shouldPrompt(
                isEnabled: true,
                memos: [],
                lastPromptedAt: midnight,
                now: endOfDay,
                calendar: calendar
            )
        )
    }

    func testTodayPlanningReminderReevaluatesAcrossDSTTransitions() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let springChangeDay = calendar.date(
            from: DateComponents(year: 2026, month: 3, day: 8, hour: 12)
        )!
        let expectedAfterSpringChange = calendar.date(
            from: DateComponents(year: 2026, month: 3, day: 9, hour: 0, minute: 5)
        )!
        let fallChangeDay = calendar.date(
            from: DateComponents(year: 2026, month: 11, day: 1, hour: 12)
        )!
        let expectedAfterFallChange = calendar.date(
            from: DateComponents(year: 2026, month: 11, day: 2, hour: 0, minute: 5)
        )!
        let defaultDelaySeconds = Constants.todayPlanningReminderDelaySeconds(
            for: Constants.defaultTodayPlanningReminderDelayMinutes
        )

        let afterSpringChange = TodayPlanningReminderPolicy.nextDayEvaluationDate(
            after: springChangeDay,
            delaySeconds: defaultDelaySeconds,
            calendar: calendar
        )
        let afterFallChange = TodayPlanningReminderPolicy.nextDayEvaluationDate(
            after: fallChangeDay,
            delaySeconds: defaultDelaySeconds,
            calendar: calendar
        )

        XCTAssertEqual(afterSpringChange, expectedAfterSpringChange)
        XCTAssertEqual(
            afterSpringChange.timeIntervalSince(calendar.startOfDay(for: springChangeDay)),
            23 * 60 * 60 + 5 * 60,
            accuracy: 0.001
        )
        XCTAssertEqual(afterFallChange, expectedAfterFallChange)
        XCTAssertEqual(
            afterFallChange.timeIntervalSince(calendar.startOfDay(for: fallChangeDay)),
            25 * 60 * 60 + 5 * 60,
            accuracy: 0.001
        )
    }

    func testPomodoroReflectionAnswerLabelsStayStable() {
        XCTAssertEqual(
            PomodoroFocusExperience.allCases.map(\.label),
            [
                "깊게 몰입했어요",
                "대체로 집중했어요",
                "자주 흐트러졌어요",
                "집중하기 어려웠어요",
                "잘 모르겠어요",
            ]
        )
        XCTAssertEqual(
            PomodoroProgressResult.allCases.map(\.label),
            [
                "계획한 만큼 끝냈어요",
                "의미 있게 진행했지만 남았어요",
                "거의 진행하지 못했어요",
                "진행 중 목표가 바뀌었어요",
            ]
        )
        XCTAssertEqual(
            PomodoroProgressResult.completedAsPlanned.label(recordsLinkedTaskCompletion: true),
            "이 할 일을 모두 끝냈어요"
        )
        XCTAssertEqual(
            PomodoroProgressResult.meaningfulProgress.label(recordsLinkedTaskCompletion: true),
            PomodoroProgressResult.meaningfulProgress.label
        )
        XCTAssertEqual(
            PomodoroIncompleteReason.allCases.map(\.label),
            [
                "설정한 시간이 짧았어요",
                "예상보다 작업이 컸어요",
                "원하는 수준까지 더 다듬고 싶었어요",
                "막힌 부분이 있었어요",
                "다른 작업으로 옮겼어요",
                "방해 요소에 집중이 흐트러졌어요",
                "외부 요청이나 일정이 생겼어요",
            ]
        )
    }

    func testOnlyCompletedAsPlannedSkipsIncompleteReason() {
        XCTAssertFalse(PomodoroProgressResult.completedAsPlanned.requiresReason)
        XCTAssertTrue(PomodoroProgressResult.meaningfulProgress.requiresReason)
        XCTAssertTrue(PomodoroProgressResult.littleProgress.requiresReason)
        XCTAssertTrue(PomodoroProgressResult.goalChanged.requiresReason)
    }

    @MainActor
    func testPomodoroReflectionPersistsInSwiftData() throws {
        let schema = Schema([
            FocusSession.self,
            PomodoroReflection.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let sessionID = UUID()
        let answeredAt = Date(timeIntervalSince1970: 1_800_000_000)
        let reflection = PomodoroReflection(
            focusSessionID: sessionID,
            focusExperience: .mostlyFocused,
            progressResult: .meaningfulProgress,
            incompleteReason: .underestimatedScope,
            answeredAt: answeredAt
        )

        context.insert(reflection)
        try context.save()

        let saved = try XCTUnwrap(context.fetch(FetchDescriptor<PomodoroReflection>()).first)
        XCTAssertEqual(saved.focusSessionID, sessionID)
        XCTAssertEqual(saved.focusExperienceRawValue, PomodoroFocusExperience.mostlyFocused.rawValue)
        XCTAssertEqual(saved.progressResultRawValue, PomodoroProgressResult.meaningfulProgress.rawValue)
        XCTAssertEqual(saved.incompleteReasonRawValue, PomodoroIncompleteReason.underestimatedScope.rawValue)
        XCTAssertEqual(saved.focusExperience, .mostlyFocused)
        XCTAssertEqual(saved.progressResult, .meaningfulProgress)
        XCTAssertEqual(saved.incompleteReason, .underestimatedScope)
        XCTAssertEqual(saved.answeredAt, answeredAt)
        XCTAssertEqual(saved.schemaVersion, 1)
    }

    @MainActor
    func testPomodoroReflectionBatchFetchesOnlyRequestedSessions() throws {
        let schema = Schema([
            FocusSession.self,
            PomodoroReflection.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let requestedSessionIDs = [UUID(), UUID()]
        let unrelatedSessionID = UUID()

        for sessionID in requestedSessionIDs + [unrelatedSessionID] {
            context.insert(
                PomodoroReflection(
                    focusSessionID: sessionID,
                    focusExperience: .mostlyFocused,
                    progressResult: .meaningfulProgress
                )
            )
        }
        try context.save()

        let descriptor = FetchDescriptor<PomodoroReflection>(
            predicate: #Predicate {
                requestedSessionIDs.contains($0.focusSessionID)
            }
        )
        let fetched = try context.fetch(descriptor)

        XCTAssertEqual(Set(fetched.map(\.focusSessionID)), Set(requestedSessionIDs))
    }

    func testUpdatingPomodoroReflectionClearsReasonWhenWorkIsCompleted() {
        let reflection = PomodoroReflection(
            focusSessionID: UUID(),
            focusExperience: .frequentlyDistracted,
            progressResult: .littleProgress,
            incompleteReason: .distracted
        )

        reflection.updateAnswers(
            focusExperience: .deeplyFocused,
            progressResult: .completedAsPlanned,
            incompleteReason: .underestimatedScope
        )

        XCTAssertEqual(reflection.focusExperience, .deeplyFocused)
        XCTAssertEqual(reflection.progressResult, .completedAsPlanned)
        XCTAssertNil(reflection.incompleteReason)
        XCTAssertNil(reflection.incompleteReasonRawValue)
    }

    func testUpdatingIncompletePomodoroReflectionKeepsSelectedReason() {
        let reflection = PomodoroReflection(
            focusSessionID: UUID(),
            focusExperience: .unsure,
            progressResult: .completedAsPlanned
        )

        reflection.updateAnswers(
            focusExperience: .mostlyFocused,
            progressResult: .meaningfulProgress,
            incompleteReason: .insufficientTime
        )

        XCTAssertEqual(reflection.focusExperience, .mostlyFocused)
        XCTAssertEqual(reflection.progressResult, .meaningfulProgress)
        XCTAssertEqual(reflection.incompleteReason, .insufficientTime)
    }

    @MainActor
    func testPomodoroTaskCompletionMarksLinkedMemoAndStoresEvidence() throws {
        let schema = Schema([
            Todo.self,
            FocusSession.self,
            PomodoroTaskCompletion.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let memo = Todo(content: "  완료 근거 저장  ")
        memo.isPinned = true
        let session = FocusSession(
            focusMinutes: 25,
            breakMinutes: 5,
            linkedMemoID: memo.id,
            taskTitleSnapshot: "  완료 근거 저장  "
        )
        context.insert(memo)
        context.insert(session)
        try context.save()
        let completedAt = Date(timeIntervalSince1970: 1_800_001_000)

        let affectedMemo = try PomodoroTaskCompletionRecorder.recordCompletion(
            for: session,
            completedAt: completedAt,
            modelContext: context
        )
        try context.save()

        XCTAssertEqual(affectedMemo?.id, memo.id)
        XCTAssertTrue(memo.isCompletedValue)
        XCTAssertFalse(memo.isPinned)
        XCTAssertEqual(memo.updatedAt, completedAt)

        let completion = try XCTUnwrap(
            context.fetch(FetchDescriptor<PomodoroTaskCompletion>()).first
        )
        XCTAssertEqual(completion.focusSessionID, session.id)
        XCTAssertEqual(completion.linkedMemoID, memo.id)
        XCTAssertEqual(completion.taskTitleSnapshot, "완료 근거 저장")
        XCTAssertEqual(completion.completedAt, completedAt)
        XCTAssertTrue(completion.didMarkMemoCompleted)
        XCTAssertTrue(completion.memoWasPinnedBeforeCompletion)
        XCTAssertEqual(completion.memoStateChangedAt, completedAt)
        XCTAssertEqual(completion.schemaVersion, 1)
    }

    @MainActor
    func testCompletionForAlreadyCompletedMemoNeverTakesRestorationOwnership() throws {
        let schema = Schema([
            Todo.self,
            FocusSession.self,
            PomodoroTaskCompletion.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let originalUpdatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let memo = Todo(content: "직접 완료한 할 일")
        memo.isCompletedValue = true
        memo.isPinned = true
        memo.updatedAt = originalUpdatedAt
        let session = FocusSession(
            focusMinutes: 25,
            breakMinutes: 5,
            linkedMemoID: memo.id,
            taskTitleSnapshot: "직접 완료한 할 일"
        )
        context.insert(memo)
        context.insert(session)
        try context.save()

        let affectedMemo = try PomodoroTaskCompletionRecorder.recordCompletion(
            for: session,
            completedAt: originalUpdatedAt.addingTimeInterval(60),
            modelContext: context
        )
        try context.save()

        XCTAssertNil(affectedMemo)
        XCTAssertTrue(memo.isCompletedValue)
        XCTAssertTrue(memo.isPinned)
        XCTAssertEqual(memo.updatedAt, originalUpdatedAt)
        let completion = try XCTUnwrap(
            context.fetch(FetchDescriptor<PomodoroTaskCompletion>()).first
        )
        XCTAssertFalse(completion.didMarkMemoCompleted)
        XCTAssertTrue(completion.memoWasPinnedBeforeCompletion)
        XCTAssertNil(completion.memoStateChangedAt)

        let removedMemo = try PomodoroTaskCompletionRecorder.removeCompletion(
            focusSessionID: session.id,
            modelContext: context
        )
        try context.save()

        XCTAssertNil(removedMemo)
        XCTAssertTrue(memo.isCompletedValue)
        XCTAssertTrue(memo.isPinned)
        XCTAssertEqual(memo.updatedAt, originalUpdatedAt)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PomodoroTaskCompletion>()).isEmpty)
    }

    @MainActor
    func testCompletionForMissingLinkedMemoDoesNotStoreEvidence() throws {
        let schema = Schema([
            Todo.self,
            FocusSession.self,
            PomodoroTaskCompletion.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let missingMemoID = UUID()
        let session = FocusSession(
            focusMinutes: 25,
            breakMinutes: 5,
            linkedMemoID: missingMemoID,
            taskTitleSnapshot: "삭제된 할 일"
        )
        context.insert(session)
        try context.save()

        let affectedMemo = try PomodoroTaskCompletionRecorder.recordCompletion(
            for: session,
            completedAt: Date(timeIntervalSince1970: 1_800_001_000),
            modelContext: context
        )
        try context.save()

        XCTAssertNil(affectedMemo)
        XCTAssertFalse(
            PomodoroTaskCompletionRecorder.hasLinkedMemo(
                id: missingMemoID,
                modelContext: context
            )
        )
        XCTAssertTrue(try context.fetch(FetchDescriptor<PomodoroTaskCompletion>()).isEmpty)
    }

    @MainActor
    func testRemovingPomodoroTaskCompletionSafelyRestoresMemoState() throws {
        let schema = Schema([
            Todo.self,
            FocusSession.self,
            PomodoroTaskCompletion.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let memo = Todo(content: "완료 취소")
        memo.isPinned = true
        let session = FocusSession(
            focusMinutes: 25,
            breakMinutes: 5,
            linkedMemoID: memo.id,
            taskTitleSnapshot: "완료 취소"
        )
        context.insert(memo)
        context.insert(session)
        try context.save()
        let completedAt = Date(timeIntervalSince1970: 1_800_001_000)
        let removedAt = completedAt.addingTimeInterval(60)
        try PomodoroTaskCompletionRecorder.recordCompletion(
            for: session,
            completedAt: completedAt,
            modelContext: context
        )
        try context.save()

        let affectedMemo = try PomodoroTaskCompletionRecorder.removeCompletion(
            focusSessionID: session.id,
            removedAt: removedAt,
            modelContext: context
        )
        try context.save()

        XCTAssertEqual(affectedMemo?.id, memo.id)
        XCTAssertFalse(memo.isCompletedValue)
        XCTAssertTrue(memo.isPinned)
        XCTAssertEqual(memo.updatedAt, removedAt)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PomodoroTaskCompletion>()).isEmpty)
    }

    @MainActor
    func testDeletingPomodoroSessionRemovesReflectionAndRestoresLinkedMemo() throws {
        let schema = Schema([
            Todo.self,
            FocusSession.self,
            PomodoroReflection.self,
            PomodoroTaskCompletion.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let memo = Todo(content: "세션 삭제 시 되돌릴 할 일")
        memo.isPinned = true
        let session = FocusSession(
            focusMinutes: 25,
            breakMinutes: 5,
            linkedMemoID: memo.id,
            taskTitleSnapshot: "세션 삭제 시 되돌릴 할 일"
        )
        let reflection = PomodoroReflection(
            focusSessionID: session.id,
            focusExperience: .deeplyFocused,
            progressResult: .completedAsPlanned
        )
        context.insert(memo)
        context.insert(session)
        context.insert(reflection)
        try context.save()
        try PomodoroTaskCompletionRecorder.recordCompletion(
            for: session,
            completedAt: Date(timeIntervalSince1970: 1_800_001_000),
            modelContext: context
        )
        try context.save()

        let affectedMemo = try PomodoroSessionDeletion.delete(
            session,
            modelContext: context
        )
        try context.save()

        XCTAssertEqual(affectedMemo?.id, memo.id)
        XCTAssertFalse(memo.isCompletedValue)
        XCTAssertTrue(memo.isPinned)
        XCTAssertTrue(try context.fetch(FetchDescriptor<FocusSession>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PomodoroReflection>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PomodoroTaskCompletion>()).isEmpty)
    }

    @MainActor
    func testRepairingOrphanedPomodoroRecordsRestoresPreviouslyDeletedSessionMemo() throws {
        let schema = Schema([
            Todo.self,
            FocusSession.self,
            PomodoroReflection.self,
            PomodoroTaskCompletion.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let memo = Todo(content: "기존 삭제 오류 복구")
        let session = FocusSession(
            focusMinutes: 25,
            breakMinutes: 5,
            linkedMemoID: memo.id,
            taskTitleSnapshot: "기존 삭제 오류 복구"
        )
        let reflection = PomodoroReflection(
            focusSessionID: session.id,
            focusExperience: .mostlyFocused,
            progressResult: .completedAsPlanned
        )
        context.insert(memo)
        context.insert(session)
        context.insert(reflection)
        try context.save()
        try PomodoroTaskCompletionRecorder.recordCompletion(
            for: session,
            completedAt: Date(timeIntervalSince1970: 1_800_001_000),
            modelContext: context
        )
        memo.completionStateChangedAt = nil
        try context.save()

        context.delete(session)
        try context.save()
        XCTAssertTrue(memo.isCompletedValue)
        XCTAssertFalse(try context.fetch(FetchDescriptor<PomodoroReflection>()).isEmpty)
        XCTAssertFalse(try context.fetch(FetchDescriptor<PomodoroTaskCompletion>()).isEmpty)

        let affectedMemos = try PomodoroSessionDeletion.repairOrphanedRecords(
            modelContext: context
        )
        try context.save()

        XCTAssertEqual(affectedMemos.map(\.id), [memo.id])
        XCTAssertFalse(memo.isCompletedValue)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PomodoroReflection>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PomodoroTaskCompletion>()).isEmpty)
    }

    @MainActor
    func testDeletingFirstOfMultipleCompletionsTransfersSafeMemoRestoration() throws {
        let schema = Schema([
            Todo.self,
            FocusSession.self,
            PomodoroTaskCompletion.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let memo = Todo(content: "여러 완료 근거")
        memo.isPinned = true
        let firstSession = FocusSession(
            focusMinutes: 25,
            breakMinutes: 5,
            linkedMemoID: memo.id,
            taskTitleSnapshot: "여러 완료 근거"
        )
        let secondSession = FocusSession(
            focusMinutes: 25,
            breakMinutes: 5,
            linkedMemoID: memo.id,
            taskTitleSnapshot: "여러 완료 근거"
        )
        context.insert(memo)
        context.insert(firstSession)
        context.insert(secondSession)
        try context.save()
        let firstCompletedAt = Date(timeIntervalSince1970: 1_800_001_000)
        let secondCompletedAt = firstCompletedAt.addingTimeInterval(1_800)
        try PomodoroTaskCompletionRecorder.recordCompletion(
            for: firstSession,
            completedAt: firstCompletedAt,
            modelContext: context
        )
        try PomodoroTaskCompletionRecorder.recordCompletion(
            for: secondSession,
            completedAt: secondCompletedAt,
            modelContext: context
        )
        try context.save()

        let firstRemoval = try PomodoroTaskCompletionRecorder.removeCompletion(
            focusSessionID: firstSession.id,
            modelContext: context
        )
        try context.save()

        XCTAssertNil(firstRemoval)
        XCTAssertTrue(memo.isCompletedValue)
        let successor = try XCTUnwrap(
            context.fetch(FetchDescriptor<PomodoroTaskCompletion>()).first
        )
        XCTAssertEqual(successor.focusSessionID, secondSession.id)
        XCTAssertTrue(successor.didMarkMemoCompleted)
        XCTAssertTrue(successor.memoWasPinnedBeforeCompletion)
        XCTAssertEqual(successor.memoStateChangedAt, firstCompletedAt)

        let finalRemoval = try PomodoroTaskCompletionRecorder.removeCompletion(
            focusSessionID: secondSession.id,
            removedAt: secondCompletedAt.addingTimeInterval(60),
            modelContext: context
        )
        try context.save()

        XCTAssertEqual(finalRemoval?.id, memo.id)
        XCTAssertFalse(memo.isCompletedValue)
        XCTAssertTrue(memo.isPinned)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PomodoroTaskCompletion>()).isEmpty)
    }

    @MainActor
    func testDeletingNonOwningCompletionFirstStillRestoresMemo() throws {
        let schema = Schema([
            Todo.self,
            FocusSession.self,
            PomodoroTaskCompletion.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let memo = Todo(content: "완료 근거 삭제 순서")
        memo.isPinned = true
        let firstSession = FocusSession(
            focusMinutes: 25,
            breakMinutes: 5,
            linkedMemoID: memo.id,
            taskTitleSnapshot: "완료 근거 삭제 순서"
        )
        let secondSession = FocusSession(
            focusMinutes: 25,
            breakMinutes: 5,
            linkedMemoID: memo.id,
            taskTitleSnapshot: "완료 근거 삭제 순서"
        )
        context.insert(memo)
        context.insert(firstSession)
        context.insert(secondSession)
        try context.save()
        let firstCompletedAt = Date(timeIntervalSince1970: 1_800_001_000)
        let secondCompletedAt = firstCompletedAt.addingTimeInterval(1_800)
        try PomodoroTaskCompletionRecorder.recordCompletion(
            for: firstSession,
            completedAt: firstCompletedAt,
            modelContext: context
        )
        try PomodoroTaskCompletionRecorder.recordCompletion(
            for: secondSession,
            completedAt: secondCompletedAt,
            modelContext: context
        )
        try context.save()

        let secondRemoval = try PomodoroTaskCompletionRecorder.removeCompletion(
            focusSessionID: secondSession.id,
            modelContext: context
        )
        try context.save()

        XCTAssertNil(secondRemoval)
        XCTAssertTrue(memo.isCompletedValue)
        let owner = try XCTUnwrap(
            context.fetch(FetchDescriptor<PomodoroTaskCompletion>()).first
        )
        XCTAssertEqual(owner.focusSessionID, firstSession.id)
        XCTAssertTrue(owner.didMarkMemoCompleted)

        let finalRemoval = try PomodoroTaskCompletionRecorder.removeCompletion(
            focusSessionID: firstSession.id,
            removedAt: secondCompletedAt.addingTimeInterval(60),
            modelContext: context
        )
        try context.save()

        XCTAssertEqual(finalRemoval?.id, memo.id)
        XCTAssertFalse(memo.isCompletedValue)
        XCTAssertTrue(memo.isPinned)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PomodoroTaskCompletion>()).isEmpty)
    }

    @MainActor
    func testRemovingCurrentCompletionDoesNotTransferToHistoricalOwner() throws {
        let schema = Schema([
            Todo.self,
            FocusSession.self,
            PomodoroTaskCompletion.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let memo = Todo(content: "다시 진행한 할 일")
        memo.isPinned = true
        let firstSession = FocusSession(
            focusMinutes: 25,
            breakMinutes: 5,
            linkedMemoID: memo.id,
            taskTitleSnapshot: "다시 진행한 할 일"
        )
        let secondSession = FocusSession(
            focusMinutes: 25,
            breakMinutes: 5,
            linkedMemoID: memo.id,
            taskTitleSnapshot: "다시 진행한 할 일"
        )
        context.insert(memo)
        context.insert(firstSession)
        context.insert(secondSession)
        try context.save()
        let firstCompletedAt = Date(timeIntervalSince1970: 1_800_001_000)
        try PomodoroTaskCompletionRecorder.recordCompletion(
            for: firstSession,
            completedAt: firstCompletedAt,
            modelContext: context
        )
        try context.save()

        memo.isCompletedValue = false
        memo.updatedAt = firstCompletedAt.addingTimeInterval(60)
        try context.save()
        let secondCompletedAt = firstCompletedAt.addingTimeInterval(1_800)
        try PomodoroTaskCompletionRecorder.recordCompletion(
            for: secondSession,
            completedAt: secondCompletedAt,
            modelContext: context
        )
        try context.save()

        let affectedMemo = try PomodoroTaskCompletionRecorder.removeCompletion(
            focusSessionID: secondSession.id,
            removedAt: secondCompletedAt.addingTimeInterval(60),
            modelContext: context
        )
        try context.save()

        XCTAssertEqual(affectedMemo?.id, memo.id)
        XCTAssertFalse(memo.isCompletedValue)
        XCTAssertFalse(memo.isPinned)
        let historicalCompletion = try XCTUnwrap(
            context.fetch(FetchDescriptor<PomodoroTaskCompletion>()).first
        )
        XCTAssertEqual(historicalCompletion.focusSessionID, firstSession.id)
        XCTAssertTrue(historicalCompletion.didMarkMemoCompleted)
        XCTAssertEqual(historicalCompletion.memoStateChangedAt, firstCompletedAt)
    }

    @MainActor
    func testRemovingCompletionDoesNotUndoLaterCompletionDecision() throws {
        let schema = Schema([
            Todo.self,
            FocusSession.self,
            PomodoroTaskCompletion.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let memo = Todo(content: "나중에 다시 완료한 일")
        let session = FocusSession(
            focusMinutes: 25,
            breakMinutes: 5,
            linkedMemoID: memo.id,
            taskTitleSnapshot: "나중에 다시 완료한 일"
        )
        context.insert(memo)
        context.insert(session)
        try context.save()
        let completedAt = Date(timeIntervalSince1970: 1_800_001_000)
        try PomodoroTaskCompletionRecorder.recordCompletion(
            for: session,
            completedAt: completedAt,
            modelContext: context
        )
        try context.save()
        memo.setCompleted(false, at: completedAt.addingTimeInterval(30))
        memo.setCompleted(true, at: completedAt.addingTimeInterval(60))
        memo.updatedAt = completedAt.addingTimeInterval(60)
        try context.save()

        let affectedMemo = try PomodoroTaskCompletionRecorder.removeCompletion(
            focusSessionID: session.id,
            modelContext: context
        )
        try context.save()

        XCTAssertNil(affectedMemo)
        XCTAssertTrue(memo.isCompletedValue)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PomodoroTaskCompletion>()).isEmpty)
    }

    @MainActor
    func testRemovingCompletionPreservesUnrelatedMemoEditsAndRestoresCheck() throws {
        let schema = Schema([
            Todo.self,
            FocusSession.self,
            PomodoroTaskCompletion.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let memo = Todo(content: "수정 전 제목")
        let session = FocusSession(
            focusMinutes: 25,
            breakMinutes: 5,
            linkedMemoID: memo.id,
            taskTitleSnapshot: "수정 전 제목"
        )
        context.insert(memo)
        context.insert(session)
        try context.save()
        let completedAt = Date(timeIntervalSince1970: 1_800_001_000)
        try PomodoroTaskCompletionRecorder.recordCompletion(
            for: session,
            completedAt: completedAt,
            modelContext: context
        )
        try context.save()

        memo.content = "완료 후 수정한 제목"
        memo.deadline = completedAt.addingTimeInterval(86_400)
        memo.isPinned = true
        memo.updatedAt = completedAt.addingTimeInterval(60)
        try context.save()
        let removedAt = completedAt.addingTimeInterval(120)

        let affectedMemo = try PomodoroTaskCompletionRecorder.removeCompletion(
            focusSessionID: session.id,
            removedAt: removedAt,
            modelContext: context
        )
        try context.save()

        XCTAssertEqual(affectedMemo?.id, memo.id)
        XCTAssertFalse(memo.isCompletedValue)
        XCTAssertEqual(memo.content, "완료 후 수정한 제목")
        XCTAssertEqual(memo.deadline, completedAt.addingTimeInterval(86_400))
        XCTAssertTrue(memo.isPinned)
        XCTAssertEqual(memo.completionStateChangedAt, removedAt)
    }

    @MainActor
    func testExistingCompletedReflectionIsNotImplicitlyConvertedToTaskCompletion() {
        XCTAssertFalse(
            PomodoroTaskCompletionRecorder.shouldRecordCompletionOnEdit(
                previousResult: .completedAsPlanned,
                newResult: .completedAsPlanned,
                hasExistingCompletion: false
            )
        )
        XCTAssertTrue(
            PomodoroTaskCompletionRecorder.shouldRecordCompletionOnEdit(
                previousResult: .meaningfulProgress,
                newResult: .completedAsPlanned,
                hasExistingCompletion: false
            )
        )
        XCTAssertTrue(
            PomodoroTaskCompletionRecorder.shouldRecordCompletionOnEdit(
                previousResult: .completedAsPlanned,
                newResult: .completedAsPlanned,
                hasExistingCompletion: true
            )
        )
    }

    @MainActor
    func testReflectionEditorDoesNotDefaultUnknownProgressValueToCompletion() {
        XCTAssertNil(
            PomodoroReflectionEditSheet.initialProgressResult(
                rawValue: "future_progress_state"
            )
        )
        XCTAssertEqual(
            PomodoroReflectionEditSheet.initialProgressResult(
                rawValue: PomodoroProgressResult.completedAsPlanned.rawValue
            ),
            .completedAsPlanned
        )
    }

    func testFocusSessionStoresOptionalTaskContext() {
        let memoID = UUID()
        let linkedSession = FocusSession(
            focusMinutes: 25,
            breakMinutes: 5,
            category: "개발",
            linkedMemoID: memoID,
            taskTitleSnapshot: "  통계 회고 표시  "
        )
        let unlinkedSession = FocusSession(
            focusMinutes: 25,
            breakMinutes: 5,
            taskTitleSnapshot: "저장되면 안 되는 제목"
        )

        XCTAssertEqual(linkedSession.linkedMemoID, memoID)
        XCTAssertEqual(linkedSession.taskTitleSnapshot, "통계 회고 표시")
        XCTAssertNil(unlinkedSession.linkedMemoID)
        XCTAssertNil(unlinkedSession.taskTitleSnapshot)
    }

    @MainActor
    func testFocusSessionTaskContextPersistsInSwiftData() throws {
        let schema = Schema([FocusSession.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let memoID = UUID()
        let session = FocusSession(
            focusMinutes: 50,
            breakMinutes: 5,
            linkedMemoID: memoID,
            taskTitleSnapshot: "데이터 계약 확정"
        )

        context.insert(session)
        try context.save()

        let saved = try XCTUnwrap(context.fetch(FetchDescriptor<FocusSession>()).first)
        XCTAssertEqual(saved.linkedMemoID, memoID)
        XCTAssertEqual(saved.taskTitleSnapshot, "데이터 계약 확정")
    }

    @MainActor
    func testCompletedFocusSessionCanRelinkAndUnlinkExistingMemo() throws {
        let schema = Schema([
            FocusSession.self,
            Memo.self,
            PomodoroTaskCompletion.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let session = FocusSession(focusMinutes: 25, breakMinutes: 5, category: "개발")
        session.completed = true
        let memo = Memo(content: "\n  복구할 할 일  \n상세 내용")
        context.insert(session)
        context.insert(memo)
        try context.save()

        try FocusSession.updateTaskLink(
            sessionID: session.id,
            memo: memo,
            modelContext: context
        )

        XCTAssertEqual(session.linkedMemoID, memo.id)
        XCTAssertEqual(session.taskTitleSnapshot, "복구할 할 일")

        try FocusSession.updateTaskLink(
            sessionID: session.id,
            memo: nil,
            modelContext: context
        )

        XCTAssertNil(session.linkedMemoID)
        XCTAssertNil(session.taskTitleSnapshot)
    }

    @MainActor
    func testFocusSessionWithTaskCompletionRejectsRelink() throws {
        let schema = Schema([
            FocusSession.self,
            Memo.self,
            PomodoroTaskCompletion.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let originalMemo = Memo(content: "원래 할 일")
        let replacementMemo = Memo(content: "바꿀 할 일")
        let session = FocusSession(
            focusMinutes: 25,
            breakMinutes: 5,
            category: "개발",
            linkedMemoID: originalMemo.id,
            taskTitleSnapshot: "원래 할 일"
        )
        let completion = PomodoroTaskCompletion(
            focusSessionID: session.id,
            linkedMemoID: originalMemo.id,
            taskTitleSnapshot: "원래 할 일",
            didMarkMemoCompleted: false,
            memoWasPinnedBeforeCompletion: false
        )
        context.insert(originalMemo)
        context.insert(replacementMemo)
        context.insert(session)
        context.insert(completion)
        try context.save()

        XCTAssertThrowsError(
            try FocusSession.updateTaskLink(
                sessionID: session.id,
                memo: replacementMemo,
                modelContext: context
            )
        ) { error in
            XCTAssertEqual(
                error as? FocusSessionTaskLinkUpdateError,
                .taskCompletionExists
            )
        }
        XCTAssertEqual(session.linkedMemoID, originalMemo.id)
        XCTAssertEqual(session.taskTitleSnapshot, "원래 할 일")
    }

    @MainActor
    func testFocusSessionEarlyEndMetadataPersistsInSwiftData() throws {
        let schema = Schema([FocusSession.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let session = FocusSession(
            focusMinutes: 50,
            breakMinutes: 5,
            category: "개발"
        )
        session.completed = true
        session.actualFocusSeconds = 18 * 60 + 42
        session.endKind = .recordedEarly

        context.insert(session)
        try context.save()

        let saved = try XCTUnwrap(context.fetch(FetchDescriptor<FocusSession>()).first)
        XCTAssertEqual(saved.actualFocusSeconds, 18 * 60 + 42)
        XCTAssertEqual(saved.recordedFocusSeconds, 18 * 60 + 42)
        XCTAssertEqual(saved.endKind, .recordedEarly)
    }

    func testTimerManagerElapsedFocusTimeUsesCountdownProgress() {
        XCTAssertEqual(
            TimerManager.elapsedFocusSeconds(
                plannedSeconds: 50 * 60,
                remainingSeconds: 31 * 60 + 18
            ),
            18 * 60 + 42
        )
        XCTAssertEqual(
            TimerManager.elapsedFocusSeconds(
                plannedSeconds: 50 * 60,
                remainingSeconds: 60 * 60
            ),
            0
        )
        XCTAssertEqual(
            TimerManager.elapsedFocusSeconds(
                plannedSeconds: 50 * 60,
                remainingSeconds: -1
            ),
            50 * 60
        )
    }

    @MainActor
    func testTimerManagerRecordsEarlyFocusUsingElapsedCountdown() throws {
        let reflectionKey = Constants.AppStorageKey.pomodoroReflectionEnabled
        let previousReflectionSetting = UserDefaults.standard.object(
            forKey: reflectionKey
        )
        UserDefaults.standard.set(false, forKey: reflectionKey)
        defer {
            if let previousReflectionSetting {
                UserDefaults.standard.set(
                    previousReflectionSetting,
                    forKey: reflectionKey
                )
            } else {
                UserDefaults.standard.removeObject(forKey: reflectionKey)
            }
        }

        let schema = Schema([FocusSession.self, AppUsageRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let appState = AppState()
        appState.focusMinutes = 50
        appState.breakMinutes = 5
        let manager = TimerManager(appState: appState)
        manager.setRepositories(
            focusSessions: SwiftDataFocusSessionRepository(context: context),
            reflections: SwiftDataPomodoroReflectionRepository(context: context)
        )

        manager.startFocus(category: "개발")
        appState.remainingSeconds = 31 * 60 + 18
        manager.endFocusAndRecord()

        // `endFocusAndRecord` 는 이제 `@Model` 을 돌려주지 않는다. 저장된 것을 확인한다.
        let session = try XCTUnwrap(context.fetch(FetchDescriptor<FocusSession>()).first)
        XCTAssertEqual(appState.timerState, .idle)
        XCTAssertEqual(session.actualFocusSeconds, 18 * 60 + 42)
        XCTAssertEqual(session.recordedFocusSeconds, 18 * 60 + 42)
        XCTAssertEqual(session.endKind, .recordedEarly)
        XCTAssertTrue(session.completed)

        let records = try context.fetch(FetchDescriptor<AppUsageRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.durationSeconds, 18 * 60 + 42)
    }

    @MainActor
    func testTimerManagerToggleFocusStartsPausesAndResumes() {
        let appState = AppState()
        let manager = TimerManager(appState: appState)

        manager.toggleFocus(category: "개발")
        XCTAssertEqual(appState.timerState, .focusing)

        manager.toggleFocus(category: "개발")
        XCTAssertEqual(appState.timerState, .paused)

        manager.toggleFocus(category: "개발")
        XCTAssertEqual(appState.timerState, .focusing)

        manager.discardCurrentFocus()
    }

    @MainActor
    func testTimerManagerToggleFocusDoesNothingDuringBreak() {
        let appState = AppState()
        let manager = TimerManager(appState: appState)

        appState.timerState = .breaking
        appState.remainingSeconds = 5 * 60
        manager.toggleFocus(category: "개발")

        XCTAssertEqual(appState.timerState, .breaking)
        XCTAssertEqual(appState.remainingSeconds, 5 * 60)
    }

    @MainActor
    func testTimerManagerRecordsPauseIntervalAcrossResume() throws {
        let schema = Schema([FocusSession.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let appState = AppState()
        appState.focusMinutes = 30
        let manager = TimerManager(appState: appState)
        manager.setRepositories(
            focusSessions: SwiftDataFocusSessionRepository(context: context),
            reflections: SwiftDataPomodoroReflectionRepository(context: context)
        )
        manager.startFocus(category: "개발")

        let session = try XCTUnwrap(context.fetch(FetchDescriptor<FocusSession>()).first)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        session.startedAt = start
        manager.pause(at: start.addingTimeInterval(10 * 60))
        manager.resume(at: start.addingTimeInterval(30 * 60))

        XCTAssertEqual(appState.timerState, .focusing)
        XCTAssertNil(session.pauseStartedAt)
        XCTAssertEqual(
            session.pauseIntervals,
            [
                FocusSessionPauseInterval(
                    startedAt: start.addingTimeInterval(10 * 60),
                    endedAt: start.addingTimeInterval(30 * 60)
                ),
            ]
        )

        manager.discardCurrentFocus()
    }

    @MainActor
    func testTimerManagerDiscardsCurrentFocusWithoutPersistingSession() throws {
        let schema = Schema([FocusSession.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let appState = AppState()
        let manager = TimerManager(appState: appState)
        manager.setRepositories(
            focusSessions: SwiftDataFocusSessionRepository(context: context),
            reflections: SwiftDataPomodoroReflectionRepository(context: context)
        )

        manager.startFocus(category: "개발")
        manager.discardCurrentFocus()

        XCTAssertEqual(appState.timerState, .idle)
        XCTAssertTrue(try context.fetch(FetchDescriptor<FocusSession>()).isEmpty)
    }

    @MainActor
    func testFocusSessionImmersionMetadataPersistsInSwiftData() throws {
        let schema = Schema([FocusSession.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let session = FocusSession(
            focusMinutes: 50,
            breakMinutes: 5,
            category: "개발"
        )
        session.inputActiveSeconds = 2_100
        session.markerColorKey = "purple"
        let reflectionDeferredAt = Date(timeIntervalSince1970: 1_800_000_000)
        session.reflectionDeferredAt = reflectionDeferredAt

        context.insert(session)
        try context.save()

        let saved = try XCTUnwrap(context.fetch(FetchDescriptor<FocusSession>()).first)
        XCTAssertEqual(saved.inputActiveSeconds, 2_100)
        XCTAssertEqual(saved.markerColorKey, "purple")
        XCTAssertEqual(saved.reflectionDeferredAt, reflectionDeferredAt)
    }

    func testFocusSessionRowOnlyMarksDeferredMissingReflectionAsPending() {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let deferredAt = startedAt.addingTimeInterval(60)
        let pending = makeFocusSessionRow(
            category: "개발",
            startedAt: startedAt,
            durationSeconds: 25 * 60,
            reflectionDeferredAt: deferredAt
        )
        let reflectionDisabled = makeFocusSessionRow(
            category: "개발",
            startedAt: startedAt,
            durationSeconds: 25 * 60
        )
        let answered = makeFocusSessionRow(
            category: "개발",
            startedAt: startedAt,
            durationSeconds: 25 * 60,
            selfAssessmentLabel: PomodoroFocusExperience.mostlyFocused.label,
            reflectionDeferredAt: deferredAt
        )

        XCTAssertTrue(pending.isReflectionPending)
        XCTAssertFalse(reflectionDisabled.isReflectionPending)
        XCTAssertFalse(answered.isReflectionPending)
    }

    @MainActor
    func testResetMarkerColorsOnlyAffectsSelectedCategory() throws {
        let schema = Schema([FocusSession.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        let customizedDevelopment = FocusSession(
            focusMinutes: 50,
            breakMinutes: 5,
            category: "개발"
        )
        customizedDevelopment.markerColorKey = "purple"
        let defaultDevelopment = FocusSession(
            focusMinutes: 25,
            breakMinutes: 5,
            category: "개발"
        )
        let customizedStudy = FocusSession(
            focusMinutes: 25,
            breakMinutes: 5,
            category: "공부"
        )
        customizedStudy.markerColorKey = "pink"

        context.insert(customizedDevelopment)
        context.insert(defaultDevelopment)
        context.insert(customizedStudy)
        try context.save()

        let resetCount = try FocusSession.resetMarkerColors(
            for: "개발",
            in: context
        )

        XCTAssertEqual(resetCount, 1)
        XCTAssertNil(customizedDevelopment.markerColorKey)
        XCTAssertNil(defaultDevelopment.markerColorKey)
        XCTAssertEqual(customizedStudy.markerColorKey, "pink")
    }

    /// 완료·보관·삭제분은 이제 **저장소가 술어로 떨군다**
    /// (`SwiftDataPomodoroTaskRepositoryTests` 가 그쪽을 검사한다).
    /// 여기서는 「오늘 것인가 · 목표에 묶였는가」만 본다.
    func testPomodoroTaskCandidatesIncludeGoalLinkedAndTodayTasksOnce() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 12))!
        let today = calendar.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 9))!
        let tomorrow = calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 9))!

        func memo(_ content: String, start: Date? = nil) -> AchievementMemoDetail {
            AchievementMemoDetail(
                id: UUID(),
                content: content,
                icon: nil,
                startDate: start,
                deadline: nil,
                updatedAt: now,
                isCompleted: false
            )
        }

        let goalLinked = memo("\n  통계 회고 결과 표시\n상세 설명")
        let todayOnly = memo("오늘 시작할 일", start: today)
        let todayAndGoalLinked = memo("오늘의 목표 할 일", start: today)
        let future = memo("내일 시작할 일", start: tomorrow)
        let noStartDate = memo("시작일이 없는 일반 할 일")

        let candidates = PomodoroTaskCandidateBuilder.candidates(
            memos: [goalLinked, todayOnly, todayAndGoalLinked, future, noStartDate],
            goalLinkedMemoIDs: [goalLinked.id, todayAndGoalLinked.id],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(candidates, [
            PomodoroTaskCandidate(
                id: goalLinked.id,
                title: "통계 회고 결과 표시",
                isToday: false,
                isGoalLinked: true,
                durationMinutes: nil
            ),
            PomodoroTaskCandidate(
                id: todayOnly.id,
                title: "오늘 시작할 일",
                isToday: true,
                isGoalLinked: false,
                durationMinutes: nil
            ),
            PomodoroTaskCandidate(
                id: todayAndGoalLinked.id,
                title: "오늘의 목표 할 일",
                isToday: true,
                isGoalLinked: true,
                durationMinutes: nil
            )
        ])
    }

    func testPomodoroTaskCandidatePreservesFullTitleForSessionSnapshot() throws {
        let fullTitle = String(repeating: "긴 작업 제목 ", count: 8)
            .trimmingCharacters(in: .whitespaces)
        let memo = AchievementMemoDetail(
            id: UUID(),
            content: "\(fullTitle)\n상세 설명",
            icon: nil,
            startDate: nil,
            deadline: nil,
            updatedAt: Date(),
            isCompleted: false
        )

        let candidate = try XCTUnwrap(
            PomodoroTaskCandidateBuilder.candidates(
                memos: [memo],
                goalLinkedMemoIDs: [memo.id]
            ).first
        )

        XCTAssertEqual(candidate.title, fullTitle)
        XCTAssertFalse(candidate.title.hasSuffix("..."))
    }

    func testFocusCategorySummariesSortCurrentPeriodByTotalDuration() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let rows = [
            makeFocusSessionRow(
                category: "개발",
                startedAt: start,
                durationSeconds: 600
            ),
            makeFocusSessionRow(
                category: "공부",
                startedAt: start.addingTimeInterval(900),
                durationSeconds: 1_200
            ),
            makeFocusSessionRow(
                category: "개발",
                startedAt: start.addingTimeInterval(2_400),
                durationSeconds: 300
            ),
        ]

        XCTAssertEqual(
            FocusCategorySummaryBuilder.summaries(rows: rows),
            [
                FocusCategorySummary(
                    category: "공부",
                    durationSeconds: 1_200,
                    sessionCount: 1
                ),
                FocusCategorySummary(
                    category: "개발",
                    durationSeconds: 900,
                    sessionCount: 2
                ),
            ]
        )
    }

    func testFocusPeriodCalendarBuildsMondayBasedWeek() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let referenceDate = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 22
                )
            )
        )

        let dates = FocusPeriodCalendarBuilder.weekDates(
            containing: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(
            dates.map { calendar.component(.day, from: $0) },
            [20, 21, 22, 23, 24, 25, 26]
        )
        XCTAssertEqual(
            dates.map {
                FocusPeriodCalendarBuilder.mondayIndex(
                    for: $0,
                    calendar: calendar
                )
            },
            [0, 1, 2, 3, 4, 5, 6]
        )
    }

    func testFocusPeriodCalendarPadsMonthIntoCompleteWeeks() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let referenceDate = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 15
                )
            )
        )

        let weeks = FocusPeriodCalendarBuilder.monthWeeks(
            containing: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(weeks.count, 5)
        XCTAssertTrue(weeks.allSatisfy { $0.count == 7 })
        XCTAssertNil(weeks[0][0])
        XCTAssertNil(weeks[0][1])
        XCTAssertEqual(
            calendar.component(
                .day,
                from: try XCTUnwrap(weeks[0][2])
            ),
            1
        )
        XCTAssertEqual(
            calendar.component(
                .day,
                from: try XCTUnwrap(weeks[4][4])
            ),
            31
        )
        XCTAssertNil(weeks[4][5])
        XCTAssertNil(weeks[4][6])
    }

    func testFocusTaskSessionGroupsUseLinkedMemoIDAndKeepUnlinkedSessionsSeparate() throws {
        let memoID = UUID()
        let completedSessionID = UUID()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let rows = [
            makeFocusSessionRow(
                linkedMemoID: memoID,
                title: "통계 화면 구현",
                category: "개발",
                startedAt: start,
                durationSeconds: 1_500,
                plannedDurationSeconds: 1_500,
                endKind: .timerCompleted,
                selfAssessmentLabel: PomodoroFocusExperience.deeplyFocused.label
            ),
            makeFocusSessionRow(
                id: completedSessionID,
                linkedMemoID: memoID,
                title: "통계 화면 구현 완료",
                category: "개발",
                startedAt: start.addingTimeInterval(1_800),
                durationSeconds: 900,
                plannedDurationSeconds: 1_500,
                endKind: .recordedEarly,
                selfAssessmentLabel: PomodoroFocusExperience.mostlyFocused.label
            ),
            makeFocusSessionRow(
                title: "연결하지 않고 진행",
                category: "기타",
                startedAt: start.addingTimeInterval(3_600),
                durationSeconds: 600
            ),
            makeFocusSessionRow(
                title: "연결하지 않고 진행",
                category: "기타",
                startedAt: start.addingTimeInterval(4_500),
                durationSeconds: 600
            ),
        ]

        let groups = FocusTaskSessionGroupBuilder.groups(
            rows: rows,
            completedSessionIDs: [completedSessionID]
        )

        XCTAssertEqual(groups.count, 3)

        let linkedGroup = try XCTUnwrap(
            groups.first { $0.linkedMemoID == memoID }
        )
        XCTAssertEqual(linkedGroup.title, "통계 화면 구현 완료")
        XCTAssertEqual(linkedGroup.rows.map(\.startedAt), [
            start,
            start.addingTimeInterval(1_800),
        ])
        XCTAssertEqual(linkedGroup.totalDurationSeconds, 2_400)
        XCTAssertEqual(linkedGroup.completedAsPlannedCount, 1)
        XCTAssertEqual(linkedGroup.endedEarlyCount, 1)
        XCTAssertEqual(linkedGroup.unknownEndCount, 0)
        XCTAssertEqual(linkedGroup.categories, ["개발"])
        XCTAssertEqual(linkedGroup.assessmentCounts.map(\.label), [
            PomodoroFocusExperience.deeplyFocused.label,
            PomodoroFocusExperience.mostlyFocused.label,
        ])
        XCTAssertEqual(linkedGroup.assessmentCounts.map(\.count), [1, 1])
        XCTAssertTrue(linkedGroup.completedInPeriod)

        let unlinkedGroups = groups.filter { $0.linkedMemoID == nil }
        XCTAssertEqual(unlinkedGroups.count, 2)
        XCTAssertTrue(unlinkedGroups.allSatisfy { $0.rows.count == 1 })
        XCTAssertEqual(Set(unlinkedGroups.map(\.id)).count, 2)
    }

    func testFocusTaskSessionTrendPointsKeepChronologyAndMissingValues() throws {
        let firstSessionID = UUID()
        let secondSessionID = UUID()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let secondStart = start.addingTimeInterval(1_800)
        let rows = [
            makeFocusSessionRow(
                id: secondSessionID,
                category: "개발",
                startedAt: secondStart,
                durationSeconds: 1_200,
                plannedDurationSeconds: 1_500,
                endKind: .recordedEarly,
                rating: 3,
                selfAssessmentLabel: PomodoroFocusExperience.mostlyFocused.label,
                progressResult: .meaningfulProgress,
                incompleteReason: .underestimatedScope
            ),
            makeFocusSessionRow(
                id: firstSessionID,
                category: "개발",
                startedAt: start,
                durationSeconds: 1_500,
                plannedDurationSeconds: 1_500,
                endKind: .timerCompleted,
                rating: 4,
                selfAssessmentLabel: PomodoroFocusExperience.deeplyFocused.label,
                progressResult: .completedAsPlanned
            ),
        ]

        let points = FocusTaskSessionTrendBuilder.points(
            rows: rows,
            completedSessionIDs: [firstSessionID]
        )

        XCTAssertEqual(points.map(\.id), [firstSessionID, secondSessionID])
        XCTAssertEqual(points.map(\.iteration), [1, 2])

        let firstPoint = try XCTUnwrap(points.first)
        XCTAssertEqual(firstPoint.selfAssessmentRating, 4)
        XCTAssertEqual(firstPoint.progressResult, .completedAsPlanned)
        XCTAssertEqual(firstPoint.progressScore, 3)
        XCTAssertTrue(firstPoint.taskCompleted)

        let secondPoint = try XCTUnwrap(points.last)
        XCTAssertEqual(secondPoint.completionStatus, .endedEarly)
        XCTAssertEqual(secondPoint.selfAssessmentRating, 3)
        XCTAssertEqual(secondPoint.progressResult, .meaningfulProgress)
        XCTAssertEqual(secondPoint.incompleteReason, .underestimatedScope)
        XCTAssertEqual(secondPoint.progressScore, 2)
        XCTAssertTrue(secondPoint.canPlotOnCauseMap)
        XCTAssertFalse(secondPoint.taskCompleted)
    }

    func testFocusTaskContinuationCausesUseDirectReflectionReasons() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let rows = [
            makeFocusSessionRow(
                category: "개발",
                startedAt: start,
                durationSeconds: 1_500,
                rating: 4,
                progressResult: .meaningfulProgress,
                incompleteReason: .underestimatedScope
            ),
            makeFocusSessionRow(
                category: "개발",
                startedAt: start.addingTimeInterval(1_800),
                durationSeconds: 1_500,
                rating: 4,
                progressResult: .littleProgress,
                incompleteReason: .blocked
            ),
            makeFocusSessionRow(
                category: "개발",
                startedAt: start.addingTimeInterval(3_600),
                durationSeconds: 1_500,
                rating: 1,
                progressResult: .littleProgress,
                incompleteReason: .distracted
            ),
            makeFocusSessionRow(
                category: "개발",
                startedAt: start.addingTimeInterval(5_400),
                durationSeconds: 1_500,
                rating: 3,
                progressResult: .goalChanged,
                incompleteReason: .switchedTask
            ),
        ]

        let summary = FocusTaskContinuationCauseBuilder.summary(
            points: FocusTaskSessionTrendBuilder.points(rows: rows)
        )
        let evidence = Dictionary(
            uniqueKeysWithValues: summary.evidence.map { ($0.cause, $0) }
        )

        XCTAssertEqual(
            FocusTaskContinuationCause.allCases.map {
                evidence[$0]?.directSessionCount
            },
            [1, 1, 1, 1]
        )
        XCTAssertTrue(
            FocusTaskContinuationCause.allCases.allSatisfy {
                evidence[$0]?.supportingSessionCount == 0
            }
        )
        XCTAssertNil(summary.dominantCause)
        XCTAssertEqual(summary.headline, "여러 이유가 함께 기록됐어요")
    }

    func testFocusTaskContinuationCausesKeepInferredSignalsSeparate() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let completedSessionID = UUID()
        let rows = [
            makeFocusSessionRow(
                category: "개발",
                startedAt: start,
                durationSeconds: 1_500,
                rating: 4,
                progressResult: .meaningfulProgress
            ),
            makeFocusSessionRow(
                category: "개발",
                startedAt: start.addingTimeInterval(1_800),
                durationSeconds: 1_500,
                rating: 4,
                progressResult: .littleProgress
            ),
            makeFocusSessionRow(
                category: "개발",
                startedAt: start.addingTimeInterval(3_600),
                durationSeconds: 1_500,
                rating: 1,
                progressResult: .meaningfulProgress
            ),
            makeFocusSessionRow(
                id: completedSessionID,
                category: "개발",
                startedAt: start.addingTimeInterval(5_400),
                durationSeconds: 1_500,
                rating: 4,
                progressResult: .completedAsPlanned
            ),
        ]
        let points = FocusTaskSessionTrendBuilder.points(
            rows: rows,
            completedSessionIDs: [completedSessionID]
        )
        let summary = FocusTaskContinuationCauseBuilder.summary(points: points)
        let evidence = Dictionary(
            uniqueKeysWithValues: summary.evidence.map { ($0.cause, $0) }
        )

        XCTAssertTrue(
            FocusTaskContinuationCause.allCases.allSatisfy {
                evidence[$0]?.directSessionCount == 0
            }
        )
        XCTAssertEqual(evidence[.scopeOrQuality]?.supportingSessionCount, 1)
        XCTAssertEqual(evidence[.difficultyOrBlocked]?.supportingSessionCount, 1)
        XCTAssertEqual(evidence[.focusDisruption]?.supportingSessionCount, 1)
        XCTAssertEqual(evidence[.contextChange]?.supportingSessionCount, 0)
        XCTAssertEqual(
            summary.headline,
            "직접 선택한 이유가 없어 응답 조합만 보여드려요"
        )
        XCTAssertEqual(points.map(\.progressScore), [2, 1, 2, 3])
        XCTAssertEqual(points.last?.taskCompleted, true)
    }

    func testPomodoroTaskSummariesGroupByMemoIDAndKeepUnlinkedSessionsSeparate() throws {
        let firstMemoID = UUID()
        let secondMemoID = UUID()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let sessions = [
            PomodoroTimeSummary(
                id: UUID(),
                startedAt: start,
                endedAt: start.addingTimeInterval(1_500),
                category: "개발",
                linkedMemoID: firstMemoID,
                taskTitle: "통계 요약 구현",
                durationSeconds: 1_500
            ),
            PomodoroTimeSummary(
                id: UUID(),
                startedAt: start.addingTimeInterval(1_800),
                endedAt: start.addingTimeInterval(2_700),
                category: "개발",
                linkedMemoID: secondMemoID,
                taskTitle: "통계 요약 구현 완료",
                durationSeconds: 900
            ),
            PomodoroTimeSummary(
                id: UUID(),
                startedAt: start.addingTimeInterval(3_600),
                endedAt: start.addingTimeInterval(4_800),
                category: "개발",
                linkedMemoID: firstMemoID,
                taskTitle: "통계 요약 구현 완료",
                durationSeconds: 1_200
            ),
            PomodoroTimeSummary(
                id: UUID(),
                startedAt: start.addingTimeInterval(900),
                endedAt: start.addingTimeInterval(1_500),
                category: "기타",
                linkedMemoID: nil,
                taskTitle: nil,
                durationSeconds: 600
            ),
            PomodoroTimeSummary(
                id: UUID(),
                startedAt: start.addingTimeInterval(5_400),
                endedAt: start.addingTimeInterval(6_000),
                category: "기타",
                linkedMemoID: nil,
                taskTitle: nil,
                durationSeconds: 600
            ),
        ]

        let summaries = PomodoroTaskSummaryBuilder.summaries(
            sessions: sessions,
            reflections: []
        )

        XCTAssertEqual(summaries.count, 3)
        XCTAssertEqual(summaries.map(\.linkedMemoID), [firstMemoID, secondMemoID, nil])

        let firstSummary = try XCTUnwrap(summaries.first)
        XCTAssertEqual(firstSummary.taskTitle, "통계 요약 구현 완료")
        XCTAssertEqual(firstSummary.sessionCount, 2)
        XCTAssertEqual(firstSummary.durationSeconds, 2_700)

        let secondSummary = try XCTUnwrap(summaries.dropFirst().first)
        XCTAssertEqual(secondSummary.taskTitle, "통계 요약 구현 완료")
        XCTAssertEqual(secondSummary.sessionCount, 1)
        XCTAssertEqual(secondSummary.durationSeconds, 900)

        let unlinkedSummary = try XCTUnwrap(summaries.last)
        XCTAssertNil(unlinkedSummary.linkedMemoID)
        XCTAssertEqual(unlinkedSummary.displayTitle, "연결하지 않고 진행")
        XCTAssertEqual(unlinkedSummary.sessionCount, 2)
        XCTAssertEqual(unlinkedSummary.durationSeconds, 1_200)
    }

    func testPomodoroTaskSummariesAggregateOnlyMatchingSessionReflections() throws {
        let memoID = UUID()
        let firstSessionID = UUID()
        let secondSessionID = UUID()
        let unknownSessionID = UUID()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let sessions = [
            PomodoroTimeSummary(
                id: firstSessionID,
                startedAt: start,
                endedAt: start.addingTimeInterval(1_500),
                category: "개발",
                linkedMemoID: memoID,
                taskTitle: "회고 집계",
                durationSeconds: 1_500
            ),
            PomodoroTimeSummary(
                id: secondSessionID,
                startedAt: start.addingTimeInterval(1_800),
                endedAt: start.addingTimeInterval(3_300),
                category: "개발",
                linkedMemoID: memoID,
                taskTitle: "회고 집계",
                durationSeconds: 1_500
            ),
            PomodoroTimeSummary(
                id: unknownSessionID,
                startedAt: start.addingTimeInterval(3_600),
                endedAt: start.addingTimeInterval(5_100),
                category: "개발",
                linkedMemoID: memoID,
                taskTitle: "회고 집계",
                durationSeconds: 1_500
            ),
        ]
        let unknownReflection = PomodoroReflection(
            focusSessionID: unknownSessionID,
            focusExperience: .unsure,
            progressResult: .goalChanged,
            incompleteReason: .switchedTask
        )
        unknownReflection.focusExperienceRawValue = "future_focus_state"
        unknownReflection.progressResultRawValue = "future_progress_state"
        let reflections = [
            PomodoroReflection(
                focusSessionID: firstSessionID,
                focusExperience: .deeplyFocused,
                progressResult: .completedAsPlanned
            ),
            PomodoroReflection(
                focusSessionID: secondSessionID,
                focusExperience: .deeplyFocused,
                progressResult: .meaningfulProgress,
                incompleteReason: .underestimatedScope
            ),
            unknownReflection,
            PomodoroReflection(
                focusSessionID: UUID(),
                focusExperience: .difficultToFocus,
                progressResult: .littleProgress,
                incompleteReason: .distracted
            ),
        ]

        let summary = try XCTUnwrap(
            PomodoroTaskSummaryBuilder.summaries(
                sessions: sessions,
                reflections: reflections
            ).first
        )

        XCTAssertEqual(summary.reflectionCount, 3)
        XCTAssertEqual(
            summary.focusExperienceCounts,
            [
                PomodoroReflectionOptionCount(
                    id: PomodoroFocusExperience.deeplyFocused.rawValue,
                    label: PomodoroFocusExperience.deeplyFocused.label,
                    count: 2
                ),
                PomodoroReflectionOptionCount(
                    id: "unknown_focus_experience",
                    label: "확인할 수 없는 응답",
                    count: 1
                )
            ]
        )
        XCTAssertEqual(
            summary.progressResultCounts,
            [
                PomodoroReflectionOptionCount(
                    id: PomodoroProgressResult.completedAsPlanned.rawValue,
                    label: PomodoroProgressResult.completedAsPlanned.label,
                    count: 1
                ),
                PomodoroReflectionOptionCount(
                    id: PomodoroProgressResult.meaningfulProgress.rawValue,
                    label: PomodoroProgressResult.meaningfulProgress.label,
                    count: 1
                ),
                PomodoroReflectionOptionCount(
                    id: "unknown_progress_result",
                    label: "확인할 수 없는 응답",
                    count: 1
                ),
            ]
        )
    }

    func testPomodoroTaskSummariesDistinguishExplicitTaskCompletionFromLegacyAnswer() throws {
        let memoID = UUID()
        let legacySessionID = UUID()
        let completedSessionID = UUID()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let completedAt = start.addingTimeInterval(3_400)
        let sessions = [
            PomodoroTimeSummary(
                id: legacySessionID,
                startedAt: start,
                endedAt: start.addingTimeInterval(1_500),
                category: "개발",
                linkedMemoID: memoID,
                taskTitle: "완료 의미 구분",
                durationSeconds: 1_500
            ),
            PomodoroTimeSummary(
                id: completedSessionID,
                startedAt: start.addingTimeInterval(1_800),
                endedAt: start.addingTimeInterval(3_300),
                category: "개발",
                linkedMemoID: memoID,
                taskTitle: "완료 의미 구분",
                durationSeconds: 1_500
            ),
        ]
        let reflections = [
            PomodoroReflection(
                focusSessionID: legacySessionID,
                focusExperience: .mostlyFocused,
                progressResult: .completedAsPlanned
            ),
            PomodoroReflection(
                focusSessionID: completedSessionID,
                focusExperience: .deeplyFocused,
                progressResult: .completedAsPlanned
            ),
        ]
        let completion = PomodoroTaskCompletion(
            focusSessionID: completedSessionID,
            linkedMemoID: memoID,
            taskTitleSnapshot: "완료 의미 구분",
            completedAt: completedAt,
            didMarkMemoCompleted: true,
            memoWasPinnedBeforeCompletion: false
        )

        let summary = try XCTUnwrap(
            PomodoroTaskSummaryBuilder.summaries(
                sessions: sessions,
                reflections: reflections,
                completions: [completion]
            ).first
        )

        XCTAssertEqual(summary.completedSessionID, completedSessionID)
        XCTAssertEqual(summary.completedAt, completedAt)
        XCTAssertEqual(
            summary.progressResultCounts,
            [
                PomodoroReflectionOptionCount(
                    id: "linked_task_completed",
                    label: "이 할 일을 모두 끝냈어요",
                    count: 1
                ),
                PomodoroReflectionOptionCount(
                    id: PomodoroProgressResult.completedAsPlanned.rawValue,
                    label: PomodoroProgressResult.completedAsPlanned.label,
                    count: 1
                ),
            ]
        )
    }

    @MainActor
    func testPomodoroSessionObservationClipsAndKeepsObjectiveFacts() {
        let start = Date(timeIntervalSince1970: 1_800_100_000)
        let end = start.addingTimeInterval(25 * 60)
        let segments = [
            AppUsageSegment(
                appName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                category: "조사",
                startTime: start.addingTimeInterval(16 * 60),
                endTime: start.addingTimeInterval(18 * 60)
            ),
            AppUsageSegment(
                appName: "Xcode",
                bundleIdentifier: "com.apple.dt.Xcode",
                category: "개발",
                startTime: start.addingTimeInterval(-2 * 60),
                endTime: start.addingTimeInterval(5 * 60)
            ),
            AppUsageSegment(
                appName: "Xcode",
                bundleIdentifier: "com.apple.dt.Xcode",
                category: "개발",
                startTime: start.addingTimeInterval(5 * 60),
                endTime: start.addingTimeInterval(10 * 60)
            ),
            AppUsageSegment(
                appName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                category: "조사",
                startTime: start.addingTimeInterval(10 * 60),
                endTime: start.addingTimeInterval(15 * 60)
            ),
            AppUsageSegment(
                appName: "Xcode",
                bundleIdentifier: "com.apple.dt.Xcode",
                category: "개발",
                startTime: start.addingTimeInterval(18 * 60),
                endTime: start.addingTimeInterval(30 * 60)
            ),
        ]

        let observation = PomodoroSessionObservationBuilder.observation(
            from: start,
            to: end,
            segments: segments
        )

        XCTAssertTrue(observation.hasRecords)
        XCTAssertEqual(observation.sessionSeconds, 25 * 60)
        XCTAssertEqual(observation.recordedSeconds, 24 * 60)
        XCTAssertEqual(observation.unrecordedSeconds, 60)
        XCTAssertEqual(observation.ambiguousOverlapSeconds, 0)
        XCTAssertEqual(observation.userModifiedRecordedSeconds, 0)
        XCTAssertEqual(observation.appSwitchCount, 2)
        XCTAssertEqual(observation.appUsageRunCount, 3)
        XCTAssertEqual(
            observation.averageAppUsageRunSeconds ?? -1,
            8 * 60,
            accuracy: 0.001
        )
        XCTAssertEqual(observation.categorySwitchCount, 2)
        XCTAssertEqual(
            observation.categoryTransitions,
            [
                PomodoroCategoryTransition(source: "개발", target: "조사", count: 1),
                PomodoroCategoryTransition(source: "조사", target: "개발", count: 1),
            ]
        )
        XCTAssertEqual(
            observation.longestContinuousAppUsage,
            PomodoroContinuousAppUsage(
                appName: "Xcode",
                category: "개발",
                durationSeconds: 10 * 60
            )
        )
        XCTAssertEqual(
            observation.apps,
            [
                PomodoroAppUsageEntry(appName: "Xcode", category: "개발", durationSeconds: 17 * 60),
                PomodoroAppUsageEntry(appName: "Safari", category: "조사", durationSeconds: 7 * 60),
            ]
        )
        XCTAssertEqual(
            observation.categories,
            [
                PomodoroCategoryUsageEntry(category: "개발", durationSeconds: 17 * 60),
                PomodoroCategoryUsageEntry(category: "조사", durationSeconds: 7 * 60),
            ]
        )
    }

    @MainActor
    func testPomodoroSessionObservationIsEmptyWithoutOverlappingRecords() {
        let start = Date(timeIntervalSince1970: 1_800_200_000)
        let end = start.addingTimeInterval(25 * 60)
        let segments = [
            AppUsageSegment(
                appName: "Xcode",
                bundleIdentifier: "com.apple.dt.Xcode",
                category: "개발",
                startTime: start.addingTimeInterval(-10 * 60),
                endTime: start
            ),
            AppUsageSegment(
                appName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                category: "조사",
                startTime: end,
                endTime: end.addingTimeInterval(10 * 60)
            ),
        ]

        let observation = PomodoroSessionObservationBuilder.observation(
            from: start,
            to: end,
            segments: segments
        )

        XCTAssertFalse(observation.hasRecords)
        XCTAssertEqual(observation.sessionSeconds, 25 * 60)
        XCTAssertEqual(observation.recordedSeconds, 0)
        XCTAssertEqual(observation.unrecordedSeconds, 25 * 60)
        XCTAssertEqual(observation.ambiguousOverlapSeconds, 0)
        XCTAssertEqual(observation.userModifiedRecordedSeconds, 0)
        XCTAssertEqual(observation.appSwitchCount, 0)
        XCTAssertEqual(observation.appUsageRunCount, 0)
        XCTAssertNil(observation.averageAppUsageRunSeconds)
        XCTAssertEqual(observation.categorySwitchCount, 0)
        XCTAssertEqual(observation.categoryTransitions, [])
        XCTAssertNil(observation.longestContinuousAppUsage)
        XCTAssertEqual(observation.apps, [])
        XCTAssertEqual(observation.categories, [])
    }

    @MainActor
    func testPomodoroSessionObservationSeparatesAmbiguousOverlap() {
        let start = Date(timeIntervalSince1970: 1_800_300_000)
        let end = start.addingTimeInterval(25 * 60)
        let segments = [
            AppUsageSegment(
                appName: "Xcode",
                bundleIdentifier: "com.apple.dt.Xcode",
                category: "개발",
                startTime: start,
                endTime: start.addingTimeInterval(10 * 60)
            ),
            AppUsageSegment(
                appName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                category: "조사",
                startTime: start.addingTimeInterval(5 * 60),
                endTime: start.addingTimeInterval(15 * 60),
                isManual: true
            ),
        ]

        let observation = PomodoroSessionObservationBuilder.observation(
            from: start,
            to: end,
            segments: segments
        )

        XCTAssertEqual(observation.recordedSeconds, 15 * 60)
        XCTAssertEqual(observation.unrecordedSeconds, 10 * 60)
        XCTAssertEqual(observation.ambiguousOverlapSeconds, 5 * 60)
        XCTAssertEqual(observation.userModifiedRecordedSeconds, 10 * 60)
        XCTAssertEqual(observation.appSwitchCount, 1)
        XCTAssertEqual(observation.appUsageRunCount, 2)
        XCTAssertEqual(
            observation.averageAppUsageRunSeconds ?? -1,
            5 * 60,
            accuracy: 0.001
        )
        XCTAssertEqual(observation.categorySwitchCount, 0)
        XCTAssertEqual(observation.categoryTransitions, [])
        XCTAssertEqual(observation.apps.reduce(0) { $0 + $1.durationSeconds }, 10 * 60)
        XCTAssertEqual(observation.categories.reduce(0) { $0 + $1.durationSeconds }, 10 * 60)
        XCTAssertEqual(
            observation.longestContinuousAppUsage,
            PomodoroContinuousAppUsage(
                appName: "Xcode",
                category: "개발",
                durationSeconds: 5 * 60
            )
        )
    }

    @MainActor
    func testPomodoroSessionObservationCountsObservedAppChangeAcrossGap() {
        let start = Date(timeIntervalSince1970: 1_800_400_000)
        let end = start.addingTimeInterval(25 * 60)
        let segments = [
            AppUsageSegment(
                appName: "Chrome",
                bundleIdentifier: "virtual.browser.research",
                category: "조사",
                startTime: start,
                endTime: start.addingTimeInterval(5 * 60)
            ),
            AppUsageSegment(
                appName: "Chrome",
                bundleIdentifier: "virtual.browser.docs",
                category: "조사",
                startTime: start.addingTimeInterval(5 * 60),
                endTime: start.addingTimeInterval(10 * 60)
            ),
            AppUsageSegment(
                appName: "Xcode",
                bundleIdentifier: "com.apple.dt.Xcode",
                category: "개발",
                startTime: start.addingTimeInterval(11 * 60),
                endTime: start.addingTimeInterval(15 * 60)
            ),
        ]

        let observation = PomodoroSessionObservationBuilder.observation(
            from: start,
            to: end,
            segments: segments
        )

        XCTAssertEqual(observation.appSwitchCount, 1)
        XCTAssertEqual(observation.appUsageRunCount, 2)
        XCTAssertEqual(
            observation.averageAppUsageRunSeconds ?? -1,
            7 * 60,
            accuracy: 0.001
        )
        XCTAssertEqual(observation.categorySwitchCount, 0)
        XCTAssertEqual(observation.categoryTransitions, [])
        XCTAssertEqual(
            observation.longestContinuousAppUsage,
            PomodoroContinuousAppUsage(
                appName: "Chrome",
                category: "조사",
                durationSeconds: 10 * 60
            )
        )
        XCTAssertEqual(
            observation.apps,
            [
                PomodoroAppUsageEntry(appName: "Chrome", category: "조사", durationSeconds: 10 * 60),
                PomodoroAppUsageEntry(appName: "Xcode", category: "개발", durationSeconds: 4 * 60),
            ]
        )
    }

    @MainActor
    func testPomodoroSessionObservationBreaksLongestRunAtGap() {
        let start = Date(timeIntervalSince1970: 1_800_500_000)
        let end = start.addingTimeInterval(25 * 60)
        let segments = [
            AppUsageSegment(
                appName: "Xcode",
                bundleIdentifier: "com.apple.dt.Xcode",
                category: "개발",
                startTime: start,
                endTime: start.addingTimeInterval(5 * 60)
            ),
            AppUsageSegment(
                appName: "Xcode",
                bundleIdentifier: "com.apple.dt.Xcode",
                category: "개발",
                startTime: start.addingTimeInterval(6 * 60),
                endTime: start.addingTimeInterval(11 * 60)
            ),
        ]

        let observation = PomodoroSessionObservationBuilder.observation(
            from: start,
            to: end,
            segments: segments
        )

        XCTAssertEqual(
            observation.longestContinuousAppUsage,
            PomodoroContinuousAppUsage(
                appName: "Xcode",
                category: "개발",
                durationSeconds: 5 * 60
            )
        )
    }

    @MainActor
    func testPomodoroSessionObservationCountsTrackerSizedGapAsDirectSwitch() {
        let start = Date(timeIntervalSince1970: 1_800_600_000)
        let end = start.addingTimeInterval(25 * 60)
        let segments = [
            AppUsageSegment(
                appName: "Xcode",
                bundleIdentifier: "com.apple.dt.Xcode",
                category: "개발",
                startTime: start,
                endTime: start.addingTimeInterval(5 * 60)
            ),
            AppUsageSegment(
                appName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                category: "조사",
                startTime: start.addingTimeInterval(5 * 60 + 0.25),
                endTime: start.addingTimeInterval(10 * 60 + 0.25)
            ),
        ]

        let observation = PomodoroSessionObservationBuilder.observation(
            from: start,
            to: end,
            segments: segments
        )

        XCTAssertEqual(observation.appSwitchCount, 1)
        XCTAssertEqual(observation.categorySwitchCount, 1)
        XCTAssertEqual(
            observation.categoryTransitions,
            [PomodoroCategoryTransition(source: "개발", target: "조사", count: 1)]
        )
    }

    @MainActor
    func testPomodoroSessionObservationCountsUnclassifiedAppsWithoutInventingCategoryTransitions() {
        let start = Date(timeIntervalSince1970: 1_800_625_000)
        let end = start.addingTimeInterval(15 * 60)
        let segments = [
            AppUsageSegment(
                appName: "Xcode",
                bundleIdentifier: "com.apple.dt.Xcode",
                category: "개발",
                startTime: start,
                endTime: start.addingTimeInterval(5 * 60)
            ),
            AppUsageSegment(
                appName: "Orca",
                bundleIdentifier: "com.stablyai.orca",
                category: Constants.unclassifiedAppCategory,
                startTime: start.addingTimeInterval(5 * 60),
                endTime: start.addingTimeInterval(10 * 60)
            ),
            AppUsageSegment(
                appName: "Slack",
                bundleIdentifier: "com.tinyspeck.slackmacgap",
                category: "업무",
                startTime: start.addingTimeInterval(10 * 60),
                endTime: end
            ),
        ]

        let observation = PomodoroSessionObservationBuilder.observation(
            from: start,
            to: end,
            segments: segments
        )

        XCTAssertEqual(observation.recordedSeconds, 15 * 60)
        XCTAssertEqual(observation.appSwitchCount, 2)
        XCTAssertEqual(observation.appUsageRunCount, 3)
        XCTAssertEqual(observation.categorySwitchCount, 0)
        XCTAssertEqual(observation.categoryTransitions, [])
        XCTAssertEqual(observation.apps.count, 3)
        XCTAssertEqual(
            observation.apps.first { $0.appName == "Orca" }?.durationSeconds,
            5 * 60
        )
    }

    @MainActor
    func testPomodoroSessionObservationCollapsesSameAppAcrossRecordingGaps() {
        let start = Date(timeIntervalSince1970: 1_800_640_000)
        let end = start.addingTimeInterval(20 * 60)
        let segments = [
            AppUsageSegment(
                appName: "Orca",
                bundleIdentifier: "com.stablyai.orca",
                category: "개발",
                startTime: start,
                endTime: start.addingTimeInterval(5 * 60)
            ),
            AppUsageSegment(
                appName: "Orca",
                bundleIdentifier: "com.stablyai.orca",
                category: "개발",
                startTime: start.addingTimeInterval(7 * 60),
                endTime: start.addingTimeInterval(11 * 60)
            ),
            AppUsageSegment(
                appName: "Orca",
                bundleIdentifier: "com.stablyai.orca",
                category: "개발",
                startTime: start.addingTimeInterval(15 * 60),
                endTime: start.addingTimeInterval(18 * 60)
            ),
        ]

        let observation = PomodoroSessionObservationBuilder.observation(
            from: start,
            to: end,
            segments: segments
        )

        XCTAssertEqual(observation.recordedSeconds, 12 * 60)
        XCTAssertEqual(observation.appSwitchCount, 0)
        XCTAssertEqual(observation.appUsageRunCount, 1)
        XCTAssertEqual(
            observation.averageAppUsageRunSeconds ?? -1,
            12 * 60,
            accuracy: 0.001
        )
        XCTAssertEqual(
            observation.longestContinuousAppUsage?.durationSeconds,
            5 * 60
        )
    }

    @MainActor
    func testPomodoroSessionObservationBridgesShortProductivityManagementInteraction() {
        let start = Date(timeIntervalSince1970: 1_800_645_000)
        let managementSeconds = Constants.productivityManagementShortInteractionSeconds - 1
        let secondAppStart = start.addingTimeInterval(5 * 60 + managementSeconds)
        let end = secondAppStart.addingTimeInterval(5 * 60)
        let segments = [
            AppUsageSegment(
                appName: "Orca",
                bundleIdentifier: "com.stablyai.orca",
                category: "개발",
                startTime: start,
                endTime: start.addingTimeInterval(5 * 60)
            ),
            AppUsageSegment(
                appName: "미리알림",
                bundleIdentifier: "com.apple.reminders",
                category: Constants.productivityManagementAppCategory,
                startTime: start.addingTimeInterval(5 * 60),
                endTime: secondAppStart
            ),
            AppUsageSegment(
                appName: "Orca",
                bundleIdentifier: "com.stablyai.orca",
                category: "개발",
                startTime: secondAppStart,
                endTime: end
            ),
        ]

        let observation = PomodoroSessionObservationBuilder.observation(
            from: start,
            to: end,
            segments: segments
        )

        XCTAssertEqual(observation.appSwitchCount, 0)
        XCTAssertEqual(observation.appUsageRunCount, 1)
        XCTAssertEqual(observation.distinctAppWebCount, 1)
        XCTAssertEqual(observation.shortProductivityManagementVisitCount, 1)
        XCTAssertEqual(observation.categorySwitchCount, 0)
        XCTAssertEqual(
            observation.averageAppUsageRunSeconds ?? -1,
            10 * 60 + managementSeconds,
            accuracy: 0.001
        )
        XCTAssertEqual(
            observation.apps.first { $0.appName == "미리알림" }?.durationSeconds,
            Int(managementSeconds)
        )
    }

    @MainActor
    func testPomodoroSessionObservationCountsLongProductivityManagementInteraction() {
        let start = Date(timeIntervalSince1970: 1_800_647_000)
        let managementSeconds = Constants.productivityManagementShortInteractionSeconds
        let secondAppStart = start.addingTimeInterval(5 * 60 + managementSeconds)
        let end = secondAppStart.addingTimeInterval(5 * 60)
        let segments = [
            AppUsageSegment(
                appName: "Orca",
                bundleIdentifier: "com.stablyai.orca",
                category: "개발",
                startTime: start,
                endTime: start.addingTimeInterval(5 * 60)
            ),
            AppUsageSegment(
                appName: "미리알림",
                bundleIdentifier: "com.apple.reminders",
                category: Constants.productivityManagementAppCategory,
                startTime: start.addingTimeInterval(5 * 60),
                endTime: secondAppStart
            ),
            AppUsageSegment(
                appName: "Orca",
                bundleIdentifier: "com.stablyai.orca",
                category: "개발",
                startTime: secondAppStart,
                endTime: end
            ),
        ]

        let observation = PomodoroSessionObservationBuilder.observation(
            from: start,
            to: end,
            segments: segments
        )

        XCTAssertEqual(observation.appSwitchCount, 2)
        XCTAssertEqual(observation.appUsageRunCount, 3)
        XCTAssertEqual(observation.distinctAppWebCount, 2)
        XCTAssertEqual(observation.shortProductivityManagementVisitCount, 0)
        XCTAssertEqual(observation.categorySwitchCount, 0)
        XCTAssertEqual(
            observation.averageAppUsageRunSeconds ?? -1,
            (10 * 60 + managementSeconds) / 3,
            accuracy: 0.001
        )
    }

    @MainActor
    func testPomodoroSessionObservationCountsAppChangeAcrossMinimumSegmentGap() {
        let start = Date(timeIntervalSince1970: 1_800_650_000)
        let end = start.addingTimeInterval(25 * 60)
        let segments = [
            AppUsageSegment(
                appName: "Xcode",
                bundleIdentifier: "com.apple.dt.Xcode",
                category: "개발",
                startTime: start,
                endTime: start.addingTimeInterval(5 * 60)
            ),
            AppUsageSegment(
                appName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                category: "조사",
                startTime: start.addingTimeInterval(
                    5 * 60 + AppTracker.minimumSegmentSeconds
                ),
                endTime: start.addingTimeInterval(
                    10 * 60 + AppTracker.minimumSegmentSeconds
                )
            ),
        ]

        let observation = PomodoroSessionObservationBuilder.observation(
            from: start,
            to: end,
            segments: segments
        )

        XCTAssertEqual(AppTracker.minimumSegmentSeconds, 5)
        XCTAssertEqual(observation.appSwitchCount, 1)
        XCTAssertEqual(observation.categorySwitchCount, 0)
        XCTAssertEqual(observation.categoryTransitions, [])
    }

    func testAppTrackerPersistsShortTailOnlyForExistingSegment() {
        XCTAssertTrue(
            AppTracker.shouldPersistSegment(
                elapsed: AppTracker.minimumSegmentSeconds - 1,
                hasPreviousSegment: true
            )
        )
        XCTAssertFalse(
            AppTracker.shouldPersistSegment(
                elapsed: AppTracker.minimumSegmentSeconds - 1,
                hasPreviousSegment: false
            )
        )
        XCTAssertTrue(
            AppTracker.shouldPersistSegment(
                elapsed: AppTracker.minimumSegmentSeconds,
                hasPreviousSegment: false
            )
        )
        XCTAssertFalse(
            AppTracker.shouldPersistSegment(elapsed: -1, hasPreviousSegment: true)
        )
    }

    func testAppTrackerSplitsIdleDurationAcrossCalendarDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 60 * 60)!
        let firstDay = calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 23)
        )!
        let start = calendar.date(
            from: DateComponents(
                year: 2026,
                month: 7,
                day: 23,
                hour: 23,
                minute: 55
            )
        )!
        let end = calendar.date(
            from: DateComponents(
                year: 2026,
                month: 7,
                day: 24,
                hour: 0,
                minute: 10
            )
        )!

        XCTAssertEqual(
            AppTracker.dailyDurationSlices(
                from: start,
                to: end,
                calendar: calendar
            ),
            [
                AppTracker.DailyDurationSlice(
                    date: firstDay,
                    durationSeconds: 5 * 60
                ),
                AppTracker.DailyDurationSlice(
                    date: calendar.date(byAdding: .day, value: 1, to: firstDay)!,
                    durationSeconds: 10 * 60
                ),
            ]
        )
    }

    func testAppTrackerKeepsSameDayIdleDurationInOneSlice() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 60 * 60)!
        let start = calendar.date(
            from: DateComponents(
                year: 2026,
                month: 7,
                day: 23,
                hour: 12
            )
        )!
        let end = start.addingTimeInterval(15 * 60)

        XCTAssertEqual(
            AppTracker.dailyDurationSlices(
                from: start,
                to: end,
                calendar: calendar
            ),
            [
                AppTracker.DailyDurationSlice(
                    date: calendar.startOfDay(for: start),
                    durationSeconds: 15 * 60
                ),
            ]
        )
    }

    func testHorongHorongIsRegisteredAsDefaultProductivityManagementApp() {
        let rule = Constants.defaultCategoryRule(
            for: Constants.horongHorongBundleIdentifier,
            includingHidden: true
        )

        XCTAssertEqual(rule?.appName, "호롱호롱")
        XCTAssertEqual(rule?.category, Constants.productivityManagementAppCategory)
        XCTAssertEqual(
            Constants.categoryEmoji(for: Constants.productivityManagementAppCategory),
            "⏰"
        )
        XCTAssertTrue(
            Constants.reservedCategoryNames.contains(
                Constants.productivityManagementAppCategory
            )
        )
    }

    func testRemindersIsRegisteredAsDefaultProductivityManagementApp() {
        let rule = Constants.defaultCategoryRule(
            for: "com.apple.reminders",
            includingHidden: true
        )

        XCTAssertEqual(rule?.appName, "미리알림")
        XCTAssertEqual(rule?.category, Constants.productivityManagementAppCategory)
    }

    func testContextDependentAppsAreNotDefaultCategoryRules() {
        let bundleIdentifiers = [
            "com.apple.Preview",
            "com.apple.iBooksX",
            "com.google.Chrome",
            "org.mozilla.firefox",
            "com.apple.Safari",
        ]

        for bundleIdentifier in bundleIdentifiers {
            XCTAssertNil(
                Constants.defaultCategoryRule(
                    for: bundleIdentifier,
                    includingHidden: true
                )
            )
        }
    }

    @MainActor
    func testDefaultRuleReconciliationRemovesOnlyRetiredDefaults() throws {
        let schema = Schema([AppCategoryRule.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let retiredDefault = AppCategoryRule(
            bundleIdentifier: "com.apple.Safari",
            appName: "Safari",
            category: "공부"
        )
        let userRule = AppCategoryRule(
            bundleIdentifier: "com.apple.iBooksX",
            appName: "Books",
            category: "공부",
            isUserDefined: true
        )
        context.insert(retiredDefault)
        context.insert(userRule)

        try DefaultAppCategoryRuleStore.reconcile(in: context)

        let rules = try context.fetch(FetchDescriptor<AppCategoryRule>())
        XCTAssertFalse(
            rules.contains {
                $0.bundleIdentifier == retiredDefault.bundleIdentifier
                    && !$0.isUserDefined
            }
        )
        XCTAssertTrue(
            rules.contains {
                $0.bundleIdentifier == userRule.bundleIdentifier
                    && $0.isUserDefined
                    && $0.category == "공부"
            }
        )
    }

    @MainActor
    func testLegacySupportCategoryMigratesToProductivityManagement() throws {
        let schema = Schema([
            AppCategoryRule.self,
            AppUsageSegment.self,
            AppUsageRecord.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let start = Date(timeIntervalSince1970: 1_800_665_000)
        let rule = AppCategoryRule(
            bundleIdentifier: Constants.horongHorongBundleIdentifier,
            appName: "호롱호롱",
            category: Constants.legacySupportAppCategory
        )
        let segment = AppUsageSegment(
            appName: "호롱호롱",
            bundleIdentifier: Constants.horongHorongBundleIdentifier,
            category: Constants.legacySupportAppCategory,
            startTime: start,
            endTime: start.addingTimeInterval(30)
        )
        let record = AppUsageRecord(
            appName: "호롱호롱",
            bundleIdentifier: Constants.horongHorongBundleIdentifier,
            category: Constants.legacySupportAppCategory,
            date: start
        )
        context.insert(rule)
        context.insert(segment)
        context.insert(record)
        try context.save()

        CategoryManager.shared.loadUserRules(from: SwiftDataAppUsageRepository(context: context))

        XCTAssertEqual(rule.category, Constants.productivityManagementAppCategory)
        XCTAssertEqual(segment.category, Constants.productivityManagementAppCategory)
        XCTAssertEqual(record.category, Constants.productivityManagementAppCategory)
    }

    @MainActor
    func testProductivityManagementAppSessionClassificationOnlyChangesOverlappingRange() throws {
        let schema = Schema([AppUsageSegment.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let sessionStart = Date(timeIntervalSince1970: 1_800_670_000)
        let sessionEnd = sessionStart.addingTimeInterval(10 * 60)
        context.insert(AppUsageSegment(
            appName: "미리알림",
            bundleIdentifier: "com.apple.reminders",
            category: Constants.productivityManagementAppCategory,
            startTime: sessionStart.addingTimeInterval(-2 * 60),
            endTime: sessionEnd.addingTimeInterval(2 * 60)
        ))
        try context.save()

        XCTAssertEqual(
            AppClassificationService.productivityManagementAppUsages(
                from: sessionStart,
                to: sessionEnd,
                modelContext: context
            ).first?.durationSeconds,
            10 * 60
        )

        try AppClassificationService.prepareProductivityManagementAppSessionClassification(
            bundleIdentifier: "com.apple.reminders",
            from: sessionStart,
            to: sessionEnd,
            category: "개발",
            modelContext: context
        )
        try context.save()

        let segments = try context.fetch(
            FetchDescriptor<AppUsageSegment>(
                sortBy: [SortDescriptor(\.startTime)]
            )
        )
        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments.map(\.category), [
            Constants.productivityManagementAppCategory,
            "개발",
            Constants.productivityManagementAppCategory,
        ])
        XCTAssertEqual(segments[0].startTime, sessionStart.addingTimeInterval(-2 * 60))
        XCTAssertEqual(segments[0].endTime, sessionStart)
        XCTAssertEqual(segments[1].startTime, sessionStart)
        XCTAssertEqual(segments[1].endTime, sessionEnd)
        XCTAssertTrue(segments[1].isUserModified)
        XCTAssertEqual(segments[2].startTime, sessionEnd)
        XCTAssertEqual(segments[2].endTime, sessionEnd.addingTimeInterval(2 * 60))
    }

    @MainActor
    func testProductivityManagementUsageGroupsMultipleAppsForReflection() throws {
        let schema = Schema([AppUsageSegment.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let sessionStart = Date(timeIntervalSince1970: 1_800_672_000)
        let sessionEnd = sessionStart.addingTimeInterval(10 * 60)
        context.insert(AppUsageSegment(
            appName: "호롱호롱",
            bundleIdentifier: Constants.horongHorongBundleIdentifier,
            category: Constants.productivityManagementAppCategory,
            startTime: sessionStart,
            endTime: sessionStart.addingTimeInterval(70)
        ))
        context.insert(AppUsageSegment(
            appName: "미리알림",
            bundleIdentifier: "com.apple.reminders",
            category: Constants.productivityManagementAppCategory,
            startTime: sessionStart.addingTimeInterval(2 * 60),
            endTime: sessionStart.addingTimeInterval(4 * 60)
        ))
        context.insert(AppUsageSegment(
            appName: "짧은 확인",
            bundleIdentifier: "com.example.short-check",
            category: Constants.productivityManagementAppCategory,
            startTime: sessionStart.addingTimeInterval(5 * 60),
            endTime: sessionStart.addingTimeInterval(5 * 60 + 59)
        ))
        try context.save()

        let usages = AppClassificationService.productivityManagementAppUsages(
            from: sessionStart,
            to: sessionEnd,
            modelContext: context
        )

        XCTAssertEqual(usages.map(\.appName), ["미리알림", "호롱호롱"])
        XCTAssertEqual(usages.map(\.durationSeconds), [120, 70])
    }

    @MainActor
    func testClassifyingDiscoveredAppUpdatesRuleAndPastUnclassifiedUsage() throws {
        let schema = Schema([
            AppCategoryRule.self,
            AppUsageSegment.self,
            AppUsageRecord.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let bundleIdentifier = "test.unclassified.classify"
        let start = Date(timeIntervalSince1970: 1_800_675_000)
        let segment = AppUsageSegment(
            appName: "새 IDE",
            bundleIdentifier: bundleIdentifier,
            category: Constants.unclassifiedAppCategory,
            startTime: start,
            endTime: start.addingTimeInterval(20 * 60)
        )
        let record = AppUsageRecord(
            appName: "새 IDE",
            bundleIdentifier: bundleIdentifier,
            category: Constants.unclassifiedAppCategory,
            date: start
        )
        record.durationSeconds = 20 * 60
        context.insert(segment)
        context.insert(record)
        try context.save()

        XCTAssertEqual(
            AppClassificationService.unclassifiedApps(
                from: start,
                to: start.addingTimeInterval(20 * 60),
                modelContext: context
            ),
            [
                UnclassifiedAppUsage(
                    bundleIdentifier: bundleIdentifier,
                    appName: "새 IDE",
                    durationSeconds: 20 * 60
                )
            ]
        )

        try AppClassificationService.classify(
            bundleIdentifier: bundleIdentifier,
            appName: "새 IDE",
            category: "개발",
            modelContext: context
        )

        let rules = try context.fetch(FetchDescriptor<AppCategoryRule>())
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?.bundleIdentifier, bundleIdentifier)
        XCTAssertEqual(rules.first?.category, "개발")
        XCTAssertEqual(rules.first?.isExcluded, false)
        XCTAssertEqual(segment.category, "개발")
        XCTAssertEqual(record.category, "개발")
        XCTAssertEqual(
            CategoryManager.shared.trackingClassification(for: bundleIdentifier),
            .category("개발")
        )
    }

    @MainActor
    func testDailyUsageRecordsStaySeparatedByCategory() throws {
        let schema = Schema([AppUsageRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let date = Date(timeIntervalSince1970: 1_800_677_000)
        let bundleIdentifier = "test.category-separated"

        try AppUsageRecordStore.applyDelta(
            bundleIdentifier: bundleIdentifier,
            appName: "분리 테스트",
            category: "개발",
            date: date,
            deltaSeconds: 10 * 60,
            modelContext: context
        )
        try AppUsageRecordStore.applyDelta(
            bundleIdentifier: bundleIdentifier,
            appName: "분리 테스트",
            category: "공부",
            date: date,
            deltaSeconds: 5 * 60,
            modelContext: context
        )
        try AppUsageRecordStore.applyDelta(
            bundleIdentifier: bundleIdentifier,
            appName: "분리 테스트",
            category: "개발",
            date: date,
            deltaSeconds: 2 * 60,
            modelContext: context
        )
        try context.save()

        let records = try context.fetch(FetchDescriptor<AppUsageRecord>())
        let durations = Dictionary(
            uniqueKeysWithValues: records.map { ($0.category, $0.durationSeconds) }
        )
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(durations["개발"], 12 * 60)
        XCTAssertEqual(durations["공부"], 5 * 60)
    }

    @MainActor
    func testReclassifyingExistingUsageProtectsUserModifiedSegmentsAndRebuildsDailyRecords() throws {
        let schema = Schema([AppUsageSegment.self, AppUsageRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let day = Calendar.current.startOfDay(
            for: Date(timeIntervalSince1970: 1_800_678_000)
        )
        let start = day.addingTimeInterval(9 * 60 * 60)
        let bundleIdentifier = "test.history-reclassification"
        let automatic = AppUsageSegment(
            appName: "기록 테스트",
            bundleIdentifier: bundleIdentifier,
            category: "개발",
            startTime: start,
            endTime: start.addingTimeInterval(10 * 60)
        )
        let userModified = AppUsageSegment(
            appName: "기록 테스트",
            bundleIdentifier: bundleIdentifier,
            category: "개발",
            startTime: start.addingTimeInterval(10 * 60),
            endTime: start.addingTimeInterval(15 * 60),
            isUserModified: true
        )
        let mixedRecord = AppUsageRecord(
            appName: "기록 테스트",
            bundleIdentifier: bundleIdentifier,
            category: "개발",
            date: day
        )
        mixedRecord.durationSeconds = 15 * 60
        context.insert(automatic)
        context.insert(userModified)
        context.insert(mixedRecord)
        try context.save()

        let changedCount = try AppClassificationService.reclassifyExistingUsage(
            ruleBundleIdentifier: bundleIdentifier,
            category: "공부",
            modelContext: context
        )

        XCTAssertEqual(changedCount, 1)
        XCTAssertEqual(automatic.category, "공부")
        XCTAssertEqual(userModified.category, "개발")
        let records = try context.fetch(FetchDescriptor<AppUsageRecord>())
        let durations = Dictionary(
            uniqueKeysWithValues: records.map { ($0.category, $0.durationSeconds) }
        )
        XCTAssertEqual(durations["공부"], 10 * 60)
        XCTAssertEqual(durations["개발"], 5 * 60)
    }

    @MainActor
    func testWebsiteHistoryReclassificationAppliesAcrossBrowsersOnlyForMatchingDomain() throws {
        let schema = Schema([AppUsageSegment.self, AppUsageRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let day = Calendar.current.startOfDay(
            for: Date(timeIntervalSince1970: 1_800_679_000)
        )
        let start = day.addingTimeInterval(10 * 60 * 60)
        let chromeBundle = "com.google.Chrome.website.youtube.com"
        let safariBundle = "com.apple.Safari.website.youtu.be"
        let legacyBundle = "com.brave.Browser.youtube"
        let unrelatedBundle = "com.apple.Safari.website.claude.ai"
        let segments = [
            AppUsageSegment(
                appName: "Chrome (youtube.com)",
                bundleIdentifier: chromeBundle,
                category: "엔터",
                startTime: start,
                endTime: start.addingTimeInterval(5 * 60)
            ),
            AppUsageSegment(
                appName: "Safari (youtu.be)",
                bundleIdentifier: safariBundle,
                category: "엔터",
                startTime: start.addingTimeInterval(5 * 60),
                endTime: start.addingTimeInterval(10 * 60)
            ),
            AppUsageSegment(
                appName: "Brave Browser (YouTube)",
                bundleIdentifier: legacyBundle,
                category: "엔터",
                startTime: start.addingTimeInterval(10 * 60),
                endTime: start.addingTimeInterval(15 * 60)
            ),
            AppUsageSegment(
                appName: "Safari (claude.ai)",
                bundleIdentifier: unrelatedBundle,
                category: "개발",
                startTime: start.addingTimeInterval(15 * 60),
                endTime: start.addingTimeInterval(20 * 60)
            ),
        ]
        for segment in segments {
            context.insert(segment)
            let record = AppUsageRecord(
                appName: segment.appName,
                bundleIdentifier: segment.bundleIdentifier,
                category: segment.category,
                date: day
            )
            record.durationSeconds = segment.durationSeconds
            context.insert(record)
        }
        try context.save()

        let changedCount = try AppClassificationService.reclassifyExistingUsage(
            ruleBundleIdentifier: WebsiteCategoryRule.bundleIdentifier(
                for: "youtube.com"
            ),
            category: "공부",
            modelContext: context
        )

        XCTAssertEqual(changedCount, 3)
        XCTAssertEqual(segments[0].category, "공부")
        XCTAssertEqual(segments[1].category, "공부")
        XCTAssertEqual(segments[2].category, "공부")
        XCTAssertEqual(segments[3].category, "개발")
        let records = try context.fetch(FetchDescriptor<AppUsageRecord>())
        XCTAssertTrue(records.contains {
            $0.bundleIdentifier == chromeBundle && $0.category == "공부"
        })
        XCTAssertTrue(records.contains {
            $0.bundleIdentifier == safariBundle && $0.category == "공부"
        })
        XCTAssertTrue(records.contains {
            $0.bundleIdentifier == legacyBundle && $0.category == "공부"
        })
        XCTAssertTrue(records.contains {
            $0.bundleIdentifier == unrelatedBundle && $0.category == "개발"
        })
    }

    @MainActor
    func testExcludingDiscoveredAppKeepsHistoryAndPersistsFutureExclusion() throws {
        let schema = Schema([
            AppCategoryRule.self,
            AppUsageSegment.self,
            AppUsageRecord.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let bundleIdentifier = "test.unclassified.exclude"
        let start = Date(timeIntervalSince1970: 1_800_680_000)
        context.insert(AppUsageSegment(
            appName: "민감 앱",
            bundleIdentifier: bundleIdentifier,
            category: Constants.unclassifiedAppCategory,
            startTime: start,
            endTime: start.addingTimeInterval(5 * 60)
        ))
        let record = AppUsageRecord(
            appName: "민감 앱",
            bundleIdentifier: bundleIdentifier,
            category: Constants.unclassifiedAppCategory,
            date: start
        )
        record.durationSeconds = 5 * 60
        context.insert(record)
        try context.save()

        try AppClassificationService.exclude(
            bundleIdentifier: bundleIdentifier,
            appName: "민감 앱",
            modelContext: context
        )

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AppUsageSegment>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AppUsageRecord>()), 1)
        XCTAssertTrue(
            AppClassificationService.allUnclassifiedApps(modelContext: context).isEmpty
        )
        let rule = try XCTUnwrap(
            context.fetch(FetchDescriptor<AppCategoryRule>()).first
        )
        XCTAssertTrue(rule.isExcluded)
        XCTAssertEqual(
            CategoryManager.shared.trackingClassification(for: bundleIdentifier),
            .excluded
        )
    }

    @MainActor
    func testPomodoroSessionObservationTreatsDecoratedBrowserNamesAsOneApp() {
        let start = Date(timeIntervalSince1970: 1_800_700_000)
        let end = start.addingTimeInterval(25 * 60)
        let segments = [
            AppUsageSegment(
                appName: "Google Chrome (GitHub)",
                bundleIdentifier: "com.google.Chrome.research.github",
                category: "조사",
                startTime: start,
                endTime: start.addingTimeInterval(5 * 60)
            ),
            AppUsageSegment(
                appName: "Google Chrome (YouTube)",
                bundleIdentifier: "com.google.Chrome.youtube",
                category: "엔터",
                startTime: start.addingTimeInterval(5 * 60),
                endTime: start.addingTimeInterval(10 * 60)
            ),
        ]

        let observation = PomodoroSessionObservationBuilder.observation(
            from: start,
            to: end,
            segments: segments
        )

        XCTAssertEqual(observation.appSwitchCount, 0)
        XCTAssertEqual(observation.appUsageRunCount, 1)
        XCTAssertEqual(observation.categorySwitchCount, 1)
        XCTAssertEqual(
            observation.apps,
            [
                PomodoroAppUsageEntry(appName: "Google Chrome", category: "엔터", durationSeconds: 5 * 60),
                PomodoroAppUsageEntry(appName: "Google Chrome", category: "조사", durationSeconds: 5 * 60),
            ]
        )
    }

    @MainActor
    func testPomodoroSessionObservationDistinguishesRegisteredWebsitesAcrossBrowsers() {
        let start = Date(timeIntervalSince1970: 1_800_710_000)
        let end = start.addingTimeInterval(15 * 60)
        let segments = [
            AppUsageSegment(
                appName: "Google Chrome (chatgpt.com)",
                bundleIdentifier: "com.google.Chrome.website.chatgpt.com",
                category: "개발",
                startTime: start,
                endTime: start.addingTimeInterval(5 * 60)
            ),
            AppUsageSegment(
                appName: "Safari (chatgpt.com)",
                bundleIdentifier: "com.apple.Safari.website.chatgpt.com",
                category: "개발",
                startTime: start.addingTimeInterval(5 * 60),
                endTime: start.addingTimeInterval(10 * 60)
            ),
            AppUsageSegment(
                appName: "Safari (youtube.com)",
                bundleIdentifier: "com.apple.Safari.website.youtube.com",
                category: "엔터",
                startTime: start.addingTimeInterval(10 * 60),
                endTime: end
            ),
        ]

        let observation = PomodoroSessionObservationBuilder.observation(
            from: start,
            to: end,
            segments: segments
        )

        XCTAssertEqual(observation.appSwitchCount, 1)
        XCTAssertEqual(observation.appUsageRunCount, 2)
        XCTAssertEqual(observation.distinctAppWebCount, 2)
        XCTAssertEqual(observation.categorySwitchCount, 1)
        XCTAssertEqual(
            observation.apps,
            [
                PomodoroAppUsageEntry(
                    appName: "chatgpt.com",
                    category: "개발",
                    durationSeconds: 10 * 60
                ),
                PomodoroAppUsageEntry(
                    appName: "youtube.com",
                    category: "엔터",
                    durationSeconds: 5 * 60
                ),
            ]
        )
    }

    @MainActor
    func testPomodoroSessionObservationCountsWebsiteChangeWithinSameCategory() {
        let start = Date(timeIntervalSince1970: 1_800_720_000)
        let end = start.addingTimeInterval(10 * 60)
        let segments = [
            AppUsageSegment(
                appName: "Google Chrome (chatgpt.com)",
                bundleIdentifier: "com.google.Chrome.website.chatgpt.com",
                category: "개발",
                startTime: start,
                endTime: start.addingTimeInterval(5 * 60)
            ),
            AppUsageSegment(
                appName: "Google Chrome (claude.ai)",
                bundleIdentifier: "com.google.Chrome.website.claude.ai",
                category: "개발",
                startTime: start.addingTimeInterval(5 * 60),
                endTime: end
            ),
        ]

        let observation = PomodoroSessionObservationBuilder.observation(
            from: start,
            to: end,
            segments: segments
        )

        XCTAssertEqual(observation.appSwitchCount, 1)
        XCTAssertEqual(observation.appUsageRunCount, 2)
        XCTAssertEqual(observation.distinctAppWebCount, 2)
        XCTAssertEqual(observation.categorySwitchCount, 0)
    }

    @MainActor
    func testPomodoroSessionObservationAllocatesFractionalSecondsWithoutInventingGap() {
        let start = Date(timeIntervalSince1970: 1_800_800_000)
        let end = start.addingTimeInterval(3)
        let segments = [
            AppUsageSegment(
                appName: "A",
                bundleIdentifier: "test.a",
                category: "개발",
                startTime: start,
                endTime: start.addingTimeInterval(1.5),
                isManual: true
            ),
            AppUsageSegment(
                appName: "B",
                bundleIdentifier: "test.b",
                category: "조사",
                startTime: start.addingTimeInterval(1.5),
                endTime: end,
                isManual: true
            ),
        ]

        let observation = PomodoroSessionObservationBuilder.observation(
            from: start,
            to: end,
            segments: segments
        )

        XCTAssertEqual(observation.recordedSeconds, 3)
        XCTAssertEqual(observation.unrecordedSeconds, 0)
        XCTAssertEqual(observation.apps.reduce(0) { $0 + $1.durationSeconds }, 3)
        XCTAssertEqual(observation.categories.reduce(0) { $0 + $1.durationSeconds }, 3)
        XCTAssertEqual(observation.userModifiedRecordedSeconds, 3)
    }

    func testPomodoroPatternReadModelKeepsUnlinkedSessionsInGeneralOnly() throws {
        let memoID = UUID()
        let start = Date(timeIntervalSince1970: 1_801_000_000)
        let linkedSession = PomodoroSessionBreakdown(
            id: UUID(),
            startedAt: start,
            endedAt: start.addingTimeInterval(1_500),
            category: "개발",
            linkedMemoID: memoID,
            taskTitle: "개인 패턴 집계",
            durationSeconds: 1_500,
            observation: PomodoroSessionObservation(
                sessionSeconds: 1_500,
                recordedSeconds: 1_200,
                unrecordedSeconds: 300,
                ambiguousOverlapSeconds: 0,
                userModifiedRecordedSeconds: 0,
                appSwitchCount: 3,
                appUsageRunCount: 4,
                categorySwitchCount: 1,
                categoryTransitions: [],
                longestContinuousAppUsage: PomodoroContinuousAppUsage(
                    appName: "Xcode",
                    category: "개발",
                    durationSeconds: 720
                ),
                apps: [],
                categories: []
            )
        )
        let unlinkedSession = PomodoroSessionBreakdown(
            id: UUID(),
            startedAt: start.addingTimeInterval(1_800),
            endedAt: start.addingTimeInterval(2_700),
            category: "개발",
            linkedMemoID: nil,
            taskTitle: nil,
            durationSeconds: 900,
            observation: PomodoroSessionObservation(
                sessionSeconds: 900,
                recordedSeconds: 600,
                unrecordedSeconds: 300,
                ambiguousOverlapSeconds: 0,
                userModifiedRecordedSeconds: 0,
                appSwitchCount: 2,
                appUsageRunCount: 3,
                categorySwitchCount: 0,
                categoryTransitions: [],
                longestContinuousAppUsage: PomodoroContinuousAppUsage(
                    appName: "Safari",
                    category: "개발",
                    durationSeconds: 300
                ),
                apps: [],
                categories: []
            )
        )

        let model = PomodoroPatternReadModelBuilder.build(
            sessions: [linkedSession, unlinkedSession],
            reflections: [
                PomodoroReflection(
                    focusSessionID: linkedSession.id,
                    focusExperience: .deeplyFocused,
                    progressResult: .meaningfulProgress,
                    incompleteReason: .underestimatedScope
                ),
                PomodoroReflection(
                    focusSessionID: unlinkedSession.id,
                    focusExperience: .mostlyFocused,
                    progressResult: .completedAsPlanned
                ),
            ]
        )

        XCTAssertEqual(model.general.sessionCount, 2)
        XCTAssertEqual(model.general.linkedSessionCount, 1)
        XCTAssertEqual(model.general.unlinkedSessionCount, 1)
        XCTAssertEqual(model.general.durationSeconds, 2_400)
        XCTAssertEqual(model.general.appSwitchCount, 5)
        XCTAssertEqual(model.general.categorySwitchCount, 1)
        XCTAssertEqual(model.general.reflectionCount, 2)

        let category = try XCTUnwrap(model.categoryGroups.first)
        XCTAssertEqual(category.title, "개발")
        XCTAssertEqual(category.metrics.sessionCount, 2)
        XCTAssertEqual(category.metrics.reflectionCount, 2)

        XCTAssertEqual(model.taskGroups.count, 1)
        let task = try XCTUnwrap(model.taskGroups.first)
        XCTAssertEqual(task.linkedMemoID, memoID)
        XCTAssertEqual(task.title, "개인 패턴 집계")
        XCTAssertEqual(task.metrics.sessionCount, 1)
        XCTAssertEqual(task.metrics.appSwitchCount, 3)
        XCTAssertEqual(task.metrics.reflectionCount, 1)
        XCTAssertEqual(
            task.metrics.incompleteReasonCounts,
            [
                PomodoroReflectionOptionCount(
                    id: PomodoroIncompleteReason.underestimatedScope.rawValue,
                    label: PomodoroIncompleteReason.underestimatedScope.label,
                    count: 1
                )
            ]
        )
    }

    func testPomodoroPatternReadModelSeparatesMissingRecordsAndOrphanReflections() throws {
        let memoID = UUID()
        let start = Date(timeIntervalSince1970: 1_801_100_000)
        let recordedSession = PomodoroSessionBreakdown(
            id: UUID(),
            startedAt: start,
            endedAt: start.addingTimeInterval(1_500),
            category: "조사",
            linkedMemoID: memoID,
            taskTitle: "자료 조사",
            durationSeconds: 1_500,
            observation: PomodoroSessionObservation(
                sessionSeconds: 1_500,
                recordedSeconds: 1_500,
                unrecordedSeconds: 0,
                ambiguousOverlapSeconds: 0,
                userModifiedRecordedSeconds: 0,
                appSwitchCount: 0,
                appUsageRunCount: 1,
                categorySwitchCount: 0,
                categoryTransitions: [],
                longestContinuousAppUsage: PomodoroContinuousAppUsage(
                    appName: "Safari",
                    category: "조사",
                    durationSeconds: 1_500
                ),
                apps: [],
                categories: []
            )
        )
        let missingRecordSession = PomodoroSessionBreakdown(
            id: UUID(),
            startedAt: start.addingTimeInterval(1_800),
            endedAt: start.addingTimeInterval(3_300),
            category: "조사",
            linkedMemoID: memoID,
            taskTitle: "자료 조사 완료",
            durationSeconds: 1_500,
            observation: PomodoroSessionObservation(
                sessionSeconds: 1_500,
                recordedSeconds: 0,
                unrecordedSeconds: 1_500,
                ambiguousOverlapSeconds: 0,
                userModifiedRecordedSeconds: 0,
                appSwitchCount: 0,
                appUsageRunCount: 0,
                categorySwitchCount: 0,
                categoryTransitions: [],
                longestContinuousAppUsage: nil,
                apps: [],
                categories: []
            )
        )
        let matchingReflection = PomodoroReflection(
            focusSessionID: recordedSession.id,
            focusExperience: .deeplyFocused,
            progressResult: .completedAsPlanned
        )
        let orphanReflection = PomodoroReflection(
            focusSessionID: UUID(),
            focusExperience: .difficultToFocus,
            progressResult: .littleProgress,
            incompleteReason: .distracted
        )
        let completion = PomodoroTaskCompletion(
            focusSessionID: recordedSession.id,
            linkedMemoID: memoID,
            taskTitleSnapshot: "자료 조사",
            completedAt: start.addingTimeInterval(1_500),
            didMarkMemoCompleted: true,
            memoWasPinnedBeforeCompletion: false
        )

        let model = PomodoroPatternReadModelBuilder.build(
            sessions: [recordedSession, missingRecordSession],
            reflections: [matchingReflection, orphanReflection],
            completions: [completion]
        )

        XCTAssertEqual(model.general.sessionCount, 2)
        XCTAssertEqual(model.general.sessionsWithAppRecords, 1)
        XCTAssertEqual(model.general.recordedSeconds, 1_500)
        XCTAssertEqual(model.general.unrecordedSeconds, 1_500)
        XCTAssertEqual(model.general.reflectionCount, 1)
        XCTAssertEqual(model.general.longestContinuousAppUsage?.durationSeconds, 1_500)
        XCTAssertEqual(
            model.general.progressResultCounts,
            [
                PomodoroReflectionOptionCount(
                    id: "linked_task_completed",
                    label: "이 할 일을 모두 끝냈어요",
                    count: 1
                )
            ]
        )

        let task = try XCTUnwrap(model.taskGroups.first)
        XCTAssertEqual(task.title, "자료 조사 완료")
        XCTAssertEqual(task.metrics.sessionsWithAppRecords, 1)
        XCTAssertEqual(task.metrics.reflectionCount, 1)
    }

    func testPomodoroFocusComparisonUsesAttributedTimeAndGroupMedians() throws {
        let start = Date(timeIntervalSince1970: 1_801_200_000)

        func session(
            offset: TimeInterval,
            recordedSeconds: Int,
            ambiguousSeconds: Int,
            appSwitchCount: Int,
            categorySwitchCount: Int,
            longestSeconds: Int?
        ) -> PomodoroSessionBreakdown {
            let id = UUID()
            let startedAt = start.addingTimeInterval(offset)
            return PomodoroSessionBreakdown(
                id: id,
                startedAt: startedAt,
                endedAt: startedAt.addingTimeInterval(1_200),
                category: "개발",
                linkedMemoID: nil,
                taskTitle: nil,
                durationSeconds: 1_200,
                observation: PomodoroSessionObservation(
                    sessionSeconds: 1_200,
                    recordedSeconds: recordedSeconds,
                    unrecordedSeconds: max(0, 1_200 - recordedSeconds),
                    ambiguousOverlapSeconds: ambiguousSeconds,
                    userModifiedRecordedSeconds: 0,
                    appSwitchCount: appSwitchCount,
                    appUsageRunCount: recordedSeconds > ambiguousSeconds
                        ? appSwitchCount + 1
                        : 0,
                    categorySwitchCount: categorySwitchCount,
                    categoryTransitions: [],
                    longestContinuousAppUsage: longestSeconds.map {
                        PomodoroContinuousAppUsage(
                            appName: "Xcode",
                            category: "개발",
                            durationSeconds: $0
                        )
                    },
                    apps: [],
                    categories: []
                )
            )
        }

        let deeplyFocused = session(
            offset: 0,
            recordedSeconds: 1_200,
            ambiguousSeconds: 60,
            appSwitchCount: 2,
            categorySwitchCount: 1,
            longestSeconds: 570
        )
        let mostlyFocused = session(
            offset: 1_500,
            recordedSeconds: 960,
            ambiguousSeconds: 0,
            appSwitchCount: 0,
            categorySwitchCount: 0,
            longestSeconds: 960
        )
        let unavailableFocused = session(
            offset: 3_000,
            recordedSeconds: 600,
            ambiguousSeconds: 600,
            appSwitchCount: 0,
            categorySwitchCount: 0,
            longestSeconds: nil
        )
        let lowCoverageFocused = session(
            offset: 3_600,
            recordedSeconds: 120,
            ambiguousSeconds: 0,
            appSwitchCount: 0,
            categorySwitchCount: 0,
            longestSeconds: 120
        )
        let highAmbiguityFocused = session(
            offset: 4_050,
            recordedSeconds: 1_200,
            ambiguousSeconds: 180,
            appSwitchCount: 1,
            categorySwitchCount: 1,
            longestSeconds: 500
        )
        let frequentlyDistracted = session(
            offset: 4_500,
            recordedSeconds: 960,
            ambiguousSeconds: 0,
            appSwitchCount: 6,
            categorySwitchCount: 2,
            longestSeconds: 192
        )
        let difficultToFocus = session(
            offset: 6_000,
            recordedSeconds: 1_200,
            ambiguousSeconds: 0,
            appSwitchCount: 8,
            categorySwitchCount: 4,
            longestSeconds: 240
        )
        let unsure = session(
            offset: 7_500,
            recordedSeconds: 960,
            ambiguousSeconds: 0,
            appSwitchCount: 3,
            categorySwitchCount: 1,
            longestSeconds: 480
        )
        let sessions = [
            deeplyFocused,
            mostlyFocused,
            unavailableFocused,
            lowCoverageFocused,
            highAmbiguityFocused,
            frequentlyDistracted,
            difficultToFocus,
            unsure,
        ]
        let reflections = [
            PomodoroReflection(
                focusSessionID: deeplyFocused.id,
                focusExperience: .deeplyFocused,
                progressResult: .meaningfulProgress
            ),
            PomodoroReflection(
                focusSessionID: mostlyFocused.id,
                focusExperience: .mostlyFocused,
                progressResult: .completedAsPlanned
            ),
            PomodoroReflection(
                focusSessionID: unavailableFocused.id,
                focusExperience: .deeplyFocused,
                progressResult: .littleProgress,
                incompleteReason: .distracted
            ),
            PomodoroReflection(
                focusSessionID: lowCoverageFocused.id,
                focusExperience: .mostlyFocused,
                progressResult: .littleProgress,
                incompleteReason: .distracted
            ),
            PomodoroReflection(
                focusSessionID: highAmbiguityFocused.id,
                focusExperience: .deeplyFocused,
                progressResult: .meaningfulProgress
            ),
            PomodoroReflection(
                focusSessionID: frequentlyDistracted.id,
                focusExperience: .frequentlyDistracted,
                progressResult: .littleProgress,
                incompleteReason: .distracted
            ),
            PomodoroReflection(
                focusSessionID: difficultToFocus.id,
                focusExperience: .difficultToFocus,
                progressResult: .meaningfulProgress,
                incompleteReason: .blocked
            ),
            PomodoroReflection(
                focusSessionID: unsure.id,
                focusExperience: .unsure,
                progressResult: .goalChanged,
                incompleteReason: .switchedTask
            ),
        ]

        let model = PomodoroFocusComparisonBuilder.build(
            sessions: sessions,
            reflections: reflections
        )

        XCTAssertEqual(model.scopedSessionCount, 8)
        XCTAssertEqual(model.matchedReflectionCount, 8)
        XCTAssertEqual(model.focused.reflectionSessionCount, 5)
        XCTAssertEqual(model.focused.comparableSessionCount, 2)
        XCTAssertEqual(model.focused.missingBehaviorRecordSessionCount, 0)
        XCTAssertEqual(model.focused.qualityExcludedSessionCount, 3)
        XCTAssertEqual(model.focused.sessionsWithAmbiguousRecords, 1)
        XCTAssertEqual(
            try XCTUnwrap(model.focused.medianAppSwitchesPerAttributedTenMinutes),
            0.5263157895,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try XCTUnwrap(model.focused.medianCategorySwitchesPerAttributedTenMinutes),
            0.2631578947,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try XCTUnwrap(model.focused.medianLongestContinuousAppCategoryRatio),
            0.75,
            accuracy: 0.0001
        )
        XCTAssertEqual(model.difficult.reflectionSessionCount, 2)
        XCTAssertEqual(
            try XCTUnwrap(model.difficult.medianAppSwitchesPerAttributedTenMinutes),
            3.875,
            accuracy: 0.0001
        )
        XCTAssertEqual(model.unsure.reflectionSessionCount, 1)
        XCTAssertEqual(model.unknownReflectionCount, 0)
    }

    func testPomodoroFocusComparisonScopesCategoryAndLinkedTaskIndependently() throws {
        let memoA = UUID()
        let memoB = UUID()
        let start = Date(timeIntervalSince1970: 1_801_300_000)

        func session(
            offset: TimeInterval,
            category: String,
            memoID: UUID?,
            title: String?
        ) -> PomodoroSessionBreakdown {
            let id = UUID()
            let startedAt = start.addingTimeInterval(offset)
            return PomodoroSessionBreakdown(
                id: id,
                startedAt: startedAt,
                endedAt: startedAt.addingTimeInterval(600),
                category: category,
                linkedMemoID: memoID,
                taskTitle: title,
                durationSeconds: 600,
                observation: PomodoroSessionObservation(
                    sessionSeconds: 600,
                    recordedSeconds: 600,
                    unrecordedSeconds: 0,
                    ambiguousOverlapSeconds: 0,
                    userModifiedRecordedSeconds: 0,
                    appSwitchCount: 1,
                    appUsageRunCount: 2,
                    categorySwitchCount: 0,
                    categoryTransitions: [],
                    longestContinuousAppUsage: PomodoroContinuousAppUsage(
                        appName: "Xcode",
                        category: category,
                        durationSeconds: 500
                    ),
                    apps: [],
                    categories: []
                )
            )
        }

        let developmentMemoA = session(
            offset: 0,
            category: "개발",
            memoID: memoA,
            title: "비교 화면"
        )
        let unlinkedDevelopment = session(
            offset: 900,
            category: "개발",
            memoID: nil,
            title: nil
        )
        let writingMemoA = session(
            offset: 1_800,
            category: "글쓰기",
            memoID: memoA,
            title: "비교 화면 문서"
        )
        let developmentMemoB = session(
            offset: 2_700,
            category: "개발",
            memoID: memoB,
            title: "필터 테스트"
        )
        let unknownResponse = session(
            offset: 3_600,
            category: "개발",
            memoID: nil,
            title: nil
        )
        let sessions = [
            developmentMemoA,
            unlinkedDevelopment,
            writingMemoA,
            developmentMemoB,
            unknownResponse,
        ]
        let reflections = sessions.map {
            PomodoroReflection(
                focusSessionID: $0.id,
                focusExperience: .mostlyFocused,
                progressResult: .meaningfulProgress
            )
        }
        reflections.last?.focusExperienceRawValue = "legacy_unknown"
        let orphan = PomodoroReflection(
            focusSessionID: UUID(),
            focusExperience: .difficultToFocus,
            progressResult: .littleProgress,
            incompleteReason: .distracted
        )

        let categoryModel = PomodoroFocusComparisonBuilder.build(
            sessions: sessions,
            reflections: reflections + [orphan],
            category: "개발"
        )
        XCTAssertEqual(categoryModel.scopedSessionCount, 4)
        XCTAssertEqual(categoryModel.matchedReflectionCount, 4)
        XCTAssertEqual(categoryModel.focused.reflectionSessionCount, 3)
        XCTAssertEqual(categoryModel.unknownReflectionCount, 1)

        let taskModel = PomodoroFocusComparisonBuilder.build(
            sessions: sessions,
            reflections: reflections,
            category: "개발",
            linkedMemoID: memoA
        )
        XCTAssertEqual(taskModel.scopedSessionCount, 1)
        XCTAssertEqual(taskModel.focused.reflectionSessionCount, 1)

        XCTAssertEqual(
            PomodoroFocusComparisonBuilder.taskOptions(
                sessions: sessions,
                category: "개발"
            ),
            [
                PomodoroFocusComparisonTaskOption(
                    id: memoA,
                    title: "비교 화면",
                    firstStartedAt: developmentMemoA.startedAt
                ),
                PomodoroFocusComparisonTaskOption(
                    id: memoB,
                    title: "필터 테스트",
                    firstStartedAt: developmentMemoB.startedAt
                ),
            ]
        )
    }

    func testLinkedTaskComparisonSeparatesReflectionsFromAllBehaviorSessions() throws {
        let memoA = UUID()
        let memoB = UUID()
        let memoC = UUID()
        let start = Date(timeIntervalSince1970: 1_801_350_000)

        func session(
            offset: TimeInterval,
            category: String = "개발",
            memoID: UUID?,
            title: String?,
            recordedSeconds: Int,
            ambiguousSeconds: Int = 0,
            appSwitchCount: Int = 0,
            categorySwitchCount: Int = 0,
            longestSeconds: Int? = nil
        ) -> PomodoroSessionBreakdown {
            let startedAt = start.addingTimeInterval(offset)
            return PomodoroSessionBreakdown(
                id: UUID(),
                startedAt: startedAt,
                endedAt: startedAt.addingTimeInterval(600),
                category: category,
                linkedMemoID: memoID,
                taskTitle: title,
                durationSeconds: 600,
                observation: PomodoroSessionObservation(
                    sessionSeconds: 600,
                    recordedSeconds: recordedSeconds,
                    unrecordedSeconds: max(0, 600 - recordedSeconds),
                    ambiguousOverlapSeconds: ambiguousSeconds,
                    userModifiedRecordedSeconds: 0,
                    appSwitchCount: appSwitchCount,
                    appUsageRunCount: recordedSeconds > ambiguousSeconds
                        ? appSwitchCount + 1
                        : 0,
                    categorySwitchCount: categorySwitchCount,
                    categoryTransitions: [],
                    longestContinuousAppUsage: longestSeconds.map {
                        PomodoroContinuousAppUsage(
                            appName: "Xcode",
                            category: category,
                            durationSeconds: $0
                        )
                    },
                    apps: [],
                    categories: []
                )
            )
        }

        let aFocused = session(
            offset: 0,
            memoID: memoA,
            title: "이전 제목",
            recordedSeconds: 600,
            appSwitchCount: 1,
            longestSeconds: 400
        )
        let aUnanswered = session(
            offset: 900,
            memoID: memoA,
            title: nil,
            recordedSeconds: 600,
            appSwitchCount: 3,
            categorySwitchCount: 1,
            longestSeconds: 300
        )
        let aMissing = session(
            offset: 1_800,
            memoID: memoA,
            title: "  ",
            recordedSeconds: 0
        )
        let aLowQuality = session(
            offset: 2_700,
            memoID: memoA,
            title: "새 제목",
            recordedSeconds: 120,
            longestSeconds: 120
        )
        let bUnsure = session(
            offset: 3_600,
            memoID: memoB,
            title: "문서 정리",
            recordedSeconds: 0
        )
        let bUnknown = session(
            offset: 4_500,
            memoID: memoB,
            title: nil,
            recordedSeconds: 0
        )
        let cUnanswered = session(
            offset: 5_100,
            memoID: memoC,
            title: "테스트 보강",
            recordedSeconds: 600,
            appSwitchCount: 5,
            categorySwitchCount: 2,
            longestSeconds: 240
        )
        let sameMemoOtherCategory = session(
            offset: 5_400,
            category: "글쓰기",
            memoID: memoA,
            title: "다른 카테고리",
            recordedSeconds: 600,
            appSwitchCount: 9,
            longestSeconds: 100
        )
        let unlinked = session(
            offset: 6_300,
            memoID: nil,
            title: nil,
            recordedSeconds: 600,
            longestSeconds: 600
        )
        let unknownReflection = PomodoroReflection(
            focusSessionID: bUnknown.id,
            focusExperience: .unsure,
            progressResult: .meaningfulProgress
        )
        unknownReflection.focusExperienceRawValue = "legacy_unknown"
        let reflections = [
            PomodoroReflection(
                focusSessionID: aFocused.id,
                focusExperience: .deeplyFocused,
                progressResult: .meaningfulProgress
            ),
            PomodoroReflection(
                focusSessionID: aMissing.id,
                focusExperience: .difficultToFocus,
                progressResult: .littleProgress,
                incompleteReason: .blocked
            ),
            PomodoroReflection(
                focusSessionID: bUnsure.id,
                focusExperience: .unsure,
                progressResult: .goalChanged,
                incompleteReason: .switchedTask
            ),
            unknownReflection,
            PomodoroReflection(
                focusSessionID: sameMemoOtherCategory.id,
                focusExperience: .deeplyFocused,
                progressResult: .completedAsPlanned
            ),
        ]

        let model = PomodoroLinkedTaskComparisonBuilder.build(
            sessions: [
                aFocused,
                aUnanswered,
                aMissing,
                aLowQuality,
                bUnsure,
                bUnknown,
                cUnanswered,
                sameMemoOtherCategory,
                unlinked,
            ],
            reflections: reflections,
            category: "개발"
        )

        XCTAssertEqual(model.category, "개발")
        XCTAssertEqual(model.items.map(\.id), [memoA, memoB, memoC])
        let taskA = try XCTUnwrap(model.items.first)
        XCTAssertEqual(taskA.title, "새 제목")
        XCTAssertEqual(taskA.totalSessionCount, 4)
        XCTAssertEqual(taskA.totalDurationSeconds, 2_400)
        XCTAssertEqual(taskA.behavior.comparableSessionCount, 2)
        XCTAssertEqual(taskA.behavior.missingBehaviorRecordSessionCount, 1)
        XCTAssertEqual(taskA.behavior.qualityExcludedSessionCount, 1)
        XCTAssertEqual(
            taskA.totalSessionCount,
            taskA.behavior.comparableSessionCount
                + taskA.behavior.missingBehaviorRecordSessionCount
                + taskA.behavior.qualityExcludedSessionCount
        )
        XCTAssertEqual(
            try XCTUnwrap(taskA.behavior.medianAppSwitchesPerAttributedTenMinutes),
            2,
            accuracy: 0.0001
        )
        XCTAssertEqual(taskA.reflections.answeredCount, 2)
        XCTAssertEqual(taskA.reflections.unansweredCount, 2)
        XCTAssertEqual(taskA.reflections.focusedCount, 1)
        XCTAssertEqual(taskA.reflections.difficultCount, 1)

        let taskB = try XCTUnwrap(model.items.first { $0.id == memoB })
        XCTAssertEqual(taskB.totalSessionCount, 2)
        XCTAssertEqual(taskB.behavior.comparableSessionCount, 0)
        XCTAssertEqual(taskB.behavior.missingBehaviorRecordSessionCount, 2)
        XCTAssertNil(taskB.behavior.medianAppSwitchesPerAttributedTenMinutes)
        XCTAssertEqual(taskB.reflections.answeredCount, 2)
        XCTAssertEqual(taskB.reflections.unsureCount, 1)
        XCTAssertEqual(taskB.reflections.unknownCount, 1)

        let taskC = try XCTUnwrap(model.items.first { $0.id == memoC })
        XCTAssertEqual(taskC.behavior.comparableSessionCount, 1)
        XCTAssertEqual(taskC.reflections.answeredCount, 0)
        XCTAssertEqual(taskC.reflections.unansweredCount, 1)
        XCTAssertEqual(model.appSwitchDomainMaximum, 5, accuracy: 0.0001)
        XCTAssertEqual(model.categorySwitchDomainMaximum, 2, accuracy: 0.0001)
    }

    func testPomodoroComparisonSegmentScopeIncludesEverySession() {
        let linked = FocusSession(
            focusMinutes: 25,
            breakMinutes: 5,
            category: "개발",
            linkedMemoID: UUID(),
            taskTitleSnapshot: "비교 화면"
        )
        let reflectedUnlinked = FocusSession(
            focusMinutes: 25,
            breakMinutes: 5,
            category: "개발"
        )
        let unrelated = FocusSession(
            focusMinutes: 25,
            breakMinutes: 5,
            category: "개발"
        )
        XCTAssertEqual(
            PomodoroComparisonSegmentScope.includedSessionIDs(
                sessions: [linked, reflectedUnlinked, unrelated]
            ),
            Set([linked.id, reflectedUnlinked.id, unrelated.id])
        )
    }

    func testBehaviorConditionEvaluatorUsesVisibleValuesAndInclusiveThresholds() {
        let observation = PomodoroSessionObservation(
            sessionSeconds: 600,
            recordedSeconds: 576,
            unrecordedSeconds: 24,
            ambiguousOverlapSeconds: 0,
            userModifiedRecordedSeconds: 0,
            appSwitchCount: 1,
            appUsageRunCount: 2,
            categorySwitchCount: 1,
            categoryTransitions: [],
            longestContinuousAppUsage: PomodoroContinuousAppUsage(
                appName: "Xcode",
                category: "개발",
                durationSeconds: 484
            ),
            apps: [],
            categories: []
        )
        let allConditions = PomodoroBehaviorConditions(
            maximumAppSwitchesPerAttributedTenMinutes: 1,
            maximumCategorySwitchesPerAttributedTenMinutes: 1,
            minimumLongestContinuousAppCategoryRatio: 0.84
        )

        XCTAssertEqual(
            PomodoroBehaviorConditionEvaluator.evaluate(
                observation: observation,
                conditions: allConditions
            ),
            .evaluated(matchedConditionCount: 3, totalConditionCount: 3)
        )

        let twoConditions = PomodoroBehaviorConditions(
            maximumAppSwitchesPerAttributedTenMinutes: 0.9,
            minimumLongestContinuousAppCategoryRatio: 0.85
        )
        XCTAssertEqual(
            PomodoroBehaviorConditionEvaluator.evaluate(
                observation: observation,
                conditions: twoConditions
            ),
            .evaluated(matchedConditionCount: 0, totalConditionCount: 2)
        )
        XCTAssertEqual(
            PomodoroBehaviorConditionEvaluator.evaluate(
                observation: observation,
                conditions: PomodoroBehaviorConditions()
            ),
            .noConditions
        )
    }

    func testBehaviorConditionDraftRequiresExplicitValidValues() throws {
        var draft = PomodoroBehaviorConditionDraft()
        XCTAssertNil(draft.conditions)

        draft.usesMaximumAppSwitches = true
        XCTAssertNil(draft.conditions)
        draft.maximumAppSwitchesText = "1,5"
        draft.usesMinimumLongestContinuousRatio = true
        draft.minimumLongestContinuousPercentText = "60"

        let conditions = try XCTUnwrap(draft.conditions)
        XCTAssertEqual(conditions.maximumAppSwitchesPerAttributedTenMinutes, 1.5)
        XCTAssertNil(conditions.maximumCategorySwitchesPerAttributedTenMinutes)
        XCTAssertEqual(conditions.minimumLongestContinuousAppCategoryRatio, 0.6)

        draft.minimumLongestContinuousPercentText = "101"
        XCTAssertNil(draft.conditions)
    }

    func testBehaviorConditionDraftNormalizesToDisplayedPrecision() throws {
        var draft = PomodoroBehaviorConditionDraft()
        draft.usesMaximumAppSwitches = true
        draft.maximumAppSwitchesText = "1.06"
        draft.usesMaximumCategorySwitches = true
        draft.maximumCategorySwitchesText = "2.04"
        draft.usesMinimumLongestContinuousRatio = true
        draft.minimumLongestContinuousPercentText = "55.5"

        let conditions = try XCTUnwrap(draft.conditions)
        XCTAssertEqual(
            try XCTUnwrap(conditions.maximumAppSwitchesPerAttributedTenMinutes),
            1.1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try XCTUnwrap(conditions.maximumCategorySwitchesPerAttributedTenMinutes),
            2.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try XCTUnwrap(conditions.minimumLongestContinuousAppCategoryRatio),
            0.56,
            accuracy: 0.0001
        )
    }

    func testBehaviorConditionEvaluatorUsesInclusiveQualityBoundaries() {
        func observation(recordedSeconds: Int, ambiguousSeconds: Int) -> PomodoroSessionObservation {
            let attributedSeconds = max(0, recordedSeconds - ambiguousSeconds)
            return PomodoroSessionObservation(
                sessionSeconds: 600,
                recordedSeconds: recordedSeconds,
                unrecordedSeconds: max(0, 600 - recordedSeconds),
                ambiguousOverlapSeconds: ambiguousSeconds,
                userModifiedRecordedSeconds: 0,
                appSwitchCount: 1,
                appUsageRunCount: attributedSeconds > 0 ? 2 : 0,
                categorySwitchCount: 0,
                categoryTransitions: [],
                longestContinuousAppUsage: attributedSeconds > 0
                    ? PomodoroContinuousAppUsage(
                        appName: "Xcode",
                        category: "개발",
                        durationSeconds: attributedSeconds
                    )
                    : nil,
                apps: [],
                categories: []
            )
        }
        let conditions = PomodoroBehaviorConditions(
            maximumAppSwitchesPerAttributedTenMinutes: 10
        )

        XCTAssertEqual(
            PomodoroBehaviorConditionEvaluator.evaluate(
                observation: observation(recordedSeconds: 480, ambiguousSeconds: 60),
                conditions: conditions
            ),
            .evaluated(matchedConditionCount: 1, totalConditionCount: 1)
        )
        XCTAssertEqual(
            PomodoroBehaviorConditionEvaluator.evaluate(
                observation: observation(recordedSeconds: 479, ambiguousSeconds: 0),
                conditions: conditions
            ),
            .calculationHeld(.qualityExcluded)
        )
        XCTAssertEqual(
            PomodoroBehaviorConditionEvaluator.evaluate(
                observation: observation(recordedSeconds: 600, ambiguousSeconds: 61),
                conditions: conditions
            ),
            .calculationHeld(.qualityExcluded)
        )
        XCTAssertEqual(
            PomodoroBehaviorConditionEvaluator.evaluate(
                observation: observation(recordedSeconds: 0, ambiguousSeconds: 0),
                conditions: conditions
            ),
            .calculationHeld(.missingBehaviorRecord)
        )
    }

    func testBehaviorConditionPreviewScopesCategoryAndIncludesUnreflectedSessions() {
        let start = Date(timeIntervalSince1970: 1_801_375_000)
        func session(
            id: UUID = UUID(),
            category: String,
            appSwitchCount: Int,
            recordedSeconds: Int = 600
        ) -> PomodoroSessionBreakdown {
            PomodoroSessionBreakdown(
                id: id,
                startedAt: start,
                endedAt: start.addingTimeInterval(600),
                category: category,
                linkedMemoID: nil,
                taskTitle: nil,
                durationSeconds: 600,
                observation: PomodoroSessionObservation(
                    sessionSeconds: 600,
                    recordedSeconds: recordedSeconds,
                    unrecordedSeconds: max(0, 600 - recordedSeconds),
                    ambiguousOverlapSeconds: 0,
                    userModifiedRecordedSeconds: 0,
                    appSwitchCount: appSwitchCount,
                    appUsageRunCount: recordedSeconds > 0 ? appSwitchCount + 1 : 0,
                    categorySwitchCount: 0,
                    categoryTransitions: [],
                    longestContinuousAppUsage: recordedSeconds > 0
                        ? PomodoroContinuousAppUsage(
                            appName: "Xcode",
                            category: category,
                            durationSeconds: recordedSeconds
                        )
                        : nil,
                    apps: [],
                    categories: []
                )
            )
        }
        let conditions = PomodoroBehaviorConditions(
            maximumAppSwitchesPerAttributedTenMinutes: 1
        )
        let preview = PomodoroBehaviorConditionEvaluator.preview(
            sessions: [
                session(category: "개발", appSwitchCount: 0),
                session(category: "개발", appSwitchCount: 2),
                session(category: "개발", appSwitchCount: 0, recordedSeconds: 0),
                session(category: "글쓰기", appSwitchCount: 0),
            ],
            category: "개발",
            conditions: conditions
        )

        XCTAssertEqual(preview.totalSessionCount, 3)
        XCTAssertEqual(preview.evaluatedSessionCount, 2)
        XCTAssertEqual(preview.missingBehaviorRecordSessionCount, 1)
        XCTAssertEqual(preview.qualityExcludedSessionCount, 0)
        XCTAssertEqual(preview.matchCounts, [0: 1, 1: 1])
    }

    @MainActor
    func testCategoryBehaviorConditionSetPersistsUpdatesAndDeletes() throws {
        let schema = Schema([CategoryBehaviorConditionSet.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        try CategoryBehaviorConditionSetStore.upsert(
            category: " 개발 ",
            maximumAppSwitchesPerAttributedTenMinutes: 2,
            maximumCategorySwitchesPerAttributedTenMinutes: nil,
            minimumLongestContinuousAppCategoryRatio: 0.6,
            modelContext: context
        )
        var saved = try context.fetch(FetchDescriptor<CategoryBehaviorConditionSet>())
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.category, "개발")
        XCTAssertEqual(saved.first?.conditionCount, 2)

        try CategoryBehaviorConditionSetStore.upsert(
            category: "개발",
            maximumAppSwitchesPerAttributedTenMinutes: 1.56,
            maximumCategorySwitchesPerAttributedTenMinutes: 0.54,
            minimumLongestContinuousAppCategoryRatio: nil,
            modelContext: context
        )
        saved = try context.fetch(FetchDescriptor<CategoryBehaviorConditionSet>())
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.maximumAppSwitchesPerAttributedTenMinutes, 1.6)
        XCTAssertEqual(saved.first?.maximumCategorySwitchesPerAttributedTenMinutes, 0.5)
        XCTAssertNil(saved.first?.minimumLongestContinuousAppCategoryRatio)

        try CategoryBehaviorConditionSetStore.upsert(
            category: "개발",
            maximumAppSwitchesPerAttributedTenMinutes: nil,
            maximumCategorySwitchesPerAttributedTenMinutes: nil,
            minimumLongestContinuousAppCategoryRatio: nil,
            modelContext: context
        )
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<CategoryBehaviorConditionSet>()).isEmpty
        )
    }

    @MainActor
    func testCategoryBehaviorConditionSetMovesOnRenameAndDeletesWithoutReplacingFallback() throws {
        let schema = Schema([CategoryBehaviorConditionSet.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        context.insert(CategoryBehaviorConditionSet(
            category: "개발",
            maximumAppSwitchesPerAttributedTenMinutes: 2
        ))
        context.insert(CategoryBehaviorConditionSet(
            category: "기타",
            minimumLongestContinuousAppCategoryRatio: 0.5
        ))
        try context.save()

        try CategoryBehaviorConditionSetStore.prepareCategoryRename(
            from: "개발",
            to: "프로그래밍",
            modelContext: context
        )
        try context.save()
        var saved = try context.fetch(FetchDescriptor<CategoryBehaviorConditionSet>())
        XCTAssertEqual(Set(saved.map(\.category)), Set(["프로그래밍", "기타"]))

        try CategoryBehaviorConditionSetStore.prepareCategoryDeletion(
            category: "프로그래밍",
            modelContext: context
        )
        try context.save()
        saved = try context.fetch(FetchDescriptor<CategoryBehaviorConditionSet>())
        XCTAssertEqual(saved.map(\.category), ["기타"])
        XCTAssertEqual(saved.first?.minimumLongestContinuousAppCategoryRatio, 0.5)
    }

    @MainActor
    func testCategoryBehaviorConditionSetRenameReplacesOrphanedTargetWithSource() throws {
        let schema = Schema([CategoryBehaviorConditionSet.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        context.insert(CategoryBehaviorConditionSet(
            category: "개발",
            maximumAppSwitchesPerAttributedTenMinutes: 2
        ))
        context.insert(CategoryBehaviorConditionSet(
            category: "프로그래밍",
            minimumLongestContinuousAppCategoryRatio: 0.5
        ))
        try context.save()

        try CategoryBehaviorConditionSetStore.prepareCategoryRename(
            from: "개발",
            to: "프로그래밍",
            modelContext: context
        )
        try context.save()

        let saved = try context.fetch(FetchDescriptor<CategoryBehaviorConditionSet>())
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.category, "프로그래밍")
        XCTAssertEqual(saved.first?.maximumAppSwitchesPerAttributedTenMinutes, 2)
        XCTAssertNil(saved.first?.minimumLongestContinuousAppCategoryRatio)
    }

    @MainActor
    func testPomodoroComparisonPeriodUsesStartMembershipAndFullSessionInterval() throws {
        let periodStart = Date(timeIntervalSince1970: 1_801_400_000)
        let periodEnd = periodStart.addingTimeInterval(3_600)

        func completedSession(startedAt: Date, focusMinutes: Int = 10) -> FocusSession {
            let session = FocusSession(
                focusMinutes: focusMinutes,
                breakMinutes: 5,
                category: "개발"
            )
            session.startedAt = startedAt
            session.endedAt = startedAt.addingTimeInterval(TimeInterval(focusMinutes * 60))
            session.completed = true
            return session
        }

        let overlappingFromPreviousPeriod = completedSession(
            startedAt: periodStart.addingTimeInterval(-300)
        )
        let startsAtPeriodBoundary = completedSession(startedAt: periodStart)
        startsAtPeriodBoundary.inputActiveSeconds = 300
        startsAtPeriodBoundary.markerColorKey = "purple"
        let crossesPeriodEnd = completedSession(
            startedAt: periodEnd.addingTimeInterval(-300)
        )
        let startsAtNextPeriod = completedSession(startedAt: periodEnd)

        let segments = [
            AppUsageSegment(
                appName: "Xcode",
                bundleIdentifier: "com.apple.dt.Xcode",
                category: "개발",
                startTime: periodStart,
                endTime: periodStart.addingTimeInterval(600)
            ),
            AppUsageSegment(
                appName: "Terminal",
                bundleIdentifier: "com.apple.Terminal",
                category: "개발",
                startTime: periodEnd.addingTimeInterval(-300),
                endTime: periodEnd.addingTimeInterval(300)
            ),
        ]

        let result = PomodoroComparisonPeriodBuilder.build(
            sessions: [
                overlappingFromPreviousPeriod,
                startsAtPeriodBoundary,
                crossesPeriodEnd,
                startsAtNextPeriod,
            ],
            segments: segments,
            periodStart: periodStart,
            periodEnd: periodEnd
        )

        XCTAssertEqual(result.map(\.id), [startsAtPeriodBoundary.id, crossesPeriodEnd.id])
        let first = try XCTUnwrap(result.first)
        let last = try XCTUnwrap(result.last)
        XCTAssertEqual(first.observation.sessionSeconds, 600)
        XCTAssertEqual(first.observation.recordedSeconds, 600)
        XCTAssertEqual(first.inputActivityRatio, 0.5)
        XCTAssertEqual(first.markerColorKey, "purple")
        XCTAssertEqual(last.endedAt, periodEnd.addingTimeInterval(300))
        XCTAssertEqual(last.observation.sessionSeconds, 600)
        XCTAssertEqual(last.observation.recordedSeconds, 600)
    }

    @MainActor
    func testPomodoroComparisonPeriodPreservesEarlyEndStatusAndPlannedDuration() throws {
        let periodStart = Date(timeIntervalSince1970: 1_801_500_000)
        let session = FocusSession(
            focusMinutes: 50,
            breakMinutes: 10,
            category: "개발"
        )
        session.startedAt = periodStart.addingTimeInterval(60)
        session.endedAt = session.startedAt.addingTimeInterval(1_200)
        session.actualFocusSeconds = 1_200
        session.completed = true
        session.endKind = .recordedEarly
        let reflectionDeferredAt = session.endedAt?.addingTimeInterval(5)
        session.reflectionDeferredAt = reflectionDeferredAt

        let result = PomodoroComparisonPeriodBuilder.build(
            sessions: [session],
            segments: [],
            periodStart: periodStart,
            periodEnd: periodStart.addingTimeInterval(3_600)
        )

        let breakdown = try XCTUnwrap(result.first)
        XCTAssertEqual(breakdown.durationSeconds, 1_200)
        XCTAssertEqual(breakdown.plannedDurationSeconds, 3_000)
        XCTAssertEqual(breakdown.endKind, .recordedEarly)
        XCTAssertEqual(breakdown.reflectionDeferredAt, reflectionDeferredAt)
    }

    @MainActor
    func testAppUsageSegmentTracksUserModifiedProvenance() {
        let start = Date(timeIntervalSince1970: 1_800_900_000)
        let automatic = AppUsageSegment(
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            category: "개발",
            startTime: start,
            endTime: start.addingTimeInterval(60)
        )
        let manual = AppUsageSegment(
            appName: "직접 입력",
            bundleIdentifier: "manual.직접-입력",
            category: "기록",
            startTime: start,
            endTime: start.addingTimeInterval(60),
            isManual: true
        )

        XCTAssertFalse(automatic.isUserModified)
        XCTAssertTrue(manual.isUserModified)
    }

    @MainActor
    func testAppUsageSegmentSchemaMigrationDefaultsLegacyProvenanceToFalse() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let storeURL = directory.appendingPathComponent("segment-migration.store")
        let segmentID = try makeLegacyAppUsageSegmentStore(at: storeURL)

        let updatedSchema = Schema([AppUsageSegment.self])
        let updatedConfiguration = ModelConfiguration(schema: updatedSchema, url: storeURL)
        let updatedContainer = try ModelContainer(
            for: updatedSchema,
            configurations: [updatedConfiguration]
        )

        let segments = try updatedContainer.mainContext.fetch(
            FetchDescriptor<AppUsageSegment>()
        )
        XCTAssertEqual(segments.map(\.id), [segmentID])
        XCTAssertFalse(try XCTUnwrap(segments.first).isUserModified)
    }

    @MainActor
    func testPomodoroSchemaMigrationKeepsLegacyFocusSessions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let storeURL = directory.appendingPathComponent("migration.store")
        let sessionID = try makeLegacyFocusSessionStore(at: storeURL)

        let updatedSchema = Schema([
            FocusSession.self,
            PomodoroReflection.self,
            CategoryBehaviorConditionSet.self,
            PomodoroTaskCompletion.self,
        ])
        let updatedConfiguration = ModelConfiguration(schema: updatedSchema, url: storeURL)
        let updatedContainer = try ModelContainer(
            for: updatedSchema,
            configurations: [updatedConfiguration]
        )

        let sessions = try updatedContainer.mainContext.fetch(FetchDescriptor<FocusSession>())
        XCTAssertEqual(sessions.map(\.id), [sessionID])
        XCTAssertNil(sessions.first?.linkedMemoID)
        XCTAssertNil(sessions.first?.taskTitleSnapshot)
        XCTAssertNil(sessions.first?.reflectionDeferredAt)
        XCTAssertNil(sessions.first?.pauseIntervalsData)
        XCTAssertNil(sessions.first?.pauseStartedAt)
        XCTAssertTrue(
            try updatedContainer.mainContext.fetch(
                FetchDescriptor<PomodoroTaskCompletion>()
            ).isEmpty
        )
        XCTAssertTrue(
            try updatedContainer.mainContext.fetch(
                FetchDescriptor<CategoryBehaviorConditionSet>()
            ).isEmpty
        )
    }

    func testDefaultCategoryDefinitionsDoNotIncludeRemovedDocumentCategory() {
        let defaultNames = Constants.defaultCategoryDefinitions.map(\.defaultName)

        XCTAssertFalse(defaultNames.contains("문서"))
        XCTAssertTrue(defaultNames.contains("기록"))
        XCTAssertTrue(defaultNames.contains("조사"))
        XCTAssertTrue(defaultNames.contains("기타"))
    }

    func testDefaultCategoryColorsAreOneToOne() {
        let colorKeys = Constants.defaultCategoryDefinitions.compactMap(\.colorKey)

        XCTAssertEqual(colorKeys.count, Constants.defaultCategoryDefinitions.count)
        XCTAssertEqual(Set(colorKeys).count, colorKeys.count)
        XCTAssertEqual(
            Dictionary(
                uniqueKeysWithValues: Constants.defaultCategoryDefinitions.map {
                    ($0.defaultName, $0.colorKey)
                }
            ),
            Constants.defaultCategoryColorKeys.mapValues(Optional.some)
        )
    }

    func testNewCategoriesReceiveUniqueColorsAfterPaletteIsExhausted() throws {
        let (userDefaults, suiteName) = try makeIsolatedUserDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let store = CategoryStore(userDefaults: userDefaults)
        let newCategoryCount = CategoryColorPalette.options.count + 5

        for index in 0..<newCategoryCount {
            XCTAssertTrue(store.add(name: "사용자 \(index)", emoji: "🧩"))
        }

        let colorKeys = store.categories.compactMap(\.colorKey)
        XCTAssertEqual(colorKeys.count, store.categories.count)
        XCTAssertEqual(Set(colorKeys).count, colorKeys.count)
        XCTAssertNotEqual(store.colorKey(for: "사용자 0"), CategoryColorPalette.fallbackKey)
        XCTAssertTrue(colorKeys.contains(where: CategoryColorPalette.isGenerated))
    }

    func testCategoryColorSurvivesRenameAndSwapsWithoutDuplicates() throws {
        let (userDefaults, suiteName) = try makeIsolatedUserDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let store = CategoryStore(userDefaults: userDefaults)
        XCTAssertTrue(store.add(name: "기획", emoji: "🗺️"))
        XCTAssertTrue(store.add(name: "리뷰", emoji: "🧪"))
        let planningColor = store.colorKey(for: "기획")
        let reviewColor = store.colorKey(for: "리뷰")

        XCTAssertTrue(store.setColorKey(reviewColor, for: "기획"))
        XCTAssertEqual(store.colorKey(for: "기획"), reviewColor)
        XCTAssertEqual(store.colorKey(for: "리뷰"), planningColor)
        XCTAssertTrue(store.update(oldName: "기획", newName: "설계", emoji: "🗺️"))
        XCTAssertEqual(store.colorKey(for: "설계"), reviewColor)

        let reloaded = CategoryStore(userDefaults: userDefaults)
        let reloadedColorKeys = reloaded.categories.compactMap(\.colorKey)
        XCTAssertEqual(reloaded.colorKey(for: "설계"), reviewColor)
        XCTAssertEqual(reloaded.colorKey(for: "리뷰"), planningColor)
        XCTAssertEqual(Set(reloadedColorKeys).count, reloadedColorKeys.count)
    }

    func testLegacyCategoriesWithoutColorsAreAssignedUniquePersistentColors() throws {
        let (userDefaults, suiteName) = try makeIsolatedUserDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        var legacyCategories = Constants.defaultCategoryDefinitions
        for index in legacyCategories.indices {
            legacyCategories[index].colorKey = nil
        }
        legacyCategories.append(
            CategoryDefinition(
                defaultName: "사용자",
                name: "사용자",
                emoji: "🧩",
                colorKey: nil
            )
        )
        userDefaults.set(
            try JSONEncoder().encode(legacyCategories),
            forKey: "categories.v1"
        )

        let migrated = CategoryStore(userDefaults: userDefaults)
        let migratedColorKeys = migrated.categories.compactMap(\.colorKey)
        XCTAssertEqual(migratedColorKeys.count, migrated.categories.count)
        XCTAssertEqual(Set(migratedColorKeys).count, migratedColorKeys.count)
        XCTAssertEqual(migrated.colorKey(for: "업무"), "brown")
        XCTAssertNotEqual(migrated.colorKey(for: "사용자"), CategoryColorPalette.fallbackKey)

        let reloaded = CategoryStore(userDefaults: userDefaults)
        XCTAssertEqual(
            reloaded.categories.map(\.colorKey),
            migrated.categories.map(\.colorKey)
        )
    }

    func testAgentDerivedDirectoriesUseSingleRoot() {
        let root = "/tmp/HorongHorongTests/experiments"

        XCTAssertEqual(Constants.agentIdeaDirectoryPath(for: root), "/tmp/HorongHorongTests/experiments/ideas")
        XCTAssertEqual(Constants.agentOutputDirectoryPath(for: root), "/tmp/HorongHorongTests/experiments/outputs")
        XCTAssertEqual(Constants.agentIdeaDirectoryPath(for: "   "), "")
        XCTAssertEqual(Constants.agentOutputDirectoryPath(for: ""), "")
    }

    func testDefaultInterestKeywordsStartEmpty() {
        XCTAssertEqual(Constants.defaultInterestKeywords, "")
        XCTAssertEqual(Constants.defaultNewsInterestKeywords, "")
    }

    func testRepresentativeAgentTypesNormalizeToSupportedUniqueValues() {
        XCTAssertEqual(
            Constants.normalizedRepresentativeAgentTypes(from: "Codex,Claude,Antigravity,Unknown,Codex"),
            ["Codex", "Claude", "Antigravity"]
        )
        XCTAssertEqual(
            Constants.normalizedRepresentativeAgentTypes(from: "Antigravity,Opencode"),
            ["Antigravity", "Opencode"]
        )
        XCTAssertEqual(
            Constants.normalizedRepresentativeAgentTypes(from: ""),
            Constants.defaultRepresentativeAgentTypes
        )
    }

    @MainActor
    private func makeLegacyFocusSessionStore(at storeURL: URL) throws -> UUID {
        let legacySchema = Schema([LegacyPomodoroSchema.FocusSession.self])
        let legacyConfiguration = ModelConfiguration(schema: legacySchema, url: storeURL)
        let legacyContainer = try ModelContainer(
            for: legacySchema,
            configurations: [legacyConfiguration]
        )
        let session = LegacyPomodoroSchema.FocusSession(
            focusMinutes: 25,
            breakMinutes: 5
        )
        legacyContainer.mainContext.insert(session)
        try legacyContainer.mainContext.save()
        return session.id
    }

    private func makeFocusSessionRow(
        id: UUID = UUID(),
        linkedMemoID: UUID? = nil,
        title: String = "테스트 세션",
        category: String,
        startedAt: Date,
        durationSeconds: Int,
        plannedDurationSeconds: Int? = nil,
        endKind: FocusSessionEndKind? = nil,
        rating: Int? = nil,
        selfAssessmentLabel: String? = nil,
        progressResult: PomodoroProgressResult? = nil,
        incompleteReason: PomodoroIncompleteReason? = nil,
        segments: [AppUsageSegment] = [],
        inputActivityRatio: Double? = nil,
        reflectionDeferredAt: Date? = nil
    ) -> FocusSessionRow {
        let endedAt = startedAt.addingTimeInterval(TimeInterval(durationSeconds))
        return FocusSessionRow(
            id: id,
            linkedMemoID: linkedMemoID,
            title: title,
            category: category,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            plannedDurationSeconds: plannedDurationSeconds,
            endKind: endKind,
            rating: rating,
            selfAssessmentLabel: selfAssessmentLabel,
            progressResult: progressResult,
            incompleteReason: incompleteReason,
            observation: PomodoroSessionObservationBuilder.observation(
                from: startedAt,
                to: endedAt,
                segments: segments
            ),
            inputActivityRatio: inputActivityRatio,
            markerColorKey: nil,
            reflectionDeferredAt: reflectionDeferredAt
        )
    }

    private func makeIsolatedUserDefaults() throws -> (UserDefaults, String) {
        let suiteName = "HorongHorongTests.CategoryStore.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        return (userDefaults, suiteName)
    }

    @MainActor
    private func makeLegacyAppUsageSegmentStore(at storeURL: URL) throws -> UUID {
        let legacySchema = Schema([LegacyObservationSchema.AppUsageSegment.self])
        let legacyConfiguration = ModelConfiguration(schema: legacySchema, url: storeURL)
        let legacyContainer = try ModelContainer(
            for: legacySchema,
            configurations: [legacyConfiguration]
        )
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let segment = LegacyObservationSchema.AppUsageSegment(
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            category: "개발",
            startTime: start,
            endTime: start.addingTimeInterval(60)
        )
        legacyContainer.mainContext.insert(segment)
        try legacyContainer.mainContext.save()
        return segment.id
    }

    func testVacationRangeSingleDayHasCountOneAndContainsExactDate() {
        let cal = Calendar.current
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 8
        comps.day = 1
        comps.hour = 14
        comps.minute = 30
        let date = cal.date(from: comps)!

        let range = VacationRange(start: date, end: date, label: "하루 휴가")
        XCTAssertEqual(range.dayCount, 1)
        XCTAssertEqual(range.start, cal.startOfDay(for: date))
        XCTAssertEqual(range.end, cal.startOfDay(for: date))
        XCTAssertTrue(range.contains(date))

        let nextDay = cal.date(byAdding: .day, value: 1, to: date)!
        XCTAssertFalse(range.contains(nextDay))

        let prevDay = cal.date(byAdding: .day, value: -1, to: date)!
        XCTAssertFalse(range.contains(prevDay))
    }

    func testVacationRangeMultiDayHasCorrectDayCount() {
        let cal = Calendar.current
        var startComps = DateComponents(year: 2026, month: 8, day: 1)
        var endComps = DateComponents(year: 2026, month: 8, day: 5)
        let startDate = cal.date(from: startComps)!
        let endDate = cal.date(from: endComps)!

        let range = VacationRange(start: startDate, end: endDate, label: "여름휴가")
        XCTAssertEqual(range.dayCount, 5)
        XCTAssertTrue(range.contains(startDate))
        XCTAssertTrue(range.contains(endDate))

        let midDate = cal.date(byAdding: .day, value: 2, to: startDate)!
        XCTAssertTrue(range.contains(midDate))

        let outsideDate = cal.date(byAdding: .day, value: 6, to: startDate)!
        XCTAssertFalse(range.contains(outsideDate))
    }
}

private enum LegacyPomodoroSchema {
    @Model
    final class FocusSession {
        var id: UUID
        var startedAt: Date
        var endedAt: Date?
        var focusMinutes: Int
        var breakMinutes: Int
        var completed: Bool
        var category: String?

        init(focusMinutes: Int, breakMinutes: Int, category: String? = nil) {
            self.id = UUID()
            self.startedAt = Date()
            self.focusMinutes = focusMinutes
            self.breakMinutes = breakMinutes
            self.completed = false
            self.category = category
        }
    }
}

private enum LegacyObservationSchema {
    @Model
    final class AppUsageSegment {
        var id: UUID
        var appName: String
        var bundleIdentifier: String
        var category: String
        var startTime: Date
        var endTime: Date
        var isManual: Bool

        init(
            appName: String,
            bundleIdentifier: String,
            category: String,
            startTime: Date,
            endTime: Date,
            isManual: Bool = false
        ) {
            self.id = UUID()
            self.appName = appName
            self.bundleIdentifier = bundleIdentifier
            self.category = category
            self.startTime = startTime
            self.endTime = endTime
            self.isManual = isManual
        }
    }
}
