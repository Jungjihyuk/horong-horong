import XCTest
import SwiftData
import UserNotifications
@testable import 호롱호롱

final class ConstantsDefaultsTests: XCTestCase {
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
        let archived = Memo(content: "보관한 일")
        archived.startDate = now
        archived.isArchivedValue = true

        XCTAssertFalse(
            TodayPlanningReminderPolicy.hasTodayTask(
                in: [completed, archived],
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
            Memo.self,
            FocusSession.self,
            PomodoroTaskCompletion.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let memo = Memo(content: "  완료 근거 저장  ")
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
            Memo.self,
            FocusSession.self,
            PomodoroTaskCompletion.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let originalUpdatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let memo = Memo(content: "직접 완료한 할 일")
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
            Memo.self,
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
            Memo.self,
            FocusSession.self,
            PomodoroTaskCompletion.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let memo = Memo(content: "완료 취소")
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
            Memo.self,
            FocusSession.self,
            PomodoroReflection.self,
            PomodoroTaskCompletion.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let memo = Memo(content: "세션 삭제 시 되돌릴 할 일")
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
            Memo.self,
            FocusSession.self,
            PomodoroReflection.self,
            PomodoroTaskCompletion.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let memo = Memo(content: "기존 삭제 오류 복구")
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
            Memo.self,
            FocusSession.self,
            PomodoroTaskCompletion.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let memo = Memo(content: "여러 완료 근거")
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
            Memo.self,
            FocusSession.self,
            PomodoroTaskCompletion.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let memo = Memo(content: "완료 근거 삭제 순서")
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
            Memo.self,
            FocusSession.self,
            PomodoroTaskCompletion.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let memo = Memo(content: "다시 진행한 할 일")
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
            Memo.self,
            FocusSession.self,
            PomodoroTaskCompletion.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let memo = Memo(content: "나중에 다시 완료한 일")
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
            Memo.self,
            FocusSession.self,
            PomodoroTaskCompletion.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let memo = Memo(content: "수정 전 제목")
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

    func testPomodoroTaskCandidatesIncludeGoalLinkedAndTodayTasksOnce() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 12))!
        let today = calendar.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 9))!
        let tomorrow = calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 9))!

        let goalLinked = Memo(content: "\n  통계 회고 결과 표시\n상세 설명")
        let todayOnly = Memo(content: "오늘 시작할 일")
        todayOnly.startDate = today
        let todayAndGoalLinked = Memo(content: "오늘의 목표 할 일")
        todayAndGoalLinked.startDate = today
        let completed = Memo(content: "완료한 오늘 할 일")
        completed.startDate = today
        completed.isCompletedValue = true
        let archived = Memo(content: "보관한 일")
        archived.startDate = today
        archived.isArchivedValue = true
        let future = Memo(content: "내일 시작할 일")
        future.startDate = tomorrow
        let noStartDate = Memo(content: "시작일이 없는 일반 할 일")
        let primaryGoal = AchievementGoalRecord(
            title: "포모도로 강화",
            linkedMemoIDs: [goalLinked.id, todayAndGoalLinked.id, archived.id]
        )
        let duplicateGoal = AchievementGoalRecord(
            title: "포모도로 강화",
            linkedMemoIDs: [goalLinked.id]
        )

        let candidates = PomodoroTaskCandidateBuilder.candidates(
            memos: [goalLinked, todayOnly, todayAndGoalLinked, completed, archived, future, noStartDate],
            goalRecords: [primaryGoal, duplicateGoal],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(candidates, [
            PomodoroTaskCandidate(
                id: goalLinked.id,
                title: "통계 회고 결과 표시",
                isToday: false,
                isGoalLinked: true
            ),
            PomodoroTaskCandidate(
                id: todayOnly.id,
                title: "오늘 시작할 일",
                isToday: true,
                isGoalLinked: false
            ),
            PomodoroTaskCandidate(
                id: todayAndGoalLinked.id,
                title: "오늘의 목표 할 일",
                isToday: true,
                isGoalLinked: true
            )
        ])
    }

    func testPomodoroTaskCandidatePreservesFullTitleForSessionSnapshot() throws {
        let fullTitle = String(repeating: "긴 작업 제목 ", count: 8)
            .trimmingCharacters(in: .whitespaces)
        let memo = Memo(content: "\(fullTitle)\n상세 설명")
        let goal = AchievementGoalRecord(title: "장기 목표", linkedMemoIDs: [memo.id])

        let candidate = try XCTUnwrap(
            PomodoroTaskCandidateBuilder.candidates(
                memos: [memo],
                goalRecords: [goal]
            ).first
        )

        XCTAssertEqual(candidate.title, fullTitle)
        XCTAssertFalse(candidate.title.hasSuffix("..."))
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
        XCTAssertEqual(observation.appSwitchCount, 0)
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
    func testPomodoroSessionObservationDoesNotInventSwitchAcrossGap() {
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

        XCTAssertEqual(observation.appSwitchCount, 0)
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
    func testPomodoroSessionObservationDoesNotBridgeMinimumSegmentGap() {
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

        XCTAssertEqual(AppTracker.minimumSegmentSeconds, 3)
        XCTAssertEqual(observation.appSwitchCount, 0)
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
        XCTAssertTrue(
            try updatedContainer.mainContext.fetch(
                FetchDescriptor<PomodoroTaskCompletion>()
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
            Constants.normalizedRepresentativeAgentTypes(from: "Gemini,Opencode"),
            ["Gemini", "Opencode"]
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
