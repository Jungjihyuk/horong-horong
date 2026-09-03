import AppKit
import HorongAI
import HorongAIMLX
import OSLog
import SwiftUI
import UniformTypeIdentifiers
#if canImport(FoundationModels)
import FoundationModels
#endif

/*
 팝오버의 성취 요약과 그 조각들.

 원래 `AchievementViews.swift`(9,854줄) 한 파일에 있었다. 2026-09-03 분할.
 */

struct AchievementSummaryView: View {
    @Environment(\.openWindow) private var openWindow
    let rewardRepository: RewardRepository

    @Environment(AppState.self) private var appState
    @State private var viewModel: AchievementSummaryViewModel
    @State private var hostWindow: NSWindow?

    private let textScale: CGFloat = 0.8

    init(repository: AchievementRepository, rewardRepository: RewardRepository) {
        self.rewardRepository = rewardRepository
        _viewModel = State(initialValue: AchievementSummaryViewModel(repository: repository))
    }

    private var currentWeekStart: Date { viewModel.currentWeekStart }
    private var weeklyGoals: [AchievementGoal] { viewModel.weeklyGoals }

    var body: some View {
        content
            .onAppear { viewModel.reload() }
            // 목표는 성취 창에서 바뀐다. `@Query` 자동 갱신을 대신한다.
            .onReceive(NotificationCenter.default.publisher(for: SwiftDataAchievementRepository.didChangeNotification)) { _ in
                viewModel.reload()
            }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            ScrollView(showsIndicators: true) {
                VStack(spacing: 12) {
                    if weeklyGoals.isEmpty {
                        emptyGoalState
                    } else {
                        ForEach(weeklyGoals) { goal in
                            AchievementGoalSummaryCard(
                                rewardRepository: rewardRepository,
                                goal: goal,
                                textScale: textScale,
                                weekCount: AchievementDataBuilder.goalWeekCount(for: goal, inWeekStarting: currentWeekStart)
                            )
                        }
                    }

                    addGoalButton
                }
                .padding(.trailing, 7)
                .padding(.bottom, 4)
            }
            .popoverScrollbar()
        }
        .configureHostWindow { window in
            hostWindow = window
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 7) {
                    Image(systemName: "target")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(PopoverChrome.accent)
                    Text("이번 주 성취")
                        .font(.system(size: 14.5, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.ink)
                }
                Spacer()
                detailButton(label: "성취 상세")
            }

            Text("\(AchievementDataBuilder.weekRangeText(forWeekStarting: currentWeekStart)) · 목표 \(completedGoalCount)/\(weeklyGoals.count) 달성 · 연결된 메모 \(linkedMemoCount)개")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)
        }
        .padding(.bottom, 2)
    }

    private var emptyGoalState: some View {
        VStack(spacing: 8) {
            Image(systemName: "target")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(PopoverChrome.accent)
            Text("아직 등록된 성취 목표가 없습니다")
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
            Text("메모장에서 만든 할일을 선택해 목표로 묶을 수 있어요.")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 118)
        .popoverCard(padding: 14, radius: 14)
    }

    private var addGoalButton: some View {
        Button {
            openGoalComposer()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                Text("메모로 목표 추가")
            }
            .font(.system(size: 10.5, weight: .bold, design: .rounded))
            .foregroundStyle(PopoverChrome.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(PopoverChrome.surfaceAlt.opacity(0.78), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var completedGoalCount: Int {
        weeklyGoals.filter(\.isComplete).count
    }

    private var linkedMemoCount: Int {
        Set(weeklyGoals.flatMap(\.sourceMemoIDs)).count
    }

    private func detailButton(label: String) -> some View {
        Button {
            openAchievementDetail()
        } label: {
            // 통계 탭의 «상세 보기», 뉴스 탭의 «모든 리포트» 와 같은 크기로 맞춘다.
            HStack(spacing: 3) {
                Text(label)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(PopoverChrome.inkSecondary)
        }
        .buttonStyle(.plain)
    }

    private func openAchievementDetail() {
        HubWindowPresenter.present(
            tab: .achievement,
            appState: appState,
            popoverWindow: hostWindow,
            openWindow: openWindow
        )
    }

    private func openGoalComposer() {
        AchievementDetailLaunchOptions.shared.shouldOpenGoalComposer = true
        openAchievementDetail()
    }
}

@MainActor
@Observable
final class AchievementDetailLaunchOptions {
    static let shared = AchievementDetailLaunchOptions()
    var shouldOpenGoalComposer = false

    private init() {}

    func consumeGoalComposerRequest() -> Bool {
        guard shouldOpenGoalComposer else { return false }
        shouldOpenGoalComposer = false
        return true
    }
}

struct AchievementOverdueBadge: View {
    var dueDateText: String?
    var textScale: CGFloat = 1

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 9 * textScale, weight: .bold))
            Text(dueDateText.map { "기한 지남 · \($0)" } ?? "기한 지남")
                .font(.system(size: 9.5 * textScale, weight: .bold, design: .rounded))
        }
        .foregroundStyle(Color.red.opacity(0.85))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.red.opacity(0.12), in: Capsule())
        .help(dueDateText.map { "마감일 \($0)이 지났어요." } ?? "마감일이 지났어요.")
    }
}

struct AchievementGoalSummaryCard: View {
    let rewardRepository: RewardRepository
    let goal: AchievementGoal
    var textScale: CGFloat = 1
    var weekCount = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 9) {
                Text(goal.emoji)
                    .font(.system(size: 22))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(goal.title)
                            .font(.system(size: scaled(16), weight: .bold, design: .rounded))
                            .foregroundStyle(PopoverChrome.ink)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if goal.isOverdue {
                            AchievementOverdueBadge(dueDateText: goal.dueDateText, textScale: textScale)
                        }
                        if weekCount > 1 {
                            Text("\(weekCount)주째")
                                .font(.system(size: scaled(9.5), weight: .bold, design: .rounded))
                                .foregroundStyle(PopoverChrome.inkSecondary)
                                .monospacedDigit()
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(PopoverChrome.surfaceAlt, in: Capsule())
                                .help("\(weekCount - 1)주 전에 시작해 아직 진행 중이에요.")
                        }
                    }
                    Text("\(goal.cadence) · \(goal.rule)")
                        .font(.system(size: scaled(12), weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)
                AchievementRewardBadge(reward: goal.reward, color: goal.color, textScale: textScale)
            }

            HStack(spacing: 10) {
                AchievementProgressBar(progress: goal.progress, color: goal.color)
                Text("\(goal.done)/\(goal.total)")
                    .font(.system(size: scaled(14), weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(PopoverChrome.ink)
                AchievementGoalRewardAction(goal: goal, rewardRepository: rewardRepository, textScale: textScale)
            }

            if let todo = goal.nextTodo {
                Divider()
                    .overlay(PopoverChrome.divider)
                HStack(spacing: 8) {
                    Image(systemName: todo.status == .done ? "checkmark.circle.fill" : "circle.dashed")
                        .font(.system(size: scaled(15), weight: .bold))
                        .foregroundStyle(todo.status == .done ? goal.color : PopoverChrome.inkTertiary)
                    Text(todo.status == .done ? "최근 증거 · \(todo.text)" : "다음 할일 · \(todo.text)")
                        .font(.system(size: scaled(12.5), weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    if !todo.metaText.isEmpty {
                        Text(todo.metaText)
                            .font(.system(size: scaled(11), weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(PopoverChrome.inkTertiary)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
        }
        .popoverCard(padding: 13, radius: 14)
    }

    private func scaled(_ size: CGFloat) -> CGFloat {
        size * textScale
    }
}

/// 목표 카드 오른쪽에 붙는 배지.
/// 보상 문구·«보상 받기»·«받음» 이 모두 같은 모양을 쓴다.
struct AchievementRewardChip: View {
    let systemImage: String
    let text: String
    let color: Color
    var textScale: CGFloat = 1
    /// 누를 수 있는 배지는 포인터를 올렸을 때만 살짝 진해진다. 평상시 모양은 같다.
    var isHovering: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10 * textScale, weight: .bold))
            Text(text)
                .font(.system(size: 11.5 * textScale, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            color.opacity(isHovering ? 0.32 : 0.18),
            in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous)
        )
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct AchievementRewardBadge: View {
    let reward: AchievementReward
    let color: Color
    var textScale: CGFloat = 1

    var body: some View {
        // 보상 문구를 적지 않았으면 배지를 아예 띄우지 않는다.
        // "보상 없음 대기" 같은 문구는 알려주는 게 없다.
        // 받았는지 여부는 옆의 «보상 받기» 배지가 말해준다.
        if reward.amount != AchievementReward.emptyAmount {
            AchievementRewardChip(
                systemImage: "gift",
                text: reward.amount,
                color: color,
                textScale: textScale
            )
        }
    }
}

struct AchievementProgressBar: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(PopoverChrome.surfaceAlt)
                Capsule()
                    .fill(color)
                    .frame(width: max(8, proxy.size.width * progress))
            }
        }
        .frame(height: 9)
    }
}
