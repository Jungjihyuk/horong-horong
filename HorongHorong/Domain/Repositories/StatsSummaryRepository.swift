import Foundation

/// 메뉴바 통계 요약에 필요한 집계를 제공한다.
@MainActor
protocol StatsSummaryRepository {
    func todaySummary(on date: Date) -> StatsTodaySummary
    func weekSummary(containing date: Date) -> StatsWeekSummary
}

struct StatsCategoryDuration: Equatable, Sendable {
    let category: String
    let durationSeconds: Int
}

struct StatsDayDuration: Equatable, Sendable {
    let date: Date
    let durationSeconds: Int
}

struct StatsFocusSummary: Equatable, Sendable {
    let totalSeconds: Int
    let switches: Int
    let longestFocusSeconds: Int
    let topCategory: String?
    let overallScore: Double
}

struct StatsSummaryNudge: Equatable, Sendable {
    let badge: String
    let message: String
}

struct StatsTodaySummary: Equatable, Sendable {
    let categories: [StatsCategoryDuration]
    let focus: StatsFocusSummary
    let hasSegmentDetails: Bool
    let nudge: StatsSummaryNudge?
}

struct StatsWeekSummary: Equatable, Sendable {
    let categories: [StatsCategoryDuration]
    let days: [StatsDayDuration]
    let longestSessionSeconds: Int
}
