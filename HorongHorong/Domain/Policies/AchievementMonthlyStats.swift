import AppKit
import HorongAI
import HorongAIMLX
import OSLog
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if canImport(FoundationModels)
import FoundationModels
#endif

/*
 월간 목표의 주차별 진행률 계산. 순수 계산이라 화면 없이 검사할 수 있다.

 원래 `AchievementViews.swift`(9,854줄) 한 파일에 있었다. 2026-09-03 분할.
 */

struct AchievementMonthlyWeekProgress: Identifiable {
    let id = UUID()
    let week: Int
    let completed: Int
    let total: Int
    let isCurrent: Bool

    var progress: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(completed) / Double(total))
    }

    var percentText: String {
        "\(Int(round(progress * 100)))%"
    }
}

/// 월간 목표 통계 계산. 화면 타입과 떼어 두어 테스트에서 바로 부른다.
enum AchievementMonthlyStats {
    /// 통계에 필요한 목표 하나의 정보.
    /// completions는 이룬 시점들 — 하위 주간 목표가 있으면 그 목표를 끝낸 날, 없으면 할 일을 끝낸 날이다.
    struct Goal {
        let total: Int
        let completions: [Date]
    }

    static func firstDayOfMonth(for date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }

    /// 목표가 그 달 화면에 보이는지.
    /// 만든 달에서 시작해 완료한 달에 끝나고, 아직 못 끝냈으면 이번 달까지 이어진다.
    /// 주 단위 goalWeekSpan과 같은 규칙이라, 그달에 못 끝낸 목표는 다음 달로 이월된다.
    /// 못 이룬 채 닫힌 목표(`closedAt`)도 그 달에서 끝난다 — 주 단위와 같은 규칙이다.
    /// 기본값이 nil 이라 이 인자를 안 넘기던 호출부는 예전과 완전히 같은 값을 받는다.
    static func goalBelongs(
        toMonthStarting monthStart: Date,
        createdAt: Date,
        completedAt: Date?,
        closedAt: Date? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        let start = firstDayOfMonth(for: createdAt, calendar: calendar)
        // 목표가 목록에서 사라지는 순간은 «닫힌 순간» 하나다 — 이뤄서든 못 이뤄서든.
        let closingMoment = closedAt ?? completedAt
        let end = max(start, firstDayOfMonth(for: closingMoment ?? now, calendar: calendar))
        return monthStart >= start && monthStart <= end
    }

    /// 주차별 누적 달성률.
    /// 각 주차는 그 주 끝까지 이룬 양을 그 달 월간 목표의 전체 목표량으로 나눈 값이다.
    /// 분모가 주마다 같아 주끼리 비교할 수 있고, 활동이 없는 주는 앞 주 값을 그대로 이어받아 우상향한다.
    static func weekProgress(
        forMonth month: Date,
        goals: [Goal],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [AchievementMonthlyWeekProgress] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let dayRange = calendar.range(of: .day, in: .month, for: month) else {
            return []
        }

        let firstDay = monthInterval.start
        let leadingBlankCount = (calendar.component(.weekday, from: firstDay) + 5) % 7
        // 월간 통계는 최대 5주로 보여 준다. 달력에 여섯 번째 줄이 필요한 달은
        // 마지막 며칠을 5주차에 포함해 별도의 6주차를 만들지 않는다.
        let calendarRowCount = max(1, Int(ceil(Double(leadingBlankCount + dayRange.count) / 7.0)))
        let weekCount = min(5, calendarRowCount)
        let total = goals.reduce(0) { $0 + $1.total }
        let isCurrentMonth = calendar.isDate(month, equalTo: now, toGranularity: .month)
        let currentWeek = isCurrentMonth
            ? min(weekIndex(for: now, calendar: calendar), weekCount)
            : nil
        let visibleWeekCount = currentWeek ?? weekCount

        return (1...visibleWeekCount).map { week in
            let weekStart = calendar.date(byAdding: .day, value: ((week - 1) * 7) - leadingBlankCount, to: firstDay) ?? firstDay
            let rawWeekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
            let weekEnd = week == weekCount ? monthInterval.end : min(rawWeekEnd, monthInterval.end)
            let completed = goals.reduce(0) { sum, goal in
                sum + min(goal.total, goal.completions.filter { $0 < weekEnd }.count)
            }
            return AchievementMonthlyWeekProgress(
                week: week,
                completed: completed,
                total: total,
                isCurrent: week == currentWeek
            )
        }
    }

    /// 그 날이 그 달의 몇 주차인지. 달력 첫 줄이 1주차다.
    static func weekIndex(for date: Date, calendar: Calendar = .current) -> Int {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else { return 1 }
        let leadingBlankCount = (calendar.component(.weekday, from: monthInterval.start) + 5) % 7
        return ((leadingBlankCount + calendar.component(.day, from: date) - 1) / 7) + 1
    }
}
