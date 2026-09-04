import Foundation

/// 목표가 **닫힌 이유**. 완료로 닫힌 것은 `completedAt` 이 따로 들고 있다.
enum AchievementCloseReason: String, Sendable, CaseIterable {
    /// 사용자가 「실패로 마감」을 눌렀다.
    case failed
    /// 유예가 끝나 자동으로 닫혔다.
    ///
    /// `failed` 와 결과는 같지만 나누는 이유는 **안내 문구가 달라야 하기 때문**이다.
    /// 「실패로 마감했어요」와 「자동으로 정리했어요」는 사용자가 겪은 일이 다르다.
    case expired
    /// 사용자가 접었다. 실패가 아니므로 패널티가 없다.
    case abandoned

    /// 포인트를 깎는 사유인가.
    var deservesPenalty: Bool {
        self != .abandoned
    }
}

/// 마감을 넘긴 목표가 지금 어느 단계인가.
enum AchievementSettlementState: Equatable, Sendable {
    /// 아직 마감 전.
    case open
    /// 마감은 지났고 유예 중 — **사용자가 고를 수 있는 유일한 구간**이다.
    case awaiting(deadline: Date, graceEnd: Date)
    /// 유예도 끝났다. 자동 실패 마감 대상.
    case expired(deadline: Date)
    /// 이미 닫혔다(완료·실패·접기).
    case closed

    var isAwaiting: Bool {
        if case .awaiting = self { return true }
        return false
    }

    var isExpired: Bool {
        if case .expired = self { return true }
        return false
    }

    /// 마감이 지난 상태인가. 배너에 모을 대상을 고를 때 쓴다.
    var deadline: Date? {
        switch self {
        case let .awaiting(deadline, _): return deadline
        case let .expired(deadline): return deadline
        case .open, .closed: return nil
        }
    }
}

/// 마감을 넘긴 목표를 어떻게 정산할지 정하는 규칙.
///
/// **「기한 지남」은 상태가 아니라 아직 답하지 않은 질문이다.** 지금까지는 못 끝낸 목표가
/// 이번 주로 무한 이월되기만 했다. 마감이 지난 목표는 ①실패 확정 ②기간을 짧게 잡았을 뿐
/// ③애초에 마감이 무의미 셋 중 하나인데, 답을 아는 건 사용자뿐이고 **목표를 만드는 시점엔
/// 사용자도 모른다.** 그래서 마감이 지난 뒤에 묻고, 안 고르면 유예 끝에 실패로 닫는다.
///
/// `Date()` 를 안에서 읽지 않는다(R9) — 「자정이 지나면 답이 달라지는」 계산이라
/// `now` 를 받지 않으면 테스트할 수 없다.
enum AchievementSettlementPolicy {
    static let weeklyCadence = "주간"
    static let monthlyCadence = "월간"

    /// 정산 대상이 되는 단계. 연간·역할·비전은 하위 목표로 진행률을 내므로 제외한다.
    static let settleableCadences: Set<String> = [weeklyCadence, monthlyCadence]

    static func isSettleable(cadence: String) -> Bool {
        settleableCadences.contains(cadence)
    }

    /// 마감일을 안 넣은 목표의 **암묵적 마감**. 주간은 만든 주가, 월간은 만든 달이 끝나는 순간이다.
    ///
    /// 목표 만들기 시트의 마감일은 기본값이 꺼져 있어 대부분의 목표에 `dueDate` 가 없다.
    /// 그 목표들을 정산에서 빼면 기능이 거의 동작하지 않는다.
    ///
    /// 반환값은 **경계 순간**이다 — 「그 주 일요일 23:59:59」가 아니라 「다음 주 월요일 0시」.
    /// 끝 시각을 1초 앞으로 잡으면 그 1초 사이가 어느 쪽도 아닌 틈이 된다.
    static func implicitDeadline(
        cadence: String,
        createdAt: Date,
        calendar: Calendar = .current
    ) -> Date? {
        switch cadence {
        case weeklyCadence:
            let weekStart = Constants.mondayWeekStart(for: createdAt, calendar: calendar)
            return calendar.date(byAdding: .day, value: 7, to: weekStart)
        case monthlyCadence:
            let monthStart = AchievementMonthlyStats.firstDayOfMonth(for: createdAt, calendar: calendar)
            return calendar.date(byAdding: .month, value: 1, to: monthStart)
        default:
            return nil
        }
    }

    /// 이 목표가 실제로 넘긴 것이 되는 순간. 마감일을 넣었으면 **그 날이 다 지난 뒤**다.
    static func effectiveDeadline(
        cadence: String,
        dueDate: Date?,
        createdAt: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard isSettleable(cadence: cadence) else { return nil }
        guard let dueDate else {
            return implicitDeadline(cadence: cadence, createdAt: createdAt, calendar: calendar)
        }
        // 마감일은 «그 날까지» 라는 뜻이다. 그 날이 다 지나야 넘긴 것이므로 다음 날 0시가 경계다.
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: dueDate))
    }

    /// 자동 실패 마감 시각 — 마감이 속한 주기의 **다음 주기가 끝나는 순간**.
    ///
    /// 「다음 주가 시작할 때」로 잡으면 마감일을 안 넣은 주간 목표는 암묵적 마감(일요일 끝)과
    /// 유예 종료(월요일 0시)가 같은 순간이 되어 **고를 틈이 사라진다.** 한 주기를 더 주면
    /// 만회할 기간이 생기고, 마감일을 넣은 목표와 규칙도 하나로 유지된다.
    static func graceEnd(
        after deadline: Date,
        cadence: String,
        calendar: Calendar = .current
    ) -> Date {
        // `deadline` 은 «지나면 넘긴 것» 인 경계라 그 순간은 이미 다음 주기에 속한다.
        // 마감이 **속한** 주기를 찾으려면 한 순간 앞을 봐야 한다.
        let lastMoment = deadline.addingTimeInterval(-1)
        switch cadence {
        case monthlyCadence:
            let monthStart = AchievementMonthlyStats.firstDayOfMonth(for: lastMoment, calendar: calendar)
            return calendar.date(byAdding: .month, value: 2, to: monthStart) ?? deadline
        default:
            let weekStart = Constants.mondayWeekStart(for: lastMoment, calendar: calendar)
            return calendar.date(byAdding: .day, value: 14, to: weekStart) ?? deadline
        }
    }

    /// 지금 이 목표가 어느 단계인가.
    ///
    /// **완료 도장이 찍혔으면 무조건 `.closed`.** 달성 여부는 파생값이라 할일을 더 묶으면
    /// 다시 미완료로 돌아가는데, 그때 실패로 처리하면 이미 받은 달성을 빼앗는 셈이 된다.
    static func state(
        cadence: String,
        dueDate: Date?,
        createdAt: Date,
        completedAt: Date?,
        closedAt: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> AchievementSettlementState {
        guard closedAt == nil, completedAt == nil else { return .closed }
        guard let deadline = effectiveDeadline(
            cadence: cadence,
            dueDate: dueDate,
            createdAt: createdAt,
            calendar: calendar
        ) else {
            return .open
        }
        guard now >= deadline else { return .open }
        let grace = graceEnd(after: deadline, cadence: cadence, calendar: calendar)
        return now < grace
            ? .awaiting(deadline: deadline, graceEnd: grace)
            : .expired(deadline: deadline)
    }

    /// 실패로 마감할 때 차감할 **명목** 포인트. 잔액이 모자라 실제로 덜 깎이는 것은 원장이 정한다.
    ///
    /// 월간은 항상 0이다. 월간 진행률은 하위 주간 목표로 계산되므로 주간이 이미 깎인 뒤
    /// 월간까지 깎으면 **같은 실패를 두 번 벌하는** 셈이 된다. 월간 실패는 보상 교환 자격을
    /// 잃는 것으로 갈음한다.
    static func penaltyPoints(cadence: String, basePoints: Int, ratio: Double) -> Int {
        guard cadence == weeklyCadence, basePoints > 0 else { return 0 }
        let clampedRatio = min(1, max(0, ratio))
        return max(0, Int((Double(basePoints) * clampedRatio).rounded()))
    }

    /// 화면에 보여 줄 마감 **날짜**. 경계 순간(다음 날 0시)에서 하루를 되돌린 값이다.
    static func deadlineDay(for deadline: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: deadline.addingTimeInterval(-1))
    }

    /// 실패로 마감한 목표를 **이번 주기에 다시** 세우기 위한 초안.
    ///
    /// 「주간 기록」처럼 주가 넘어가면 새로 세워야 하는 목표가 있는데, 반복 목표를 정식
    /// 기능으로 만들면 템플릿·자동 생성·중복 방지가 줄줄이 붙는다. 실패 정산 흐름에서
    /// 복제 버튼 하나로 끊는다.
    ///
    /// **연결한 할일은 그대로 옮긴다.** 닫힌 목표는 소유권을 놓으므로(`AchievementDataBuilder`)
    /// 아직 못 끝낸 할일이 새 목표로 따라와야 이어서 하는 의미가 산다.
    static func retryDraft(
        from detail: AchievementGoalDetail,
        now: Date,
        calendar: Calendar = .current
    ) -> AchievementGoalDraft {
        let deadline = implicitDeadline(cadence: detail.cadence, createdAt: now, calendar: calendar)
        return AchievementGoalDraft(
            title: detail.title,
            emoji: detail.emoji,
            cadence: detail.cadence,
            rule: detail.rule,
            targetCount: detail.targetCount,
            targetValueText: detail.targetValueText,
            periodText: detail.periodText,
            dueDate: deadline.map { deadlineDay(for: $0, calendar: calendar) },
            colorHex: detail.colorHex,
            roleName: detail.roleName,
            vision: detail.vision,
            yearGoal: detail.yearGoal,
            monthGoal: detail.monthGoal,
            linkedMemoIDs: detail.linkedMemoIDs,
            // 복제본은 «직접 만든 목표» 다. 추천 출처를 물려주면 채택률이 부풀어 오른다.
            sourceRunID: nil,
            sourceSuggestionID: nil
        )
    }
}
