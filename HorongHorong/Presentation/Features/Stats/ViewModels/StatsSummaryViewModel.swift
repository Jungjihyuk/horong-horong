import Foundation
import Observation

@MainActor
@Observable
final class StatsSummaryViewModel {
    private(set) var categoryDurations: [StatsCategoryDuration] = []
    private(set) var dailyDurations: [StatsDayDuration] = []
    private(set) var todayFocusSummary = DailyFocusSummary(
        totalSeconds: 0,
        switches: 0,
        longestFocusSeconds: 0,
        topCategory: nil,
        overallScore: 0
    )
    private(set) var hasTodaySegmentDetails = false
    private(set) var nudge: StatsSummaryNudge?
    private(set) var weekLongestSessionSeconds = 0

    private let repository: StatsSummaryRepository

    init(repository: StatsSummaryRepository) {
        self.repository = repository
    }

    func loadToday(referenceDate: Date) {
        let summary = repository.todaySummary(on: referenceDate)
        categoryDurations = summary.categories
        dailyDurations = []
        todayFocusSummary = DailyFocusSummary(
            totalSeconds: summary.focus.totalSeconds,
            switches: summary.focus.switches,
            longestFocusSeconds: summary.focus.longestFocusSeconds,
            topCategory: summary.focus.topCategory,
            overallScore: summary.focus.overallScore
        )
        hasTodaySegmentDetails = summary.hasSegmentDetails
        nudge = summary.nudge
        weekLongestSessionSeconds = 0
    }

    func loadWeek(referenceDate: Date) {
        let summary = repository.weekSummary(containing: referenceDate)
        categoryDurations = summary.categories
        dailyDurations = summary.days
        weekLongestSessionSeconds = summary.longestSessionSeconds
        nudge = nil
    }
}
