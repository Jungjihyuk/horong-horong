import Foundation

/// 넛지 문구 카탈로그. 문구를 고치거나 새 전략을 넣고 빼는 작업은 이 파일 안에서만 하면 된다.
///
/// - 규칙은 `priority` 가 큰 것부터 검사하고, 조건을 만족하는 첫 규칙 하나만 화면에 나간다.
/// - `messages` 를 여러 개 적으면 (날짜, 규칙 id) 시드로 하루 동안 고정된 하나가 뽑힌다.
/// - 조건에 쓰는 값과 임계값은 모두 `FocusNudgeContext` 에서 온다. 새 지표가 필요하면 컨텍스트에 먼저 추가한다.
enum FocusNudgeCatalog {
    static let rules: [FocusNudgeRule] = [
        // MARK: - 콜드스타트 (포모도로 이용 내역이 없는 사용자)
        coldStartWithTask,
        coldStartFirstStep,

        // MARK: - 개인화 (최근 회고에서 읽어낸 반복 신호)
        repeatedIncompleteReason,

        // MARK: - 오늘 진행
        notStartedWithTask,
        behindYesterday,
        overdueTasks,
        lowCoverage,

        // MARK: - 개인화 (추세)
        deepFocusDrop,

        // MARK: - 오늘 진행
        firstSessionDone,
        aheadOfYesterday,

        // MARK: - 개인화 (추세·영역)
        deepFocusRise,
        focusedCategory,

        // MARK: - 기본
        fallback,
    ]

    // MARK: - 콜드스타트

    /// 오늘 날짜로 등록한 할 일이 있으면 가장 가까운 것을 지목한다.
    private static let coldStartWithTask = FocusNudgeRule(
        id: "coldStart.withTask",
        tier: .coldStart,
        priority: 100,
        badge: "오늘 시작",
        condition: { $0.isColdStart && $0.nextTask != nil },
        messages: [
            { "오늘은 '\(taskTitle($0))'부터 시작해볼까요?" },
            { "'\(taskTitle($0))'을 가장 먼저 해봐요. 일단 시작하면 마음이 편안해질 거에요." },
            { "먼저 '\(taskTitle($0))'부터 가볍게 해볼까요? 한 번 집중하면 오늘의 첫걸음은 충분해요." },
        ]
    )

    /// 할 일도 기록도 없는 첫 화면. 부담을 낮추는 문구 중 하나를 하루 단위로 고정해 보여준다.
    private static let coldStartFirstStep = FocusNudgeRule(
        id: "coldStart.firstStep",
        tier: .coldStart,
        priority: 95,
        badge: "가볍게 시작",
        condition: { $0.isColdStart },
        messages: [
            { _ in "오늘 해볼 일 하나만 적어볼까요? 작은 일이어도 충분해요." },
            { _ in "완벽한 계획은 나중에 해도 괜찮아요. 오늘 할 일 하나만 적어볼까요?" },
            { _ in "지금 제일 신경 쓰이는 일 하나, 그걸로 첫 타이머를 켜봐요." },
            { _ in "오늘 무슨 할 일 있나요? 메모에 적어두면 다음부터 제가 짚어드려요." },
            { _ in "작은 실행이 완벽한 계획보다 낫습니다." },
        ]
    )

    // MARK: - 오늘 진행

    private static let notStartedWithTask = FocusNudgeRule(
        id: "today.notStartedWithTask",
        tier: .today,
        priority: 75,
        badge: "첫 집중",
        condition: { !$0.isColdStart && $0.todayCompletedCount == 0 && $0.nextTask != nil },
        messages: [
            { context in
                guard let at = context.nextTask?.at,
                      !(context.nextTask?.isOverdue ?? false) else {
                    return "오늘의 첫 집중은 '\(taskTitle(context))'로 시작해볼까요?"
                }

                return "'\(taskTitle(context))'가 \(FocusNudgeFormat.clockTime(at))에 있어요. 조금 미리 시작해두면 마음이 한결 편해질 거예요."
            },
            {
                "'\(taskTitle($0))'부터 가볍게 해봐요. 한 번 시작하면 오늘의 흐름이 생길 거예요."
            },
        ]
    )

    private static let behindYesterday = FocusNudgeRule(
        id: "today.behindYesterday",
        tier: .today,
        priority: 70,
        badge: "오늘의 속도",
        condition: { $0.todayCompletedCount >= 1 && $0.yesterdayCountBySameTime > $0.todayCompletedCount },
        messages: [
            { context in
                let gap = context.yesterdayCountBySameTime - context.todayCompletedCount
                return "어제 이 시각보다 \(gap)회 천천히 가고 있어요. 오늘은 오늘의 속도로 이어가도 괜찮아요."
            },
        ]
    )

    private static let overdueTasks = FocusNudgeRule(
        id: "today.overdueTasks",
        tier: .today,
        priority: 68,
        badge: "다시 이어가기",
        condition: { $0.overdueTaskCount >= 1 },
        messages: [
            { context in
                if context.overdueTaskCount == 1 {
                    return "예정일이 지난 '\(taskTitle(context))'가 있어요. 오늘 할 수 있는 만큼 다시 이어가볼까요?"
                }
                return "예정일이 지난 할 일이 \(context.overdueTaskCount)개 있어요. '\(taskTitle(context))'부터 하나씩 다시 살펴볼까요?"
            },
        ]
    )

    /// 기록은 쌓이는데 타이머와 함께한 시간이 적은 상태. 기록 비율을 알려 다음 집중에서 타이머 사용을 제안한다.
    private static let lowCoverage = FocusNudgeRule(
        id: "today.lowCoverage",
        tier: .today,
        priority: 65,
        badge: "타이머와 함께",
        condition: { ($0.coverageRatio ?? 1) < 0.3 },
        messages: [
            { context in
                let ratio = context.coverageRatio ?? 0
                return "오늘 \(FocusNudgeFormat.duration(context.observedSeconds))을 기록했고, 그중 \(FocusNudgeFormat.percent(ratio))은 타이머와 함께했어요. 다음 집중은 타이머와 함께 시작해볼까요?"
            },
        ]
    )

    private static let firstSessionDone = FocusNudgeRule(
        id: "today.firstSessionDone",
        tier: .today,
        priority: 55,
        badge: "첫 집중 완료",
        condition: { $0.todayCompletedCount == 1 },
        messages: [
            { _ in "오늘의 첫 집중을 마쳤어요. 잘 시작했어요. 잠시 쉬어가도 좋아요." },
            { context in "\(FocusNudgeFormat.duration(context.todayFocusSeconds)) 집중했어요. 오늘의 첫걸음을 잘 내디뎠어요." },
        ]
    )

    private static let aheadOfYesterday = FocusNudgeRule(
        id: "today.aheadOfYesterday",
        tier: .today,
        priority: 50,
        badge: "좋은 흐름",
        condition: {
            $0.todayCompletedCount > $0.yesterdayCountBySameTime && $0.yesterdayCompletedCount > 0
        },
        messages: [
            { context in
                let gap = context.todayCompletedCount - context.yesterdayCountBySameTime
                return "어제 이 시각보다 \(gap)회 더 집중했어요. 오늘의 좋은 흐름을 편안하게 이어가봐요."
            },
        ]
    )

    // MARK: - 개인화

    /// 같은 미완료 이유가 반복되면 최근 회고의 흐름을 알려주고 다음 시도를 제안한다.
    private static let repeatedIncompleteReason = FocusNudgeRule(
        id: "personalized.repeatedIncompleteReason",
        tier: .personalized,
        priority: 80,
        badge: "최근의 흐름",
        condition: { $0.topIncompleteReasonCount >= 3 },
        messages: [
            { context in
                guard let reason = context.topIncompleteReason else {
                    return "최근 회고의 흐름을 천천히 살펴보고 있어요."
                }
                return "최근 회고에서 '\(reason.label)'를 \(context.topIncompleteReasonCount)번 선택했어요. \(advice(for: reason))"
            },
        ]
    )

    private static let deepFocusDrop = FocusNudgeRule(
        id: "personalized.deepFocusDrop",
        tier: .personalized,
        priority: 60,
        badge: "몰입 돌아보기",
        condition: {
            ($0.focusedResponseDelta ?? 0)
                <= -FocusReflectionSummary.meaningfulFocusedResponseDelta
        },
        messages: [
            { context in
                let drop = abs(context.focusedResponseDelta ?? 0)
                return "깊게 또는 대체로 집중했다고 답한 회고가 이전보다 \(drop)회 적었어요. 오늘 집중하기 편한 환경을 하나 만들어볼까요?"
            },
        ]
    )

    private static let deepFocusRise = FocusNudgeRule(
        id: "personalized.deepFocusRise",
        tier: .personalized,
        priority: 45,
        badge: "늘어난 몰입 응답",
        condition: {
            ($0.focusedResponseDelta ?? 0)
                >= FocusReflectionSummary.meaningfulFocusedResponseDelta
        },
        messages: [
            { context in
                "깊게 또는 대체로 집중했다고 답한 회고가 이전보다 \(context.focusedResponseDelta ?? 0)회 늘었어요. 요즘 잘 맞았던 방식을 편안하게 이어가봐요."
            },
        ]
    )

    private static let focusedCategory = FocusNudgeRule(
        id: "personalized.focusedCategory",
        tier: .personalized,
        priority: 40,
        badge: "요즘의 몰입",
        condition: { $0.topCategory != nil },
        messages: [
            { context in
                let category = context.topCategory ?? ""
                return "최근 7일에는 \(Constants.categoryEmoji(for: category)) \(category) 영역에서 가장 오래 집중했어요. 요즘 이어가고 있는 흐름이에요."
            },
        ]
    )

    // MARK: - 기본

    private static let fallback = FocusNudgeRule(
        id: "fallback",
        tier: .today,
        priority: 0,
        badge: "오늘 흐름",
        condition: { _ in true },
        messages: [
            { context in
                guard context.todayCompletedCount > 0 else {
                    return "오늘은 떠오르는 일 하나부터 시작해볼까요?"
                }
                return "오늘 \(context.todayCompletedCount)회 · \(FocusNudgeFormat.duration(context.todayFocusSeconds)) 몰입했어요."
            },
        ]
    )

    // MARK: - 문구 조각

    private static func taskTitle(_ context: FocusNudgeContext) -> String {
        context.nextTask?.title ?? "오늘 할 일"
    }

    /// 미완료 이유별 다음 행동 제안. 이유가 추가되면 여기도 같이 채운다.
    private static func advice(for reason: PomodoroIncompleteReason) -> String {
        switch reason {
        case .insufficientTime:
            return "다음에는 집중 시간을 조금 더 여유 있게 잡아볼까요?"
        case .underestimatedScope:
            return "다음에는 할 일을 조금 더 작게 나눠 시작해볼까요?"
        case .continuedForQuality:
            return "시작 전에 이번에 마칠 지점을 가볍게 정해볼까요?"
        case .blocked:
            return "막힌 지점만 작은 조사로 나눠 먼저 살펴볼까요?"
        case .switchedTask:
            return "지금 가장 중요한 일 하나를 골라 먼저 이어가볼까요?"
        case .distracted:
            return "집중을 방해했던 앱이나 알림을 잠시 닫아둘까요?"
        case .externalInterruption:
            return "요청이 조금 덜한 시간에 집중을 잡아봐도 좋아요."
        }
    }
}
