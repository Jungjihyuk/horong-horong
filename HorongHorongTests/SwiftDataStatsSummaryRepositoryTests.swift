import SwiftData
import XCTest
@testable import 호롱호롱

@MainActor
final class SwiftDataStatsSummaryRepositoryTests: XCTestCase {
    private let calendar = Calendar.current

    private func makeContainer() throws -> ModelContainer {
        let schema = HorongHorongModelSchema.make()
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func day(_ offset: Int = 0) -> Date {
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    private func time(_ hour: Int, minute: Int = 0, on day: Date) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    func testTodaySummaryFetchesOverlappingSegmentsAndAttributesPomodoroTime() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let targetDay = day()
        context.insert(AppUsageSegment(
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            category: "개발",
            startTime: time(9, on: targetDay),
            endTime: time(9, minute: 30, on: targetDay)
        ))
        context.insert(AppUsageSegment(
            appName: "Outside",
            bundleIdentifier: "outside",
            category: "제외",
            startTime: time(9, on: day(-2)),
            endTime: time(10, on: day(-2))
        ))
        let session = FocusSession(focusMinutes: 25, breakMinutes: 5, category: "집중")
        session.startedAt = time(9, on: targetDay)
        session.endedAt = time(9, minute: 25, on: targetDay)
        session.completed = true
        context.insert(session)
        try context.save()

        let repository = SwiftDataStatsSummaryRepository(context: context, calendar: calendar)
        let summary = repository.todaySummary(on: targetDay)
        let categories = Dictionary(uniqueKeysWithValues: summary.categories.map {
            ($0.category, $0.durationSeconds)
        })

        XCTAssertEqual(categories, ["집중": 1_500, "개발": 300])
        XCTAssertEqual(summary.focus.totalSeconds, 1_800)
        XCTAssertEqual(summary.focus.longestFocusSeconds, 1_800)
        XCTAssertTrue(summary.hasSegmentDetails)
    }

    func testTodaySummaryFallsBackToVisibleDailyRecords() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let targetDay = day(2)
        let visible = AppUsageRecord(
            appName: "Pages",
            bundleIdentifier: "com.apple.Pages",
            category: "문서",
            date: targetDay
        )
        visible.durationSeconds = 900
        context.insert(visible)
        let focusRecord = AppUsageRecord(
            appName: "Focus",
            bundleIdentifier: "\(Constants.focusSessionBundlePrefix)test",
            category: "집중",
            date: targetDay
        )
        focusRecord.durationSeconds = 1_500
        context.insert(focusRecord)
        try context.save()

        let repository = SwiftDataStatsSummaryRepository(context: context, calendar: calendar)
        let summary = repository.todaySummary(on: targetDay)

        XCTAssertEqual(summary.categories, [StatsCategoryDuration(category: "문서", durationSeconds: 900)])
        XCTAssertEqual(summary.focus.totalSeconds, 900)
        XCTAssertEqual(summary.focus.longestFocusSeconds, 900)
        XCTAssertEqual(summary.focus.topCategory, "문서")
        XCTAssertFalse(summary.hasSegmentDetails)
    }

    func testWeekSummarySplitsSegmentAtDayBoundary() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let weekStart = Constants.mondayWeekStart(for: day(), calendar: calendar)
        let firstDay = calendar.date(byAdding: .day, value: 1, to: weekStart) ?? weekStart
        let secondDay = calendar.date(byAdding: .day, value: 2, to: weekStart) ?? weekStart
        context.insert(AppUsageSegment(
            appName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            category: "개발",
            startTime: time(23, minute: 50, on: firstDay),
            endTime: time(0, minute: 10, on: secondDay)
        ))
        try context.save()

        let repository = SwiftDataStatsSummaryRepository(context: context, calendar: calendar)
        let summary = repository.weekSummary(containing: day())

        XCTAssertEqual(summary.days.count, 7)
        XCTAssertEqual(summary.days[1].durationSeconds, 600)
        XCTAssertEqual(summary.days[2].durationSeconds, 600)
        XCTAssertEqual(summary.categories, [StatsCategoryDuration(category: "개발", durationSeconds: 1_200)])
        XCTAssertEqual(summary.longestSessionSeconds, 1_200)
    }
}

@MainActor
final class StatsSummaryViewModelTests: XCTestCase {
    func testLoadTodayAndWeekReplacePresentationState() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let repository = FakeStatsSummaryRepository(
            today: StatsTodaySummary(
                categories: [StatsCategoryDuration(category: "개발", durationSeconds: 600)],
                focus: StatsFocusSummary(
                    totalSeconds: 600,
                    switches: 2,
                    longestFocusSeconds: 480,
                    topCategory: "개발",
                    overallScore: 0.75
                ),
                hasSegmentDetails: true,
                nudge: StatsSummaryNudge(badge: "관찰", message: "집중했어요")
            ),
            week: StatsWeekSummary(
                categories: [StatsCategoryDuration(category: "문서", durationSeconds: 1_200)],
                days: [StatsDayDuration(date: date, durationSeconds: 1_200)],
                longestSessionSeconds: 900
            )
        )
        let viewModel = StatsSummaryViewModel(repository: repository)

        viewModel.loadToday(referenceDate: date)
        XCTAssertEqual(viewModel.todayFocusSummary.totalSeconds, 600)
        XCTAssertEqual(viewModel.categoryDurations.first?.category, "개발")
        XCTAssertTrue(viewModel.hasTodaySegmentDetails)
        XCTAssertEqual(viewModel.nudge?.message, "집중했어요")

        viewModel.loadWeek(referenceDate: date)
        XCTAssertEqual(viewModel.categoryDurations.first?.category, "문서")
        XCTAssertEqual(viewModel.dailyDurations.first?.durationSeconds, 1_200)
        XCTAssertEqual(viewModel.weekLongestSessionSeconds, 900)
        XCTAssertNil(viewModel.nudge)
    }
}

@MainActor
private final class FakeStatsSummaryRepository: StatsSummaryRepository {
    private let today: StatsTodaySummary
    private let week: StatsWeekSummary

    init(today: StatsTodaySummary, week: StatsWeekSummary) {
        self.today = today
        self.week = week
    }

    func todaySummary(on date: Date) -> StatsTodaySummary { today }
    func weekSummary(containing date: Date) -> StatsWeekSummary { week }
}
