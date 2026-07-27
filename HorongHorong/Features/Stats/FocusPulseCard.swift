import Foundation
import SwiftUI

/// 일간 탭 상단 카드. 왼쪽은 상황에 맞는 한 문장, 오른쪽은 그 문장의 근거가 되는 오늘 지표.
struct FocusPulseCard: View {
    let snapshot: FocusNudgeSnapshot

    private struct Metric: Identifiable {
        let id: String
        let label: String
        let value: String
        let caption: String
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            nudgeBlock
                .frame(width: 260, alignment: .leading)

            Rectangle()
                .fill(PopoverChrome.divider)
                .frame(width: 1, height: 44)

            HStack(alignment: .top, spacing: 20) {
                ForEach(metrics) { metric in
                    metricView(metric)
                }
            }

            Spacer(minLength: 0)
        }
        .popoverCard(padding: 12)
    }

    // MARK: - 문구

    private var nudgeBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(snapshot.nudge.badge, systemImage: badgeIcon)
                .font(.caption.bold())
                .foregroundStyle(PopoverChrome.ink)
                .padding(.vertical, 5)
                .padding(.horizontal, 9)
                .background(PopoverChrome.accentSoft.opacity(0.3), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(PopoverChrome.accent.opacity(0.25), lineWidth: 1)
                )

            Text(messageWithSentenceBreaks(snapshot.nudge.message))
                .font(.callout.weight(.semibold))
                .foregroundStyle(PopoverChrome.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var badgeIcon: String {
        switch snapshot.nudge.tier {
        case .coldStart: return "sun.horizon"
        case .today: return "chart.bar.xaxis"
        case .personalized: return "sparkles"
        }
    }

    // MARK: - 지표

    private var metrics: [Metric] {
        let context = snapshot.context
        return [
            Metric(
                id: "sessions",
                label: "오늘 몰입",
                value: "\(context.todayCompletedCount)회",
                caption: sessionsCaption
            ),
            Metric(
                id: "deepFocus",
                label: "몰입 응답",
                value: reflectionCountValue(context.recentReflection),
                caption: deepFocusCaption
            ),
            Metric(
                id: "coverage",
                label: "타이머로 채운 시간",
                value: context.coverageRatio.map(FocusNudgeFormat.percent) ?? "—",
                caption: coverageCaption
            ),
            Metric(
                id: "tasks",
                label: "오늘 할 일",
                value: context.totalTaskCount > 0 ? "\(context.openTaskCount)/\(context.totalTaskCount)" : "—",
                caption: tasksCaption
            ),
        ]
    }

    private var sessionsCaption: String {
        let context = snapshot.context
        let focused = FocusNudgeFormat.shortDuration(context.todayFocusSeconds)
        guard context.yesterdayCompletedCount > 0 else {
            return context.todayCompletedCount > 0 ? "\(focused) 몰입" : "아직 기록 없음"
        }
        return "\(focused) · 어제 이 시각 \(context.yesterdayCountBySameTime)회"
    }

    private var deepFocusCaption: String {
        let context = snapshot.context
        return reflectionComparisonCaption(
            recent: context.recentReflection,
            previous: context.previousReflection
        )
    }

    private var coverageCaption: String {
        let context = snapshot.context
        guard context.coverageRatio != nil else { return "기록 30분부터 계산" }
        return "기록 \(FocusNudgeFormat.shortDuration(context.observedSeconds)) 중"
    }

    private var tasksCaption: String {
        let context = snapshot.context
        guard context.totalTaskCount > 0 else { return "메모에 등록해보세요" }
        if context.overdueTaskCount > 0 {
            return "남음 · 마감 지남 \(context.overdueTaskCount)개"
        }
        return context.openTaskCount > 0 ? "남음" : "모두 끝냈어요"
    }

    private func metricView(_ metric: Metric) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(metric.label)
                .font(.caption2)
                .foregroundStyle(PopoverChrome.inkTertiary)
            Text(metric.value)
                .font(.callout.bold())
                .monospacedDigit()
                .foregroundStyle(PopoverChrome.ink)
            Text(metric.caption)
                .font(.system(size: 10))
                .foregroundStyle(PopoverChrome.inkTertiary)
                .lineLimit(1)
        }
    }
}

/// 과거 일간 탭 상단 카드. 선택한 날짜까지의 최근 7일과 그 직전 7일을 비교한다.
struct HistoricalFocusTrendCard: View {
    let snapshot: HistoricalFocusTrendSnapshot

    private struct Metric: Identifiable {
        let id: String
        let label: String
        let value: String
        let caption: String
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            trendBlock
                .frame(width: 300, alignment: .leading)

            Rectangle()
                .fill(PopoverChrome.divider)
                .frame(width: 1, height: 44)

            HStack(alignment: .top, spacing: 20) {
                ForEach(metrics) { metric in
                    metricView(metric)
                }
            }

            Spacer(minLength: 0)
        }
        .popoverCard(padding: 12)
    }

    private var trendBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(badge, systemImage: "chart.xyaxis.line")
                .font(.caption.bold())
                .foregroundStyle(PopoverChrome.ink)
                .padding(.vertical, 5)
                .padding(.horizontal, 9)
                .background(PopoverChrome.accentSoft.opacity(0.3), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(PopoverChrome.accent.opacity(0.25), lineWidth: 1)
                )

            Text(messageWithSentenceBreaks(message))
                .font(.callout.weight(.semibold))
                .foregroundStyle(PopoverChrome.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var badge: String {
        switch snapshot.state {
        case .deepening:
            return "몰입 응답이 늘어난 흐름"
        case .steady:
            return "비슷하게 이어진 흐름"
        case .softening:
            return "잠시 달라진 흐름"
        case .collecting:
            return "흐름을 알아가는 중"
        }
    }

    private var message: String {
        switch snapshot.state {
        case .deepening:
            return "깊게 또는 대체로 집중했다고 답한 회고가 이전보다 \(snapshot.focusedResponseDelta ?? 0)회 늘었어요."
        case .steady:
            return "최근 7일의 몰입 응답 횟수가 이전과 비슷하게 이어졌어요."
        case .softening:
            return "깊게 또는 대체로 집중했다고 답한 회고가 이전보다 \(abs(snapshot.focusedResponseDelta ?? 0))회 적었어요. 잠시 흐름이 달라진 시기예요."
        case .collecting:
            if snapshot.recent.reflection.validResponseCount
                >= FocusReflectionSummary.minimumComparableResponseCount,
               snapshot.previous.reflection.validResponseCount
                >= FocusReflectionSummary.minimumComparableResponseCount {
                return "두 기간의 전체 회고 수가 달라 현재 기록을 중심으로 보여드려요."
            }
            return "두 기간을 비교할 회고가 조금 더 필요해요. 지금은 기록된 활동을 보여드려요."
        }
    }

    private var metrics: [Metric] {
        [
            Metric(
                id: "reflectionFocus",
                label: "몰입 응답",
                value: reflectionCountValue(snapshot.recent.reflection),
                caption: reflectionCaption
            ),
            Metric(
                id: "timerCoverage",
                label: "타이머와 함께",
                value: snapshot.recent.timerCoverageRatio.map(FocusNudgeFormat.percent) ?? "—",
                caption: coverageCaption
            ),
            Metric(
                id: "categorySwitches",
                label: "카테고리 전환",
                value: snapshot.recent.categorySwitchesPerRecordedTenMinutes
                    .map(formatSwitchRate) ?? "—",
                caption: switchCaption
            ),
            Metric(
                id: "pomodoro",
                label: "포모도로 몰입",
                value: "\(snapshot.recent.completedPomodoroCount)회",
                caption: pomodoroCaption
            ),
        ]
    }

    private var reflectionCaption: String {
        reflectionComparisonCaption(
            recent: snapshot.recent.reflection,
            previous: snapshot.previous.reflection
        )
    }

    private var coverageCaption: String {
        guard snapshot.recent.timerCoverageRatio != nil else {
            return "활동 기록 30분부터 계산"
        }
        guard let previous = snapshot.previous.timerCoverageRatio else {
            return "이전 활동 기록이 더 필요해요"
        }
        return "이전 7일 \(FocusNudgeFormat.percent(previous))"
    }

    private var switchCaption: String {
        guard snapshot.recent.categorySwitchesPerRecordedTenMinutes != nil else {
            return "활동 기록 30분부터 계산"
        }
        guard let previous = snapshot.previous.categorySwitchesPerRecordedTenMinutes else {
            return "이전 활동 기록이 더 필요해요"
        }
        return "이전 7일 \(formatSwitchRate(previous))"
    }

    private var pomodoroCaption: String {
        let duration = FocusNudgeFormat.shortDuration(
            snapshot.recent.pomodoroFocusSeconds
        )
        return "\(duration) · 이전 \(snapshot.previous.completedPomodoroCount)회"
    }

    private func formatSwitchRate(_ value: Double) -> String {
        String(format: "%.1f회/10분", value)
    }

    private func metricView(_ metric: Metric) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(metric.label)
                .font(.caption2)
                .foregroundStyle(PopoverChrome.inkTertiary)
            Text(metric.value)
                .font(.callout.bold())
                .monospacedDigit()
                .foregroundStyle(PopoverChrome.ink)
            Text(metric.caption)
                .font(.system(size: 10))
                .foregroundStyle(PopoverChrome.inkTertiary)
                .lineLimit(1)
        }
    }
}

private func messageWithSentenceBreaks(_ message: String) -> String {
    message.replacingOccurrences(of: ". ", with: ".\n")
}

private func reflectionCountValue(_ summary: FocusReflectionSummary) -> String {
    guard summary.validResponseCount > 0 else { return "—" }
    return "\(summary.focusedResponseCount)/\(summary.validResponseCount)회"
}

private func reflectionComparisonCaption(
    recent: FocusReflectionSummary,
    previous: FocusReflectionSummary
) -> String {
    guard previous.validResponseCount > 0 else {
        return recent.validResponseCount > 0
            ? "최근 7일 유효 회고 \(recent.validResponseCount)회"
            : "회고를 남겨보세요"
    }

    let previousValue = "\(previous.focusedResponseCount)/\(previous.validResponseCount)회"
    guard let delta = recent.focusedResponseDelta(comparedTo: previous) else {
        return "이전 \(previousValue) · 비교 보류"
    }
    if delta > 0 {
        return "이전 \(previousValue) · +\(delta)회"
    }
    if delta < 0 {
        return "이전 \(previousValue) · \(delta)회"
    }
    return "이전 \(previousValue) · 변화 없음"
}
