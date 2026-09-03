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
 성취 상세 창.
 
  아직 크다. 탭별로 더 가르는 일은 ViewModel 이전과 함께 한다 —
  지금 가르면 상태 소유가 어디로 갈지 정하지 않은 채 경계만 생긴다.

 원래 `AchievementViews.swift`(9,854줄) 한 파일에 있었다. 2026-09-03 분할.
 */

struct AchievementDetailScreenshotState {
    let tabIdentifier: String
    let weekGoalFilterIdentifier: String?

    init(tabIdentifier: String, weekGoalFilterIdentifier: String? = nil) {
        self.tabIdentifier = tabIdentifier
        self.weekGoalFilterIdentifier = weekGoalFilterIdentifier
    }
}

enum AchievementDetailTab: String, CaseIterable, Identifiable {
    case progress = "진행"
    case journey = "여정"
    case records = "달성 기록"
    case reward = "보상"

    var id: String { rawValue }

    init?(screenshotIdentifier: String) {
        switch screenshotIdentifier.lowercased() {
        case "progress":
            self = .progress
        case "journey":
            self = .journey
        case "records":
            self = .records
        case "reward":
            self = .reward
        default:
            return nil
        }
    }
}

enum AchievementPeriod: String, CaseIterable, Identifiable {
    case week = "주간"
    case month = "월간"

    var id: String { rawValue }
}

/// 달성한 목표에서 보상을 수확하는 버튼.
///
/// 주간 목표는 눌러서 포인트를 쌓고, 월간 목표는 쌓인 포인트로 보상을 고른다.
/// 달성 여부가 파생값이라 버튼 노출만으로는 중복을 못 막는다 — 실제 차단은 `RewardEngine`이 한다.
struct AchievementGoalRewardAction: View {
    let goal: AchievementGoal
    var textScale: CGFloat = 1
    /// 보상 탭으로 데려다주는 동작. 성취 상세 창에서만 넘어온다.
    /// nil 이면(팝오버) 받을 수 있다는 사실만 알린다.
    var onOpenRewardTab: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [RewardLedgerEntry]
    @AppStorage(Constants.AppStorageKey.rewardWeeklyGoalPoints)
    private var weeklyPoints: Int = Constants.defaultRewardWeeklyGoalPoints
    @State private var isHovering = false
    @State private var showRevokeConfirm = false
    @State private var revokeErrorMessage: String?

    private var claimable: RewardClaimableGoal {
        RewardClaimableGoal(
            id: goal.id,
            title: goal.title,
            emoji: goal.emoji,
            cadence: goal.cadence,
            isComplete: goal.isComplete
        )
    }

    private var snapshots: [RewardEntrySnapshot] { entries.map(\.snapshot) }
    private var balance: Int { RewardLedger.balance(snapshots) }
    private var hasClaimed: Bool { RewardLedger.hasClaimed(goalID: goal.id, in: snapshots) }
    private var hasRedeemed: Bool { RewardLedger.hasRedeemed(goalID: goal.id, in: snapshots) }

    private func scaled(_ value: CGFloat) -> CGFloat { value * textScale }

    var body: some View {
        Group {
            if claimable.isWeekly {
                // 이미 받았으면 목표가 미완성으로 되돌아가도 계속 보여준다.
                // 포인트는 그대로 남는데 표시만 사라지면 어디서 온 포인트인지 알 수 없다.
                if hasClaimed {
                    if goal.isComplete {
                        receivedChip
                    } else {
                        // 할일을 잘못 체크해 잠깐 달성이 됐을 수 있다. 되돌릴 길을 열어둔다.
                        revokeButton
                    }
                } else if goal.isComplete {
                    claimButton
                }
            } else if claimable.isMonthly {
                if hasRedeemed {
                    receivedChip
                } else if goal.isComplete {
                    monthlyAction
                }
            }
        }
        .alert("받은 \(claimedPoints)P 를 되돌릴까요?", isPresented: $showRevokeConfirm) {
            Button("취소", role: .cancel) {}
            Button("되돌리기", role: .destructive) { revokeClaim() }
        } message: {
            Text("목표가 다시 미달성 상태가 되었어요. 되돌리면 포인트를 회수하고, 다시 달성했을 때 새로 받을 수 있어요.")
        }
        .alert(
            "되돌릴 수 없어요",
            isPresented: Binding(get: { revokeErrorMessage != nil }, set: { if !$0 { revokeErrorMessage = nil } })
        ) {
            Button("확인", role: .cancel) { revokeErrorMessage = nil }
        } message: {
            Text(revokeErrorMessage ?? "")
        }
    }

    /// 이 목표로 받아둔 포인트.
    private var claimedPoints: Int {
        entries.first { $0.kind == .earn && $0.sourceGoalID == goal.id }?.amount ?? weeklyPoints
    }

    private var revokeButton: some View {
        Button {
            showRevokeConfirm = true
        } label: {
            AchievementRewardChip(
                systemImage: "exclamationmark.triangle.fill",
                text: "받음",
                color: goal.color,
                textScale: textScale,
                isHovering: isHovering
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("목표가 미달성으로 돌아갔어요. 눌러서 받은 포인트를 되돌립니다")
    }

    private func revokeClaim() {
        switch RewardEngine.revokeClaim(goalID: goal.id, in: modelContext) {
        case .success:
            revokeErrorMessage = nil
        case .failure(let error):
            revokeErrorMessage = error.message
        }
    }

    /// 월간 목표를 달성하면 보상을 받을 수 있게 된다. 실제 교환은 보상 탭에서 한다.
    @ViewBuilder
    private var monthlyAction: some View {
        if let onOpenRewardTab {
            Button(action: onOpenRewardTab) {
                AchievementRewardChip(
                    systemImage: "flame.fill",
                    text: "보상 받기",
                    color: goal.color,
                    textScale: textScale,
                    isHovering: isHovering
                )
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .help("모은 \(balance)P로 보상 탭에서 보상을 받습니다")
        } else {
            AchievementRewardChip(
                systemImage: "flame.fill",
                text: "보상 받을 수 있어요",
                color: goal.color,
                textScale: textScale
            )
            .help("성취 창의 보상 탭에서 보상을 받을 수 있어요")
        }
    }

    private var claimButton: some View {
        Button {
            RewardEngine.claim(
                claimable,
                policy: FixedWeeklyRewardPolicy(pointsPerGoal: weeklyPoints),
                in: modelContext
            )
        } label: {
            AchievementRewardChip(
                systemImage: "gift",
                text: "보상 받기 +\(weeklyPoints)P",
                color: goal.color,
                textScale: textScale,
                isHovering: isHovering
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("이 목표의 포인트를 호롱불에 채웁니다")
    }

    private var receivedChip: some View {
        AchievementRewardChip(
            systemImage: "checkmark.circle.fill",
            text: "받음",
            color: goal.color,
            textScale: textScale
        )
    }
}

/// 월간 목표 달성 시 뜨는 보상 선택 시트.
enum AchievementWeekGoalFilter: String, CaseIterable, Identifiable {
    case all = "전체"
    case goal = "목표별"
    /// 아직 끝내지 못한 목표. 예전 이름은 «보상만» 이었는데 보상과는 상관이 없었다.
    case remaining = "남은 것"

    var id: String { rawValue }

    init?(screenshotIdentifier: String) {
        switch screenshotIdentifier.lowercased() {
        case "all":
            self = .all
        case "goal":
            self = .goal
        case "remaining", "reward":
            self = .remaining
        default:
            return nil
        }
    }
}

enum AchievementRecordScope: String, CaseIterable, Identifiable {
    case all = "전체"
    case weekly = "주간"
    case monthly = "월간"

    var id: String { rawValue }
}

struct AchievementRecordMonthGroup: Identifiable {
    let id: String
    let title: String
    let goals: [AchievementGoal]
}

struct AchievementDetailWindow: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appearanceDensity) private var appearanceDensity
    // 섹션 술어는 못 쓴다 — 목표에는 **어떤 섹션의 메모든** 연결할 수 있고,
    // `linkableMemos` 는 이미 연결된 것이면 보관·삭제된 것까지 보여준다.
    //
    // 정렬 키만 편집으로 안 바뀌는 필드로 바꾼다. `updatedAt` 이면 메모를 하나 고칠 때마다
    // fetch 가 무효화돼 이 창이 통째로 재계산된다 — 창이 안 보여도 살아 있으면 돈다.
    // 표시 순서는 소비처가 전부 다시 정한다(피커·타임라인 모두 자체 정렬).
    @Query(sort: \Memo.createdAt, order: .reverse) private var memos: [Memo]
    @Query(sort: \AchievementGoalRecord.updatedAt, order: .reverse) private var goalRecords: [AchievementGoalRecord]
    @Query private var rewardEntries: [RewardLedgerEntry]
    @AppStorage(Constants.AppStorageKey.rewardWeeklyGoalPoints)
    private var rewardWeeklyGoalPoints: Int = Constants.defaultRewardWeeklyGoalPoints
    @AppStorage(Constants.AppStorageKey.achievementJourneyMaxFlagCount)
    private var journeyMaxFlagCount: Int = Constants.defaultAchievementJourneyMaxFlagCount
    @AppStorage(Constants.AppStorageKey.achievementTimelineSortOrder)
    private var timelineSortOrderRaw: String = Constants.defaultAchievementTimelineSortOrder.rawValue
    @State private var launchOptions = AchievementDetailLaunchOptions.shared
    @State private var selectedTab: AchievementDetailTab = .progress
    @State private var selectedPeriod: AchievementPeriod = .week
    @State private var displayedMonth = Date()
    @State private var displayedWeek = Date()
    @State private var selectedGoalID: UUID?
    @State private var selectedWeekGoalFilter: AchievementWeekGoalFilter = .all
    @State private var selectedRecordScope: AchievementRecordScope = .all
    @State private var selectedRoleID = ""
    @State private var showGoalComposer = false
    @State private var managingGoalID: UUID?
    @State private var overdueRescheduleMessage = ""
    @State private var journeyImageRefreshID = UUID()
    @State private var showsJourneyImageOptions = false
    @State private var showsJourneyVisionOptions = false
    @State private var showPersonaVisionComposer = false
    @State private var selectedJourneyVisionID: UUID?
    @State private var selectedJourneyFlagIndex: Int?
    @State private var journeyFlagRefreshID = UUID()
    @State private var visionOrderRefreshID = UUID()
    @State private var visionDragID: UUID?
    @State private var visionDragTranslation: CGFloat = 0
    @State private var visionDragStartIndex = 0
    @State private var visionDragOrder: [UUID] = []

    init(initialScreenshotState: AchievementDetailScreenshotState? = nil) {
        if let tabIdentifier = initialScreenshotState?.tabIdentifier,
           let tab = AchievementDetailTab(screenshotIdentifier: tabIdentifier) {
            _selectedTab = State(initialValue: tab)
        }
        if let filterIdentifier = initialScreenshotState?.weekGoalFilterIdentifier,
           let filter = AchievementWeekGoalFilter(screenshotIdentifier: filterIdentifier) {
            _selectedWeekGoalFilter = State(initialValue: filter)
        }
    }

    private var goals: [AchievementGoal] {
        AchievementDataBuilder.goals(from: goalRecords, memos: memos)
    }

    private var roles: [AchievementRole] {
        AchievementDataBuilder.roles(from: goals)
    }

    private var selectedGoal: AchievementGoal? {
        if let selectedGoalID, let goal = goals.first(where: { $0.id == selectedGoalID }) {
            return goal
        }
        return goals.first
    }

    private var managingGoalRecord: AchievementGoalRecord? {
        guard let managingGoalID else { return nil }
        return goalRecords.first { $0.id == managingGoalID }
    }

    private var selectedWeekGoal: AchievementGoal? {
        if let selectedGoalID, let goal = weeklyGoals.first(where: { $0.id == selectedGoalID }) {
            return goal
        }
        return weeklyGoals.first
    }

    private var visibleWeeklyGoals: [AchievementGoal] {
        switch selectedWeekGoalFilter {
        case .all:
            return weeklyGoals
        case .goal:
            return selectedWeekGoal.map { [$0] } ?? []
        case .remaining:
            return weeklyGoals.filter { !$0.isComplete }
        }
    }

    private var timelineSortOrder: Constants.AchievementTimelineSortOrder {
        Constants.AchievementTimelineSortOrder(rawValue: timelineSortOrderRaw)
            ?? Constants.defaultAchievementTimelineSortOrder
    }

    /// '남은 것' 필터는 목표뿐 아니라 할일 단위로도 미완료만 남긴다.
    private var timelineMemos: [Memo] {
        selectedWeekGoalFilter == .remaining ? memos.filter { !$0.isCompletedValue } : memos
    }

    private var weeklyTimelineTitle: String {
        switch selectedWeekGoalFilter {
        case .all:
            return "전체 주간 목표 흐름"
        case .goal:
            return selectedWeekGoal.map { "\($0.title) 흐름" } ?? "주간 목표 흐름"
        case .remaining:
            return "남은 주간 목표 흐름"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            ZStack(alignment: .trailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: appearanceDensity.informationMetric(14)) {
                        switch selectedTab {
                        case .progress:
                            progressHeader
                            periodContent
                        case .records:
                            recordsContent
                        case .journey:
                            journeyContent
                        case .reward:
                            RewardTabView(unlockedMonthlyGoals: unlockedMonthlyGoals)
                        }
                    }
                    .padding(appearanceDensity.informationMetric(18))
                }
                .background(PopoverChrome.surface)
                .disabled(showGoalComposer)

                if showGoalComposer {
                    Color.white.opacity(0.24)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            closeGoalComposer()
                        }
                        .transition(.opacity)

                    AchievementGoalComposerSheet(
                        memos: AchievementDataBuilder.activeMemos(memos),
                        existingGoals: goals,
                        onClose: closeGoalComposer
                    ) { record, childGoalIDs, newChildTitles in
                        modelContext.insert(record)
                        connectChildGoals(childGoalIDs, to: record)
                        // 컴포저에서 이름만 적어둔 하위 목표는 여기서 실제 레코드로 만든다.
                        for childTitle in newChildTitles {
                            addChildGoal(to: record, title: childTitle, emoji: "")
                        }
                        try modelContext.save()
                        selectedGoalID = record.id
                        selectedRoleID = record.roleName
                    }
                    .frame(maxHeight: .infinity)
                    .shadow(color: Color.black.opacity(0.16), radius: 22, x: -10, y: 0)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .clipped()
        }
        .frame(minWidth: 760, minHeight: 560)
        .appearanceAccentTint(.popover)
        .background(PopoverChrome.surface)
        .sheet(isPresented: Binding(get: { managingGoalID != nil }, set: { isPresented in
            if !isPresented {
                managingGoalID = nil
            }
        })) {
            if let managingGoalRecord {
                AchievementGoalManagementSheet(
                    record: managingGoalRecord,
                    linkedMemoCount: managingGoalRecord.linkedMemoIDs.count,
                    memos: linkableMemos(for: managingGoalRecord),
                    childRecords: childRecords(for: managingGoalRecord),
                    availableChildRecords: linkableChildRecords(for: managingGoalRecord),
                    childCadence: childCadence(for: managingGoalRecord.cadence),
                    onSave: updateGoalRecord,
                    onDelete: deleteGoalRecord,
                    onDetachChild: { detachChildGoal($0, from: managingGoalRecord) }
                )
            } else {
                AchievementEmptyDetailCard(message: "관리할 목표를 찾을 수 없습니다.")
                    .frame(width: 360, height: 160)
                .padding()
            }
        }
        .sheet(isPresented: $showPersonaVisionComposer) {
            AchievementPersonaVisionComposerSheet(
                personas: roles,
                selectedPersonaID: selectedRoleID,
                onClose: {
                    showPersonaVisionComposer = false
                },
                onSave: savePersonaVisionDraft
            )
        }
        .onAppear {
            ensureSelection()
            if launchOptions.consumeGoalComposerRequest() {
                openGoalComposer()
            }
        }
        .onChange(of: goalRecords.count) { _, _ in
            ensureSelection()
        }
        .onChange(of: launchOptions.shouldOpenGoalComposer) { _, shouldOpen in
            if shouldOpen, launchOptions.consumeGoalComposerRequest() {
                openGoalComposer()
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: showGoalComposer)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            AchievementSegmentedPicker(selection: $selectedTab, values: AchievementDetailTab.allCases)
            Spacer()
            Button {
                openGoalComposer()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("목표")
                }
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.accentInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(PopoverChrome.primaryButtonFill, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(PopoverChrome.surfaceAlt)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PopoverChrome.divider)
                .frame(height: PopoverChrome.borderWidth)
        }
    }

    private func openGoalComposer() {
        showGoalComposer = true
    }

    private func closeGoalComposer() {
        showGoalComposer = false
    }

    private var progressHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedPeriod == .week ? "이번 주 목표" : "월간 목표")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                Text("진행 중인 목표와 연결된 할일을 관리합니다.")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
            }

            Spacer(minLength: 10)

            Menu {
                ForEach(AchievementPeriod.allCases) { period in
                    Button {
                        selectedPeriod = period
                    } label: {
                        Label(
                            period.rawValue,
                            systemImage: selectedPeriod == period ? "checkmark" : period == .week ? "calendar.badge.clock" : "calendar"
                        )
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: selectedPeriod == .week ? "calendar.badge.clock" : "calendar")
                        .font(.system(size: 11.5, weight: .bold))
                    Text(selectedPeriod.rawValue)
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(PopoverChrome.inkSecondary)
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous)
                        .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
                )
                .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
            }
            .buttonStyle(.plain)
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
    }

    @ViewBuilder
    private var periodContent: some View {
        switch selectedPeriod {
        case .week:
            weekContent
        case .month:
            monthContent
        }
    }

    private var weekContent: some View {
        VStack(spacing: 14) {
            AchievementPeriodHeader(
                title: AchievementDataBuilder.weekRangeText(forWeekStarting: displayedWeekStart),
                subtitle: isDisplayingCurrentWeek
                    ? "이번 주 목표와 이전 주에서 이어진 목표를 함께 봅니다"
                    : "그 주에 시작했거나 그 주까지 진행 중이던 목표를 봅니다",
                leading: "이전주",
                trailing: "다음주",
                onLeading: {
                    moveDisplayedWeek(by: -1)
                },
                onTrailing: {
                    moveDisplayedWeek(by: 1)
                }
            )
            HStack(spacing: 10) {
                AchievementMetricCard(label: isDisplayingCurrentWeek ? "이번 주 성취" : "주간 성취", value: "\(completedWeeklyGoalCount)/\(weeklyGoals.count)", icon: "target")
                AchievementMetricCard(label: "받을 포인트", value: "\(claimableRewardPoints)P", icon: "gift")
                AchievementMetricCard(label: "연결된 메모", value: "\(weeklyLinkedMemoCount)", icon: "checkmark.seal")
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("성취 타임라인")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(PopoverChrome.ink)
                        AchievementTimelineSortMenu(
                            title: weeklyTimelineTitle,
                            selectedOrder: timelineSortOrder,
                            disablesCompletionOrders: selectedWeekGoalFilter == .remaining,
                            onSelect: { timelineSortOrderRaw = $0.rawValue }
                        )
                    }
                    Spacer()
                    if let selectedWeekGoal {
                        AchievementTimelineFilters(
                            goals: weeklyGoals,
                            selectedGoalID: $selectedGoalID,
                            selectedFilter: $selectedWeekGoalFilter,
                            selectedGoal: selectedWeekGoal
                        )
                    }
                }

                if !visibleWeeklyGoals.isEmpty {
                    overdueMemosBanner
                    AchievementGoalTimelineView(
                        items: AchievementDataBuilder.timeline(
                            for: visibleWeeklyGoals,
                            memos: timelineMemos,
                            weekStarting: displayedWeekStart,
                            sortOrder: timelineSortOrder
                        ),
                        onMoveTodo: moveTimelineMemo,
                        onToggleTodoCompletion: toggleTimelineMemoCompletion
                    )
                } else {
                    AchievementEmptyDetailCard(message: "주간 목표를 추가하면 타임라인이 표시됩니다.")
                }
            }
            .achievementDetailCard()

            if weeklyGoals.isEmpty {
                AchievementEmptyDetailCard(message: "이번 주에 표시할 주간 목표가 없습니다.")
            } else if visibleWeeklyGoals.isEmpty {
                AchievementEmptyDetailCard(message: "조건에 맞는 주간 목표가 없습니다.")
            } else {
                VStack(spacing: 10) {
                    ForEach(visibleWeeklyGoals) { goal in
                        AchievementDetailGoalRow(
                            goal: goal,
                            onAdd: {
                                manageGoal(goal)
                            },
                            onManage: {
                                manageGoal(goal)
                            },
                            onDelete: {
                            deleteGoal(goal)
                            },
                            onOpenRewardTab: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedTab = .reward
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var overdueMemosBanner: some View {
        let overdueMemos = overdueVisibleWeeklyMemos
        if !overdueMemos.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(PopoverChrome.accent)
                        .frame(width: 30, height: 30)
                        .background(PopoverChrome.accentSoft.opacity(0.72), in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text("지난 일정의 미완료 할일 \(overdueMemos.count)개")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(PopoverChrome.ink)
                        Text(overdueMemosPreview(overdueMemos))
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .foregroundStyle(PopoverChrome.inkSecondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 7) {
                        Button {
                            moveOverdueMemosToToday(overdueMemos)
                        } label: {
                            Text("오늘로 이동")
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                .foregroundStyle(PopoverChrome.ink)
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                                .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            distributeOverdueMemosAcrossRemainingWeek(overdueMemos)
                        } label: {
                            Text("남은 요일에 나누기")
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                .foregroundStyle(PopoverChrome.accentInk)
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                                .background(PopoverChrome.primaryButtonFill, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !overdueRescheduleMessage.isEmpty {
                    Text(overdueRescheduleMessage)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                }
            }
            .padding(12)
            .background(PopoverChrome.surfaceAlt.opacity(0.70), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous)
                    .stroke(PopoverChrome.accent.opacity(0.22), lineWidth: PopoverChrome.borderWidth)
            )
        } else if !overdueRescheduleMessage.isEmpty {
            Text(overdueRescheduleMessage)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(PopoverChrome.surfaceAlt.opacity(0.58), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
                .onAppear {
                    clearOverdueRescheduleMessageLater()
                }
        }
    }

    private var overdueVisibleWeeklyMemos: [Memo] {
        let sourceIDs = Set(visibleWeeklyGoals.flatMap(\.sourceMemoIDs))
        let weekStart = currentWeekStart
        return memos
            .filter { memo in
                sourceIDs.contains(memo.id)
                    && !memo.isCompletedValue
                    && !memo.isArchivedValue
                    && !memo.isRecentlyDeleted
                    && (memo.startDate != nil || memo.deadline != nil)
                    && AchievementDataBuilder.memoDate(memo) < weekStart
            }
            .sorted { AchievementDataBuilder.memoDate($0) < AchievementDataBuilder.memoDate($1) }
    }

    private var currentWeekStart: Date {
        Constants.mondayWeekStart(for: Date())
    }

    private var currentWeekEnd: Date {
        Calendar.current.date(byAdding: .day, value: 7, to: currentWeekStart) ?? Date()
    }

    private func overdueMemosPreview(_ memos: [Memo]) -> String {
        let titles = memos.prefix(3).map { AchievementDataBuilder.shortText($0.content, limit: 18) }
        let suffix = memos.count > 3 ? " 외 \(memos.count - 3)개" : ""
        return (titles.joined(separator: ", ") + suffix).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func moveOverdueMemosToToday(_ memos: [Memo]) {
        let today = Calendar.current.startOfDay(for: Date())
        rescheduleOverdueMemos(memos, targetDays: [today], messagePrefix: "오늘로 이동했습니다")
    }

    private func distributeOverdueMemosAcrossRemainingWeek(_ memos: [Memo]) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = max(today, currentWeekStart)
        let daysUntilSunday = max(0, calendar.dateComponents([.day], from: start, to: currentWeekEnd).day ?? 0)
        let targetDays = (0..<max(1, daysUntilSunday)).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start)
        }
        rescheduleOverdueMemos(memos, targetDays: targetDays.isEmpty ? [today] : targetDays, messagePrefix: "남은 요일에 나눠 배치했습니다")
    }

    private func moveTimelineMemo(_ memoID: UUID, to targetDay: Date) {
        guard let memo = memos.first(where: { $0.id == memoID }) else { return }

        overdueRescheduleMessage = ""
        moveMemoSchedule(memo, to: Calendar.current.startOfDay(for: targetDay))
        memo.updatedAt = Date()
        scheduleLocalReminder(for: memo)

        do {
            try modelContext.save()
        } catch {
            overdueRescheduleMessage = "일정 이동에 실패했습니다: \(error.localizedDescription)"
            return
        }

        let dayText = weekdayText(targetDay)
        syncLinkedRemindersIfNeeded([memo], successMessage: "할일을 \(dayText)요일로 이동했습니다.")
    }

    /// 타임라인에서 할일의 완료를 뒤집는다.
    ///
    /// 메모장에서 체크한 것과 같은 결과가 되도록 알림 정리와 미리알림 동기화까지 함께 한다.
    private func toggleTimelineMemoCompletion(_ memoID: UUID) {
        guard let memo = memos.first(where: { $0.id == memoID }) else { return }

        overdueRescheduleMessage = ""
        let previousCompleted = memo.isCompleted
        let previousChangedAt = memo.completionStateChangedAt
        let previousPinned = memo.isPinned

        memo.isCompletedValue.toggle()
        if memo.isCompletedValue {
            // 끝낸 일을 계속 위에 붙여둘 이유가 없다.
            memo.isPinned = false
        }
        memo.updatedAt = Date()
        // 완료·완료 해제에 맞춰 마감 알림을 취소하거나 다시 잡는다.
        scheduleLocalReminder(for: memo)

        do {
            try modelContext.save()
        } catch {
            // 화면과 저장소가 어긋나지 않도록 건드린 값을 전부 되돌린다.
            memo.isCompleted = previousCompleted
            memo.completionStateChangedAt = previousChangedAt
            memo.isPinned = previousPinned
            scheduleLocalReminder(for: memo)
            overdueRescheduleMessage = "완료 표시에 실패했습니다: \(error.localizedDescription)"
            return
        }

        syncLinkedRemindersIfNeeded(
            [memo],
            successMessage: memo.isCompletedValue ? "할일을 완료했습니다." : "완료를 해제했습니다."
        )
    }

    private func rescheduleOverdueMemos(_ memos: [Memo], targetDays: [Date], messagePrefix: String) {
        guard !memos.isEmpty, !targetDays.isEmpty else { return }
        overdueRescheduleMessage = ""

        for (index, memo) in memos.enumerated() {
            let targetDay = targetDays[index % targetDays.count]
            moveMemoSchedule(memo, to: targetDay)
            memo.updatedAt = Date()
            scheduleLocalReminder(for: memo)
        }

        do {
            try modelContext.save()
        } catch {
            overdueRescheduleMessage = "일정 저장에 실패했습니다: \(error.localizedDescription)"
            return
        }

        syncLinkedRemindersIfNeeded(memos, successMessage: "\(memos.count)개를 \(messagePrefix).")
    }

    private func moveMemoSchedule(_ memo: Memo, to targetDay: Date) {
        switch (memo.startDate, memo.deadline) {
        case let (startDate?, deadline?):
            let newStartDate = date(on: targetDay, preservingTimeOf: startDate)
            memo.startDate = newStartDate
            memo.deadline = deadlineDate(on: targetDay, preservingTimeOf: deadline, notBefore: newStartDate)
        case let (startDate?, nil):
            memo.startDate = date(on: targetDay, preservingTimeOf: startDate)
        case let (nil, deadline?):
            memo.deadline = date(on: targetDay, preservingTimeOf: deadline)
        default:
            memo.startDate = date(on: targetDay, preservingTimeOf: Date())
        }
    }

    private func date(on targetDay: Date, preservingTimeOf sourceDate: Date) -> Date {
        let calendar = Calendar.current
        let time = calendar.dateComponents([.hour, .minute, .second], from: sourceDate)
        return calendar.date(
            bySettingHour: time.hour ?? 9,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: targetDay
        ) ?? targetDay
    }

    private func deadlineDate(on targetDay: Date, preservingTimeOf sourceDate: Date, notBefore startDate: Date) -> Date {
        let deadline = date(on: targetDay, preservingTimeOf: sourceDate)
        guard deadline < startDate else { return deadline }
        return Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: targetDay) ?? startDate
    }

    private func weekdayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }

    private func scheduleLocalReminder(for memo: Memo) {
        let identifier = "memo.deadline.\(memo.id.uuidString)"
        guard !memo.isCompletedValue,
              !memo.isArchivedValue,
              !memo.isRecentlyDeleted,
              let fireDate = memo.reminderFireDate else {
            NotificationManager.shared.cancel(identifier: identifier)
            return
        }

        NotificationManager.shared.scheduleMemoReminder(
            identifier: identifier,
            title: memo.reminderNotificationTitle,
            body: AchievementDataBuilder.shortText(memo.content, limit: 40),
            at: fireDate
        )
    }

    private func syncLinkedRemindersIfNeeded(_ memos: [Memo], successMessage: String) {
        let linkedMemos = memos.filter(\.isLinkedToRemindersValue)
        guard !linkedMemos.isEmpty else {
            overdueRescheduleMessage = successMessage
            clearOverdueRescheduleMessageLater()
            return
        }

        overdueRescheduleMessage = "\(successMessage) 미리알림을 동기화하는 중입니다."
        Task { @MainActor in
            var failedCount = 0
            for memo in linkedMemos {
                do {
                    memo.reminderIdentifier = try await MemoReminderLinkService.shared.saveReminder(for: memo)
                    scheduleLocalReminder(for: memo)
                    try? modelContext.save()
                } catch {
                    failedCount += 1
                }
            }

            overdueRescheduleMessage = failedCount == 0
                ? "\(successMessage) 미리알림도 동기화했습니다."
                : "\(successMessage) 미리알림 \(failedCount)개는 동기화하지 못했습니다."
            clearOverdueRescheduleMessageLater()
        }
    }

    private func clearOverdueRescheduleMessageLater() {
        let message = overdueRescheduleMessage
        guard !message.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if overdueRescheduleMessage == message {
                overdueRescheduleMessage = ""
            }
        }
    }

    private var monthContent: some View {
        VStack(spacing: 14) {
            AchievementPeriodHeader(
                title: currentMonthTitle,
                subtitle: "월간 목표와 보상을 한 달 단위로 봅니다",
                leading: "이전달",
                trailing: "다음달",
                onLeading: {
                    moveDisplayedMonth(by: -1)
                },
                onTrailing: {
                    moveDisplayedMonth(by: 1)
                }
            )
            HStack(spacing: 10) {
                AchievementMetricCard(label: "등록 목표", value: "월간: \(monthlyGoals.count)", icon: "arrow.up.right.circle", valueSize: 14.5)
                AchievementMetricCard(label: "완료 목표", value: "월간: \(completedMonthlyGoalCount)", icon: "checkmark.seal", valueSize: 14.5)
                AchievementMetricCard(
                    label: "가장 잘한 목표",
                    value: bestMonthlyGoal?.title ?? "없음",
                    icon: "trophy",
                    valueSize: 14.5,
                    isHighlighted: true,
                    infoDetails: bestGoalInfoDetails
                ) {
                    if let bestMonthlyGoal {
                        manageGoal(bestMonthlyGoal)
                    }
                }
                AchievementMetricCard(
                    label: "흔들린 목표",
                    value: shakyMonthlyGoal?.title ?? "없음",
                    icon: "flag",
                    valueSize: 14.5,
                    infoDetails: shakyGoalInfoDetails
                ) {
                    if let shakyMonthlyGoal {
                        manageGoal(shakyMonthlyGoal)
                    }
                }
            }
            monthlyCalendar
            monthlyGoalList
            weeklyProgress
        }
    }

    private var monthlyGoalList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("월간 목표")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                Spacer()
                Text("\(displayedMonthlyGoals.count)개")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .monospacedDigit()
            }

            if displayedMonthlyGoals.isEmpty {
                Text("월간 목표를 추가하면 여기에 표시됩니다.")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
            } else {
                VStack(spacing: 9) {
                    ForEach(displayedMonthlyGoals) { goal in
                        Button {
                            manageGoal(goal)
                        } label: {
                            HStack(spacing: 9) {
                                Text(goal.emoji)
                                    .font(.system(size: 18))
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(goal.title)
                                            .font(.system(size: 13, weight: .bold, design: .rounded))
                                            .foregroundStyle(PopoverChrome.ink)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(goal.done)/\(goal.total)")
                                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                            .foregroundStyle(PopoverChrome.inkSecondary)
                                            .monospacedDigit()
                                    }
                                    AchievementProgressBar(progress: goal.progress, color: goal.color)
                                }
                                Image(systemName: "pencil")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .foregroundStyle(PopoverChrome.inkTertiary)
                            }
                            .padding(10)
                            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(11), style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(11), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
                            .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(11), style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .achievementDetailCard()
    }

    private var recordsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("달성 기록")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.ink)
                    Text("완료된 주간 목표와 월간 목표를 한 곳에서 봅니다.")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                AchievementMetricCard(label: "달성 목표", value: "\(completedAchievementGoals.count)", icon: "checkmark.seal")
                AchievementMetricCard(label: "주간", value: "\(completedWeeklyGoalCount)", icon: "calendar.badge.clock")
                AchievementMetricCard(label: "월간", value: "\(completedMonthlyGoalCount)", icon: "calendar")
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("완료된 목표")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.ink)
                    Spacer()
                    AchievementSegmentedPicker(selection: $selectedRecordScope, values: AchievementRecordScope.allCases)
                }

                if visibleCompletedAchievementGoals.isEmpty {
                    Text("아직 완료된 주간 또는 월간 목표가 없습니다.")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(completedAchievementGoalGroups) { group in
                            VStack(alignment: .leading, spacing: 9) {
                                Text(group.title)
                                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                    .foregroundStyle(PopoverChrome.inkSecondary)
                                ForEach(group.goals) { goal in
                                    achievementRecordRow(goal)
                                }
                            }
                        }
                    }
                }
            }
            .achievementDetailCard()
        }
    }

    private func achievementRecordRow(_ goal: AchievementGoal) -> some View {
        Button {
            manageGoal(goal)
        } label: {
            HStack(spacing: 10) {
                Text(goal.emoji)
                    .font(.system(size: 20))
                VStack(alignment: .leading, spacing: 5) {
                    Text(goal.title)
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.ink)
                        .lineLimit(1)
                    Text("\(goal.cadence) · \(goal.rule) · \(achievementRecordDateText(goal.recordDate)) 달성")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .lineLimit(1)
                }
                Spacer()
                AchievementRewardBadge(reward: goal.reward, color: goal.color)
            }
            .padding(10)
            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(11), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PopoverChrome.radius(11), style: .continuous)
                    .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
            )
            .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(11), style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var journeyContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            journeyHeader
            roleChips

            if let role = selectedRole {
                let imageURL = AchievementJourneyImageStore.imageURL(for: role.id)
                let selectedVision = selectedJourneyVision(for: role)
                let displayRole = AchievementRole(
                    id: role.id,
                    emoji: role.emoji,
                    name: role.name,
                    vision: journeyVisionText(for: role, selectedVision: selectedVision)
                )
                HStack(alignment: .top, spacing: 14) {
                    journeyPersonaCard(
                        role: displayRole,
                        imageURL: imageURL,
                        showsImageOptions: $showsJourneyImageOptions,
                        onAddImage: {
                        chooseJourneyImage(for: role)
                        },
                        onResetImage: {
                            resetJourneyImage(for: role)
                        }
                    )
                        .frame(width: 270)

                    VStack(alignment: .leading, spacing: 12) {
                        AchievementJourneyScene(
                            role: displayRole,
                            destinationImageURL: imageURL,
                            milestones: journeyFlagSlots
                        )
                        .frame(height: 390)

                        journeyFlagSelectorBar

                        HStack(alignment: .top, spacing: 12) {
                            journeyStatsCard
                            journeyBacklinkCard
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    AchievementEmptyDetailCard(message: "페르소나와 비전을 추가하면 여정이 표시됩니다.")
                    Button {
                        showPersonaVisionComposer = true
                    } label: {
                        Label("페르소나와 비전 추가", systemImage: "plus")
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundStyle(PopoverChrome.accentInk)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(PopoverChrome.primaryButtonFill, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var journeyHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("여정")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                Text("페르소나와 여러 비전을 연결해 목표의 목적지를 관리합니다.")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                journeyVisionSelector
                    .padding(.top, 4)
            }
            Spacer()
            Button {
                showPersonaVisionComposer = true
            } label: {
                Label("페르소나/비전", systemImage: "plus")
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.accentInk)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(PopoverChrome.primaryButtonFill, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var journeyVisionSelector: some View {
        if let role = selectedRole {
            let visions = visionGoals(for: role)
            if !visions.isEmpty {
                Button {
                    showsJourneyVisionOptions.toggle()
                } label: {
                    HStack(spacing: 7) {
                        Text("비전")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundStyle(PopoverChrome.accent)
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(PopoverChrome.accentSoft.opacity(0.72), in: Capsule())
                        Text(selectedJourneyVision(for: role)?.title ?? "비전 선택")
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundStyle(PopoverChrome.ink)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(PopoverChrome.inkTertiary)
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous)
                            .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showsJourneyVisionOptions, arrowEdge: .bottom) {
                    let orderedVisions = visionsInDragOrder(visions)

                    VStack(alignment: .leading, spacing: Constants.achievementVisionRowSpacing) {
                        HStack {
                            Text("비전 선택")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(PopoverChrome.inkTertiary)
                            Spacer(minLength: 8)
                            Text("손잡이를 끌어 순서 변경")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(PopoverChrome.inkTertiary)
                        }

                        ForEach(Array(orderedVisions.enumerated()), id: \.element.id) { index, vision in
                            HStack(spacing: 4) {
                                Button {
                                    selectedJourneyVisionID = vision.id
                                    showsJourneyVisionOptions = false
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: selectedJourneyVisionID == vision.id ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(selectedJourneyVisionID == vision.id ? PopoverChrome.accent : PopoverChrome.inkTertiary)
                                        Text(vision.title)
                                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                            .foregroundStyle(PopoverChrome.ink)
                                            .lineLimit(1)
                                        Spacer(minLength: 8)
                                    }
                                    .padding(.horizontal, 10)
                                    .frame(height: Constants.achievementVisionRowHeight)
                                    .background(
                                        selectedJourneyVisionID == vision.id ? PopoverChrome.accentSoft.opacity(0.68) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous)
                                    )
                                    .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .allowsHitTesting(visionDragID == nil)

                                visionDragHandle(for: vision, at: index, in: role, total: orderedVisions.count)
                            }
                            .background(
                                RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous)
                                    .fill(visionDragID == vision.id ? PopoverChrome.surfaceAlt.opacity(0.9) : Color.clear)
                                    .shadow(color: .black.opacity(visionDragID == vision.id ? 0.18 : 0), radius: 6, x: 0, y: 2)
                            )
                            .offset(y: visionRowOffset(at: index, id: vision.id))
                            .zIndex(visionDragID == vision.id ? 1 : 0)
                        }
                    }
                    .padding(12)
                    .frame(width: 324)
                    .background(PopoverChrome.card)
                }
            }
        }
    }

    /// 드래그 중에는 임시 순서(visionDragOrder)를, 아니면 저장된 순서를 그대로 쓴다.
    private func visionsInDragOrder(_ visions: [AchievementGoal]) -> [AchievementGoal] {
        guard !visionDragOrder.isEmpty else { return visions }
        let byID = Dictionary(visions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let reordered = visionDragOrder.compactMap { byID[$0] }
        guard reordered.count == visions.count else { return visions }
        return reordered
    }

    /// 끌고 있는 행만 손가락을 따라가고, 나머지는 재배열 애니메이션으로 자리를 비켜준다.
    private func visionRowOffset(at index: Int, id: UUID) -> CGFloat {
        guard visionDragID == id else { return 0 }
        let stride = Constants.achievementVisionRowHeight + Constants.achievementVisionRowSpacing
        return visionDragTranslation - CGFloat(index - visionDragStartIndex) * stride
    }

    private func visionDragHandle(for vision: AchievementGoal, at index: Int, in role: AchievementRole, total: Int) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(visionDragID == vision.id ? PopoverChrome.accent : PopoverChrome.inkTertiary)
            .frame(width: 26, height: Constants.achievementVisionRowHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if visionDragID == nil {
                            visionDragID = vision.id
                            visionDragStartIndex = index
                            visionDragOrder = visionGoals(for: role).map(\.id)
                        }
                        visionDragTranslation = value.translation.height

                        let stride = Constants.achievementVisionRowHeight + Constants.achievementVisionRowSpacing
                        let steps = Int((value.translation.height / stride).rounded())
                        let target = min(max(0, visionDragStartIndex + steps), total - 1)
                        guard let current = visionDragOrder.firstIndex(of: vision.id), current != target else { return }
                        withAnimation(.easeInOut(duration: 0.16)) {
                            let moved = visionDragOrder.remove(at: current)
                            visionDragOrder.insert(moved, at: target)
                        }
                    }
                    .onEnded { _ in
                        if !visionDragOrder.isEmpty {
                            AchievementVisionOrderStore.setOrder(visionDragOrder, for: role.id)
                            visionOrderRefreshID = UUID()
                        }
                        visionDragID = nil
                        visionDragTranslation = 0
                        visionDragStartIndex = 0
                        visionDragOrder = []
                    }
            )
    }

    @ViewBuilder
    private var journeyFlagSelectorBar: some View {
        if selectedRole != nil {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("여정 깃발")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.ink)
                    Spacer()
                    Text("월간 목표를 직접 지정합니다")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: min(5, clampedJourneyMaxFlagCount)), spacing: 7) {
                    ForEach(Array(journeyFlagSlots.enumerated()), id: \.offset) { index, goal in
                        Button {
                            selectedJourneyFlagIndex = index
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: goal == nil ? "flag" : "flag.fill")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .foregroundStyle(goal == nil ? PopoverChrome.inkTertiary : PopoverChrome.accent)
                                Text(goal.map { AchievementDataBuilder.shortText($0.title, limit: 12) } ?? "\(index + 1)번")
                                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                    .foregroundStyle(goal == nil ? PopoverChrome.inkSecondary : PopoverChrome.ink)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 9)
                            .frame(height: 32)
                            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous)
                                    .stroke(goal == nil ? PopoverChrome.border : PopoverChrome.accent.opacity(0.34), lineWidth: PopoverChrome.borderWidth)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: Binding(
                            get: { selectedJourneyFlagIndex == index },
                            set: { isPresented in
                                if !isPresented {
                                    selectedJourneyFlagIndex = nil
                                }
                            }
                        ), arrowEdge: .bottom) {
                            journeyFlagPicker(index: index)
                        }
                    }
                }
            }
            .padding(12)
            .background(PopoverChrome.surfaceAlt.opacity(0.68), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous)
                    .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
            )
        }
    }

    private func journeyFlagPicker(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(index + 1)번 깃발")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)

            Button {
                setJourneyFlagGoal(nil, at: index)
            } label: {
                journeyFlagPickerRow(title: "비워두기", systemImage: "flag", isSelected: journeyFlagSlots[index] == nil)
            }
            .buttonStyle(.plain)

            if selectedJourneyMonthlyGoals.isEmpty {
                Text("선택할 수 있는 월간 목표가 없습니다.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
            } else {
                ForEach(selectedJourneyMonthlyGoals) { goal in
                    let slots = journeyFlagSlots
                    let isUsedElsewhere = slots.enumerated().contains { $0.offset != index && $0.element?.id == goal.id }
                    Button {
                        setJourneyFlagGoal(goal, at: index)
                    } label: {
                        journeyFlagPickerRow(
                            title: "\(goal.emoji) \(goal.title)",
                            systemImage: "target",
                            isSelected: slots[index]?.id == goal.id,
                            isDisabled: isUsedElsewhere
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isUsedElsewhere)
                }
            }
        }
        .padding(12)
        .frame(width: 300)
        .background(PopoverChrome.card)
    }

    private func journeyFlagPickerRow(title: String, systemImage: String, isSelected: Bool, isDisabled: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isSelected ? PopoverChrome.accent : PopoverChrome.inkTertiary)
            Text(title)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(isDisabled ? PopoverChrome.inkTertiary : PopoverChrome.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            if isDisabled {
                Text("다른 깃발에 지정됨")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(isSelected ? PopoverChrome.accentSoft.opacity(0.68) : Color.clear, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
    }

    private func journeyPersonaCard(
        role: AchievementRole,
        imageURL: URL?,
        showsImageOptions: Binding<Bool>,
        onAddImage: @escaping () -> Void,
        onResetImage: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: PopoverChrome.radius(18), style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.08, green: 0.12, blue: 0.13),
                                Color(red: 0.18, green: 0.24, blue: 0.18),
                                PopoverChrome.accent.opacity(0.18),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 210)
                    .overlay(alignment: .center) {
                        if let imageURL, let image = NSImage(contentsOf: imageURL) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 270, height: 210)
                                .clipped()
                                .overlay(
                                    LinearGradient(
                                        colors: [.clear, .black.opacity(0.56)],
                                        startPoint: .center,
                                        endPoint: .bottom
                                    )
                                )
                        } else {
                            Image("AchievementJourneyDefault")
                                .resizable()
                                .scaledToFill()
                                .frame(width: 270, height: 210)
                                .clipped()
                                .overlay(
                                    LinearGradient(
                                        colors: [.clear, .black.opacity(0.56)],
                                        startPoint: .center,
                                        endPoint: .bottom
                                    )
                                )
                        }
                    }

                Text(role.name)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.16), in: Capsule())
                    .padding(.bottom, 14)
            }
            .frame(height: 210)
            .clipShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(18), style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text("비전")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.accent)
                Text(role.vision.isEmpty ? "비전을 추가하면 여정의 목적지로 표시됩니다." : role.vision)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button {
                    // TODO: AI 이미지 생성 연동 시 실제 생성 플로우로 연결합니다.
                } label: {
                    Text("AI 이미지 생성")
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .disabled(true)
                .achievementJourneyActionStyle(isPrimary: true)

                if imageURL == nil {
                    Button {
                        onAddImage()
                    } label: {
                        Text("이미지 추가")
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .achievementJourneyActionStyle(isPrimary: false)
                } else {
                    Button {
                        showsImageOptions.wrappedValue.toggle()
                    } label: {
                        Text("이미지 변경")
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .achievementJourneyActionStyle(isPrimary: false)
                    .popover(isPresented: showsImageOptions, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 6) {
                            Button {
                                showsImageOptions.wrappedValue = false
                                onAddImage()
                            } label: {
                                Label("이미지 변경", systemImage: "photo")
                            }
                            .buttonStyle(.plain)

                            Button {
                                showsImageOptions.wrappedValue = false
                                onResetImage()
                            } label: {
                                Label("기본 이미지로 되돌리기", systemImage: "arrow.counterclockwise")
                            }
                            .buttonStyle(.plain)
                        }
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .padding(12)
                        .background(PopoverChrome.card)
                    }
                }
            }

            Text("AI 생성은 임시 비활성화 상태입니다.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
        }
        .achievementDetailCard()
    }

    private var journeyStatsCard: some View {
        return VStack(alignment: .leading, spacing: 11) {
            Text("비전 연결 현황")
                .font(.system(size: 14.5, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)

            HStack(spacing: 10) {
                AchievementJourneyStat(label: "월간 목표", value: "\(selectedJourneyMonthlyGoals.count)")
                AchievementJourneyStat(label: "연결된 일", value: "\(journeyLinkedMemos.count)")
                AchievementJourneyStat(label: "완료한 일", value: "\(journeyLinkedMemos.filter(\.isCompletedValue).count)")
            }

            let remainingGoals = journeyRemainingMonthlyGoals
            let completedGoals = journeyCompletedMonthlyGoals

            let displayCompleted = Array(completedGoals.prefix(2))
            let displayRemaining = Array(remainingGoals.prefix(3))

            if !completedGoals.isEmpty {
                journeyGoalSectionHeader(title: "지나온 월간 목표 (완료)", count: completedGoals.count)
                ForEach(displayCompleted) { goal in
                    journeyCompletedGoalRow(goal)
                }
                if completedGoals.count > 2 {
                    Text("+ \\(completedGoals.count - 2)개의 목표 더보기")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .padding(.horizontal, 4)
                        .padding(.top, 2)
                }
            }

            if !remainingGoals.isEmpty {
                journeyGoalSectionHeader(title: "이동 중인 월간 목표 (진행중)", count: remainingGoals.count)
                ForEach(displayRemaining) { goal in
                    journeyRemainingGoalRow(goal)
                }
                if remainingGoals.count > 3 {
                    Text("+ \\(remainingGoals.count - 3)개의 목표 더보기")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .padding(.horizontal, 4)
                        .padding(.top, 2)
                }
            }

            if remainingGoals.isEmpty && completedGoals.isEmpty {
                Text("선택한 비전에 연결된 월간 목표가 없습니다.")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .achievementDetailCard()
    }

    private var journeyBacklinkCard: some View {
        let recentMemos = Array(journeyLinkedMemos.prefix(4))

        return VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("최근 연결된 일")
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                Spacer()
                Text("\(recentMemos.count)")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .monospacedDigit()
            }

            if recentMemos.isEmpty {
                Text("선택한 비전의 월간 목표와 연결된 일이 없습니다.")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
            } else {
                ForEach(recentMemos, id: \.id) { memo in
                    HStack(spacing: 9) {
                        Circle()
                            .fill(memo.isCompletedValue ? PopoverChrome.accent : Color.blue)
                            .frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(AchievementDataBuilder.shortText(memo.content, limit: 28))
                                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                .foregroundStyle(PopoverChrome.ink)
                                .lineLimit(1)
                            Text(AchievementDataBuilder.todoMetaText(for: memo))
                                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                .foregroundStyle(PopoverChrome.inkTertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .achievementDetailCard()
    }

    private var roleChips: some View {
        HStack(spacing: 8) {
            ForEach(roles) { role in
                Button {
                    selectedRoleID = role.id
                    selectedJourneyVisionID = selectedJourneyVision(for: role)?.id
                    selectedGoalID = goals.first(where: { $0.roleName == role.id })?.id ?? selectedGoalID
                } label: {
                    HStack(spacing: 7) {
                        Text(role.emoji)
                        Text(role.name)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                        Text("\(visionGoals(for: role).count)")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(PopoverChrome.surfaceAlt.opacity(0.9), in: Capsule())
                    }
                    .foregroundStyle(selectedRoleID == role.id ? PopoverChrome.accentInk : PopoverChrome.inkSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(selectedRoleID == role.id ? PopoverChrome.accent : PopoverChrome.card, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func journeyGoalSectionHeader(title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
            Text("\(count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private func journeyRemainingGoalRow(_ goal: AchievementGoal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(goal.title)
                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
                .lineLimit(2)
            AchievementProgressBar(progress: goal.progress, color: goal.color)
            Text(journeyProgressCaption(for: goal))
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
                .lineLimit(1)
            
            journeyChipChildren(for: goal)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous))
    }

    private func journeyCompletedGoalRow(_ goal: AchievementGoal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(PopoverChrome.accent)
                Text(goal.title)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text("\(goal.done)/\(goal.total)")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .monospacedDigit()
            }
            journeyChipChildren(for: goal)
        }
        .padding(12)
        .background(PopoverChrome.surfaceAlt.opacity(0.5), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous))
    }

    @ViewBuilder
    private func journeyChipChildren(for goal: AchievementGoal) -> some View {
        let wGoals = goals.filter { $0.cadence == "주간" && $0.monthGoal == goal.title }
        let wGoalMemoIDs = Set(wGoals.flatMap { $0.sourceMemoIDs })
        let directMemos = linkedMemos(for: goal).filter { !wGoalMemoIDs.contains($0.id) }

        if !wGoals.isEmpty || !directMemos.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(wGoals) { wg in
                        HStack(spacing: 4) {
                            Image(systemName: isJourneyGoalComplete(wg) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(isJourneyGoalComplete(wg) ? PopoverChrome.accent : PopoverChrome.inkTertiary)
                            Text(wg.title)
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .foregroundStyle(PopoverChrome.inkSecondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(PopoverChrome.card, in: Capsule())
                        .overlay(Capsule().stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
                    }
                    ForEach(directMemos) { memo in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(memo.isCompletedValue ? PopoverChrome.accent : Color.blue)
                                .frame(width: 4, height: 4)
                            Text(AchievementDataBuilder.shortText(memo.content, limit: 15))
                                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                .foregroundStyle(PopoverChrome.inkTertiary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(PopoverChrome.card, in: Capsule())
                        .overlay(Capsule().stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
                    }
                }
            }
        }
    }

    private func linkedMemos(for goal: AchievementGoal) -> [Memo] {
        let ids = Set(goal.sourceMemoIDs)
        return memos.filter { ids.contains($0.id) }
            .sorted { AchievementDataBuilder.memoDate($0) > AchievementDataBuilder.memoDate($1) }
    }

    private func journeyProgressCaption(for goal: AchievementGoal) -> String {
        let progressTarget = goal.cadence == "월간" ? "연결된 주간 목표 진행" : "연결된 일 진행"
        return "\(goal.done)/\(goal.total) · \(progressTarget)"
    }

    private var selectedRole: AchievementRole? {
        roles.first { $0.id == selectedRoleID } ?? roles.first
    }

    private func visionGoals(for role: AchievementRole) -> [AchievementGoal] {
        _ = visionOrderRefreshID
        let sorted = goals
            .filter { $0.cadence == "비전" && $0.roleName == role.id }
            .sorted { lhs, rhs in
                if lhs.recordDate == rhs.recordDate {
                    return lhs.title < rhs.title
                }
                return lhs.recordDate > rhs.recordDate
            }

        // 사용자가 지정한 순서를 먼저 배치하고, 새로 생긴 비전은 뒤에 붙인다.
        let storedOrder = AchievementVisionOrderStore.order(for: role.id)
        guard !storedOrder.isEmpty else { return sorted }
        let rank = Dictionary(
            storedOrder.enumerated().map { ($0.element, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        return sorted.enumerated().sorted { lhs, rhs in
            let lhsRank = rank[lhs.element.id] ?? Int.max
            let rhsRank = rank[rhs.element.id] ?? Int.max
            if lhsRank == rhsRank {
                return lhs.offset < rhs.offset
            }
            return lhsRank < rhsRank
        }
        .map(\.element)
    }

    private func selectedJourneyVision(for role: AchievementRole) -> AchievementGoal? {
        let visions = visionGoals(for: role)
        if let selectedJourneyVisionID,
           let selected = visions.first(where: { $0.id == selectedJourneyVisionID }) {
            return selected
        }
        return visions.first
    }

    private var selectedRoleGoals: [AchievementGoal] {
        guard let role = selectedRole else { return [] }
        return goals.filter { $0.roleName == role.id && $0.cadence != "역할" }
    }

    private var selectedJourneyMonthlyGoals: [AchievementGoal] {
        guard let role = selectedRole else { return [] }
        let selectedVision = selectedJourneyVision(for: role)
        let visionKeys = [
            selectedVision?.title,
            selectedVision?.vision,
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        return goals.filter { goal in
            guard goal.roleName == role.id, goal.cadence == "월간" else { return false }
            guard !visionKeys.isEmpty else { return true }
            let goalVision = goal.vision.trimmingCharacters(in: .whitespacesAndNewlines)
            return visionKeys.contains(goalVision)
        }
    }

    private var clampedJourneyMaxFlagCount: Int {
        min(max(journeyMaxFlagCount, Constants.achievementJourneyMaxFlagCountRange.lowerBound), Constants.achievementJourneyMaxFlagCountRange.upperBound)
    }

    private var journeyFlagStorageKey: String? {
        guard let role = selectedRole else { return nil }
        let visionID = selectedJourneyVision(for: role)?.id.uuidString ?? "none"
        return "\(role.id)|\(visionID)"
    }

    private var journeyFlagSlots: [AchievementGoal?] {
        _ = journeyFlagRefreshID
        guard let key = journeyFlagStorageKey else {
            return Array(repeating: nil, count: clampedJourneyMaxFlagCount)
        }
        let storedIDs = AchievementJourneyFlagStore.goalIDs(for: key, maxCount: clampedJourneyMaxFlagCount)
        let goalsByID = Dictionary(uniqueKeysWithValues: selectedJourneyMonthlyGoals.map { ($0.id, $0) })
        var usedIDs = Set<UUID>()
        var slots = storedIDs.map { id -> AchievementGoal? in
            guard let goal = id.flatMap({ goalsByID[$0] }) else { return nil }
            return usedIDs.insert(goal.id).inserted ? goal : nil
        }
        while slots.count < clampedJourneyMaxFlagCount {
            slots.append(nil)
        }
        let validSlots = Array(slots.prefix(clampedJourneyMaxFlagCount))

        return validSlots.enumerated().sorted {
            let lhsGoal = $0.element
            let rhsGoal = $1.element
            let lhsComplete = lhsGoal.map { isJourneyGoalComplete($0) } ?? false
            let rhsComplete = rhsGoal.map { isJourneyGoalComplete($0) } ?? false
            
            if lhsComplete != rhsComplete {
                return lhsComplete
            }
            if (lhsGoal != nil) != (rhsGoal != nil) {
                return lhsGoal != nil
            }
            return $0.offset < $1.offset
        }.map { $0.element }
    }

    private func setJourneyFlagGoal(_ goal: AchievementGoal?, at index: Int) {
        guard let key = journeyFlagStorageKey else { return }
        AchievementJourneyFlagStore.setGoalID(goal?.id, at: index, for: key, maxCount: clampedJourneyMaxFlagCount)
        selectedJourneyFlagIndex = nil
        journeyFlagRefreshID = UUID()
    }

    private func journeyVisionText(for role: AchievementRole, selectedVision: AchievementGoal?) -> String {
        if let selectedVision {
            let selectedVisionText = selectedVision.vision.trimmingCharacters(in: .whitespacesAndNewlines)
            return selectedVisionText.isEmpty ? selectedVision.title : selectedVisionText
        }

        let roleVision = role.vision.trimmingCharacters(in: .whitespacesAndNewlines)
        if !roleVision.isEmpty {
            return roleVision
        }

        let roleGoals = goals.filter { $0.roleName == role.id }
        let matchingVisionGoal = roleGoals.first { $0.cadence == "비전" }
        let linkedVisionText = [
            matchingVisionGoal?.vision,
            matchingVisionGoal?.title,
            roleGoals.first { !$0.vision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?.vision,
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
        if let linkedVisionText {
            return linkedVisionText
        }

        let allVisionGoals = goals.filter { $0.cadence == "비전" }
        if allVisionGoals.count == 1 {
            let onlyVision = allVisionGoals[0]
            return onlyVision.vision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? onlyVision.title
                : onlyVision.vision
        }

        return ""
    }

    /// 여정 깃발에 지정된 순서를 우선하고, 지정되지 않은 목표는 뒤에 붙인다.
    private var journeyMonthlyGoalsInJourneyOrder: [AchievementGoal] {
        let flagOrder = Dictionary(
            journeyFlagSlots.enumerated().compactMap { index, goal in
                goal.map { ($0.id, index) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        return selectedJourneyMonthlyGoals.sorted { lhs, rhs in
            let lhsComplete = isJourneyGoalComplete(lhs)
            let rhsComplete = isJourneyGoalComplete(rhs)
            
            if lhsComplete != rhsComplete {
                return lhsComplete
            }
            
            let lhsOrder = flagOrder[lhs.id] ?? Int.max
            let rhsOrder = flagOrder[rhs.id] ?? Int.max
            if lhsOrder == rhsOrder {
                return lhs.title < rhs.title
            }
            return lhsOrder < rhsOrder
        }
    }

    private func isJourneyGoalComplete(_ goal: AchievementGoal) -> Bool {
        goal.total > 0 && goal.done >= goal.total
    }

    private var journeyRemainingMonthlyGoals: [AchievementGoal] {
        journeyMonthlyGoalsInJourneyOrder.filter { !isJourneyGoalComplete($0) }
    }

    private var journeyCompletedMonthlyGoals: [AchievementGoal] {
        journeyMonthlyGoalsInJourneyOrder.filter { isJourneyGoalComplete($0) }
    }

    private var selectedRoleLinkedMemos: [Memo] {
        let ids = Set(selectedRoleGoals.flatMap(\.sourceMemoIDs))
        return memos
            .filter { ids.contains($0.id) }
            .sorted { AchievementDataBuilder.memoDate($0) > AchievementDataBuilder.memoDate($1) }
    }

    private var journeyLinkedMemos: [Memo] {
        guard let role = selectedRole else { return [] }
        let monthlyGoals = selectedJourneyMonthlyGoals
        let monthlyTitles = Set(monthlyGoals.map(\.title))
        let linkedGoalIDs = monthlyGoals.flatMap(\.sourceMemoIDs)
        let linkedWeeklyGoalIDs = goals
            .filter { goal in
                goal.roleName == role.id
                    && goal.cadence == "주간"
                    && goal.monthGoal.map { monthlyTitles.contains($0) } == true
            }
            .flatMap(\.sourceMemoIDs)
        let ids = Set(linkedGoalIDs + linkedWeeklyGoalIDs)

        return memos
            .filter { ids.contains($0.id) }
            .sorted { AchievementDataBuilder.memoDate($0) > AchievementDataBuilder.memoDate($1) }
    }

    private func savePersonaVisionDraft(_ draft: AchievementPersonaVisionDraft) throws {
        let personaName = AchievementDataBuilder.shortText(draft.personaName, limit: 40)
        let visionTitle = AchievementDataBuilder.shortText(draft.visionTitle, limit: 40)
        let visionText = draft.visionText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !goalRecords.contains(where: { $0.cadence == "역할" && $0.title == personaName }) {
            let personaRecord = AchievementGoalRecord(
                title: personaName,
                emoji: draft.personaEmoji,
                cadence: "역할",
                rule: "페르소나 방향 유지",
                targetCount: 1,
                targetValueText: "1개",
                periodText: "계속",
                rewardText: "",
                colorHex: "#E87333",
                roleName: personaName,
                vision: "",
                linkedMemoIDs: []
            )
            modelContext.insert(personaRecord)
        }

        let visionRecord = AchievementGoalRecord(
            title: visionTitle,
            emoji: draft.visionEmoji,
            cadence: "비전",
            rule: "비전 방향 유지",
            targetCount: 1,
            targetValueText: "1개",
            periodText: "장기",
            rewardText: "",
            colorHex: "#7A52D4",
            roleName: personaName,
            vision: visionText.isEmpty ? visionTitle : visionText,
            linkedMemoIDs: []
        )
        modelContext.insert(visionRecord)
        try modelContext.save()

        selectedRoleID = personaName
        selectedJourneyVisionID = visionRecord.id
        selectedGoalID = visionRecord.id
        showPersonaVisionComposer = false
    }

    private func chooseJourneyImage(for role: AchievementRole) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "\(role.name) 이미지 선택"
        panel.prompt = "추가"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            _ = try AchievementJourneyImageStore.saveImage(from: url, for: role.id)
            journeyImageRefreshID = UUID()
        } catch {
            overdueRescheduleMessage = "이미지를 추가하지 못했습니다: \(error.localizedDescription)"
            clearOverdueRescheduleMessageLater()
        }
    }

    private func resetJourneyImage(for role: AchievementRole) {
        AchievementJourneyImageStore.removeImage(for: role.id)
        journeyImageRefreshID = UUID()
    }

    private var monthlyCalendar: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        let calendar = Calendar.current
        let range = calendar.range(of: .day, in: .month, for: displayedMonth) ?? 1..<31
        let firstDay = dateForCurrentMonth(day: 1, calendar: calendar)
        let leadingBlankCount = (calendar.component(.weekday, from: firstDay) + 5) % 7
        let month = calendar.component(.month, from: displayedMonth)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(month)월 성취 캘린더")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                Spacer(minLength: 8)
                if !monthCalendarLegendGoals.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(monthCalendarLegendGoals) { goal in
                                AchievementCalendarLegendButton(goal: goal) {
                                    manageGoal(goal)
                                }
                            }
                        }
                        .frame(width: 360, alignment: .trailing)
                    }
                    .frame(width: 360, alignment: .trailing)
                }
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(["월", "화", "수", "목", "금", "토", "일"], id: \.self) { weekday in
                    Text(weekday)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 2)
                }
                ForEach((0..<leadingBlankCount).map { "blank-\($0)" }, id: \.self) { _ in
                    Color.clear
                        .frame(maxWidth: .infinity, minHeight: 38)
                }
                ForEach(Array(range), id: \.self) { day in
                    let dayDate = dateForCurrentMonth(day: day, calendar: calendar)
                    let dayGoals = monthCalendarGoals(on: dayDate, calendar: calendar)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(day)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(calendar.isDateInToday(dayDate) ? PopoverChrome.accent : PopoverChrome.inkSecondary)
                        HStack(spacing: 3) {
                            ForEach(dayGoals.prefix(3)) { goal in
                                Circle().fill(goal.color).frame(width: 6, height: 6)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
                    .padding(6)
                    .background(PopoverChrome.surfaceAlt.opacity(calendar.isDateInToday(dayDate) ? 1 : 0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                }
            }
        }
        .achievementDetailCard()
    }

    private var weeklyProgress: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("주차별 월간 목표 진행률")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
            if measurableMonthlyGoals.isEmpty {
                Text("이번 달에는 진행률을 잴 수 있는 월간 목표가 없어요.")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
            } else {
                HStack(alignment: .bottom, spacing: 14) {
                    ForEach(currentMonthWeekProgress) { weekProgress in
                        VStack(spacing: 5) {
                            GeometryReader { proxy in
                                VStack {
                                    Spacer(minLength: 0)
                                    RoundedRectangle(cornerRadius: PopoverChrome.radius(7), style: .continuous)
                                        .fill(PopoverChrome.accent)
                                        .frame(height: proxy.size.height * weekProgress.progress)
                                }
                            }
                            .frame(width: 30, height: 106)
                            .background(PopoverChrome.surfaceAlt, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(7), style: .continuous))
                            Text("\(weekProgress.week)주")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(PopoverChrome.inkSecondary)
                            Text(weekProgress.percentText)
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .foregroundStyle(PopoverChrome.ink)
                                .monospacedDigit()
                            Text("\(weekProgress.completed)/\(weekProgress.total)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(weekProgress.isCurrent ? PopoverChrome.accent : PopoverChrome.inkTertiary)
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .achievementDetailCard()
    }

    private var monthlyGoals: [AchievementGoal] {
        goals.filter { $0.cadence == "월간" }
    }

    /// 달성한 월간 목표는 호롱불에 불을 붙일 자격이 된다.
    /// 이미 보상을 골랐는지는 원장을 보는 보상 탭이 걸러낸다.
    private var unlockedMonthlyGoals: [RewardClaimableGoal] {
        monthlyGoals.filter(\.isComplete).map(rewardClaimable)
    }

    private var displayedWeekStart: Date {
        AchievementDataBuilder.weekStart(for: displayedWeek)
    }

    private var weeklyGoals: [AchievementGoal] {
        goals.filter { goal in
            goal.cadence == "주간"
                && AchievementDataBuilder.goal(goal, belongsToWeekStarting: displayedWeekStart)
        }
    }

    private var isDisplayingCurrentWeek: Bool {
        displayedWeekStart >= AchievementDataBuilder.weekStart(for: Date())
    }

    private func moveDisplayedWeek(by offset: Int) {
        let calendar = Calendar.current
        guard let moved = calendar.date(byAdding: .weekOfYear, value: offset, to: displayedWeekStart) else { return }
        guard moved <= AchievementDataBuilder.weekStart(for: Date()) else { return }
        displayedWeek = moved
    }

    private var completedAchievementGoals: [AchievementGoal] {
        goals.filter { goal in
            (goal.cadence == "주간" || goal.cadence == "월간") && goal.total > 0 && goal.isComplete
        }
    }

    private var visibleCompletedAchievementGoals: [AchievementGoal] {
        completedAchievementGoals
            .filter { goal in
                switch selectedRecordScope {
                case .all:
                    return true
                case .weekly:
                    return goal.cadence == "주간"
                case .monthly:
                    return goal.cadence == "월간"
                }
            }
            .sorted { lhs, rhs in
                if lhs.recordDate == rhs.recordDate {
                    return lhs.title < rhs.title
                }
                return lhs.recordDate > rhs.recordDate
            }
    }

    private var completedAchievementGoalGroups: [AchievementRecordMonthGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: visibleCompletedAchievementGoals) { goal in
            calendar.dateInterval(of: .month, for: goal.recordDate)?.start ?? calendar.startOfDay(for: goal.recordDate)
        }

        return grouped.keys.sorted(by: >).map { monthStart in
            let goals = (grouped[monthStart] ?? []).sorted { lhs, rhs in
                if lhs.recordDate == rhs.recordDate {
                    return lhs.title < rhs.title
                }
                return lhs.recordDate > rhs.recordDate
            }
            return AchievementRecordMonthGroup(
                id: "\(calendar.component(.year, from: monthStart))-\(calendar.component(.month, from: monthStart))",
                title: achievementRecordMonthTitle(monthStart),
                goals: goals
            )
        }
    }

    private func achievementRecordMonthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월"
        return formatter.string(from: date)
    }

    private func achievementRecordDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일"
        return formatter.string(from: date)
    }

    private var monthCalendarLegendGoals: [AchievementGoal] {
        let calendar = Calendar.current
        let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth)
        return monthlyGoals.filter { goal in
            memos.contains { memo in
                goal.sourceMemoIDs.contains(memo.id)
                    && monthInterval?.contains(AchievementDataBuilder.memoDate(memo)) == true
            }
        }
    }

    private var completedMonthlyGoalCount: Int {
        monthlyGoals.filter(\.isComplete).count
    }

    private var completedWeeklyGoalCount: Int {
        weeklyGoals.filter(\.isComplete).count
    }

    /// 달성했는데 아직 «보상 받기»를 누르지 않은 주간 목표.
    private var unclaimedWeeklyGoals: [AchievementGoal] {
        let snapshots = rewardEntries.map(\.snapshot)
        return weeklyGoals.filter {
            $0.isComplete && !RewardLedger.hasClaimed(goalID: $0.id, in: snapshots)
        }
    }

    /// 지금 눌러서 받을 수 있는 포인트.
    /// 개수에 설정값을 곱하지 않고 적립 정책을 거쳐, 규칙이 바뀌어도 한 곳만 고치면 되게 한다.
    private var claimableRewardPoints: Int {
        let policy = FixedWeeklyRewardPolicy(pointsPerGoal: rewardWeeklyGoalPoints)
        return unclaimedWeeklyGoals.reduce(0) { total, goal in
            total + policy.points(forWeeklyGoal: rewardClaimable(goal))
        }
    }

    private func rewardClaimable(_ goal: AchievementGoal) -> RewardClaimableGoal {
        RewardClaimableGoal(
            id: goal.id,
            title: goal.title,
            emoji: goal.emoji,
            cadence: goal.cadence,
            isComplete: goal.isComplete
        )
    }

    private var weeklyLinkedMemoCount: Int {
        Set(weeklyGoals.flatMap(\.sourceMemoIDs)).count
    }

    /// 이 아래로 떨어지면 흔들린 목표로 본다.
    private static let shakyGoalProgressThreshold = 0.5

    private func goalProgressSummary(_ goal: AchievementGoal) -> String {
        "‘\(goal.title)’ · \(goal.done)/\(goal.total) (\(Int((goal.progress * 100).rounded()))%)"
    }

    private var bestGoalInfoDetails: [String] {
        var details = [
            "이번 달 월간 목표 중 달성률이 가장 높은 목표예요.",
            "달성률이 같으면 더 많이 끝낸 목표를 골라요.",
        ]
        if let bestMonthlyGoal {
            details.append("지금은 \(goalProgressSummary(bestMonthlyGoal))이 1위예요.")
        } else if measurableMonthlyGoals.isEmpty {
            details.append("이번 달에는 진행률을 잴 수 있는 월간 목표가 없어 표시하지 않아요.")
        } else {
            details.append("아직 한 개도 진행한 목표가 없어 표시하지 않아요.")
        }
        return details
    }

    private var shakyGoalInfoDetails: [String] {
        var details = [
            "달성률이 50% 미만인 목표 중 가장 낮은 목표예요.",
            "모든 목표가 50% 이상이면 표시하지 않아요.",
        ]
        if let shakyMonthlyGoal {
            details.append("지금은 \(goalProgressSummary(shakyMonthlyGoal))이 가장 낮아요.")
        } else if measurableMonthlyGoals.isEmpty {
            details.append("이번 달에는 진행률을 잴 수 있는 월간 목표가 없어 표시하지 않아요.")
        } else if !measurableMonthlyGoals.contains(where: { $0.progress < Self.shakyGoalProgressThreshold }) {
            details.append("이번 달 목표가 모두 50% 이상이라 표시하지 않아요.")
        } else {
            details.append("가장 잘한 목표와 같은 목표뿐이라 표시하지 않아요.")
        }
        return details
    }

    /// 화면에 표시 중인 달에 속한 월간 목표.
    /// 만든 달부터 완료한 달까지 표시하므로, 그달에 끝내지 못한 목표는 다음 달로 이월된다.
    private var displayedMonthlyGoals: [AchievementGoal] {
        let monthStart = AchievementMonthlyStats.firstDayOfMonth(for: displayedMonth)
        return monthlyGoals.filter { goal in
            AchievementMonthlyStats.goalBelongs(
                toMonthStarting: monthStart,
                createdAt: goal.createdAt,
                completedAt: goal.total > 0 && goal.isComplete ? goal.recordDate : nil
            )
        }
    }

    /// 진행률을 잴 수 있는(연결된 주간 목표가 있는) 월간 목표만 두 지표의 후보로 삼는다.
    private var measurableMonthlyGoals: [AchievementGoal] {
        displayedMonthlyGoals.filter { $0.total > 0 }
    }

    /// 가장 잘한 목표: 진행한 목표 전체에서 달성률이 가장 높은 것.
    /// 30%·20%·10%처럼 모두 낮아도 그중 최고인 30%를 고른다.
    /// 진행률이 같으면 실제로 더 많이 해낸 목표를 고른다.
    private var bestMonthlyGoal: AchievementGoal? {
        measurableMonthlyGoals
            .filter { $0.done > 0 }
            .max { lhs, rhs in
                if lhs.progress == rhs.progress {
                    return lhs.done < rhs.done
                }
                return lhs.progress < rhs.progress
            }
    }

    /// 흔들린 목표: 달성률이 50% 미만인 목표 중 가장 낮은 것.
    /// 모든 목표가 50% 이상이면 표시하지 않고, 가장 잘한 목표와 겹쳐도 표시하지 않는다.
    /// 진행률이 같으면 남은 개수가 많은 쪽이 더 흔들린 것으로 본다.
    private var shakyMonthlyGoal: AchievementGoal? {
        let candidate = measurableMonthlyGoals
            .filter { $0.progress < Self.shakyGoalProgressThreshold }
            .min { lhs, rhs in
                if lhs.progress == rhs.progress {
                    return (lhs.total - lhs.done) > (rhs.total - rhs.done)
                }
                return lhs.progress < rhs.progress
            }
        guard let candidate, candidate.id != bestMonthlyGoal?.id else { return nil }
        return candidate
    }

    private var currentMonthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월"
        return formatter.string(from: displayedMonth)
    }

    private var currentMonthWeekProgress: [AchievementMonthlyWeekProgress] {
        AchievementMonthlyStats.weekProgress(
            forMonth: displayedMonth,
            goals: measurableMonthlyGoals.map { goal in
                AchievementMonthlyStats.Goal(total: goal.total, completions: completionDates(for: goal))
            }
        )
    }

    /// 목표를 이룬 시점들. 하위 주간 목표가 있으면 그 목표를 끝낸 날, 없으면 연결한 할 일을 끝낸 날이다.
    /// 목록에 보이는 done과 같은 단위라, 마지막 주 값이 목록 합계와 맞는다.
    private func completionDates(for goal: AchievementGoal) -> [Date] {
        let children = goals.filter { $0.cadence == "주간" && $0.monthGoal == goal.title }
        guard children.isEmpty else {
            return children.filter { $0.total > 0 && $0.isComplete }.map(\.recordDate)
        }
        return memos
            .filter { goal.sourceMemoIDs.contains($0.id) && $0.isCompletedValue }
            .map(AchievementDataBuilder.memoDate)
    }

    private func ensureSelection() {
        if selectedGoalID == nil || !goals.contains(where: { $0.id == selectedGoalID }) {
            selectedGoalID = goals.first?.id
        }
        if selectedRoleID.isEmpty || !roles.contains(where: { $0.id == selectedRoleID }) {
            selectedRoleID = roles.first?.id ?? ""
        }
        if let role = selectedRole {
            let visions = visionGoals(for: role)
            if selectedJourneyVisionID == nil || !visions.contains(where: { $0.id == selectedJourneyVisionID }) {
                selectedJourneyVisionID = visions.first?.id
            }
        } else {
            selectedJourneyVisionID = nil
        }
    }

    private func deleteGoal(_ goal: AchievementGoal) {
        guard let record = goalRecords.first(where: { $0.id == goal.id }) else { return }
        deleteGoalRecord(record)
    }

    private func manageGoal(_ goal: AchievementGoal) {
        managingGoalID = goal.id
    }

    private func linkableMemos(for record: AchievementGoalRecord) -> [Memo] {
        let linkedIDs = Set(record.linkedMemoIDs)
        return memos.filter {
            (!$0.isArchivedValue && !$0.isRecentlyDeleted) || linkedIDs.contains($0.id)
        }
    }

    private func childCadence(for cadence: String) -> String? {
        switch cadence {
        case "연간":
            return "월간"
        case "월간":
            return "주간"
        default:
            return nil
        }
    }

    private func childRecords(for record: AchievementGoalRecord) -> [AchievementGoalRecord] {
        guard let childCadence = childCadence(for: record.cadence) else { return [] }
        return goalRecords
            .filter { child in
                guard child.cadence == childCadence else { return false }
                switch record.cadence {
                case "연간":
                    return nonEmpty(child.yearGoal) == record.title
                case "월간":
                    return nonEmpty(child.monthGoal) == record.title
                default:
                    return false
                }
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func linkableChildRecords(for record: AchievementGoalRecord) -> [AchievementGoalRecord] {
        guard let childCadence = childCadence(for: record.cadence) else { return [] }
        return goalRecords
            .filter { child in
                guard child.cadence == childCadence else { return false }
                switch record.cadence {
                case "연간":
                    return nonEmpty(child.yearGoal) != record.title
                case "월간":
                    return nonEmpty(child.monthGoal) != record.title
                default:
                    return false
                }
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func updateGoalRecord(_ record: AchievementGoalRecord, draft: AchievementGoalEditDraft) {
        let oldTitle = record.title
        let newTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)

        record.title = newTitle.isEmpty ? record.title : newTitle
        record.emoji = draft.emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? record.emoji : draft.emoji
        record.rule = draft.rule.trimmingCharacters(in: .whitespacesAndNewlines)
        record.targetCount = max(1, draft.targetCount)
        record.rewardText = draft.rewardText.trimmingCharacters(in: .whitespacesAndNewlines)
        record.dueDate = draft.dueDate
        if let linkedMemoIDs = draft.linkedMemoIDs {
            record.linkedMemoIDs = linkedMemoIDs
            record.targetCount = max(1, linkedMemoIDs.count)
        }
        if let additionalChildGoalIDs = draft.additionalChildGoalIDs, !additionalChildGoalIDs.isEmpty {
            for childID in additionalChildGoalIDs {
                if let child = goalRecords.first(where: { $0.id == childID }) {
                    if record.cadence == "연간" { child.yearGoal = record.title }
                    if record.cadence == "월간" { child.monthGoal = record.title }
                    child.updatedAt = Date()
                }
            }
        }
        record.updatedAt = Date()

        syncGoalTitleReferences(oldTitle: oldTitle, newTitle: record.title, cadence: record.cadence)
        connectDescendantGoals(of: record)
        try? modelContext.save()
        managingGoalID = nil
    }

    private func addChildGoal(to parent: AchievementGoalRecord, title: String, emoji: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let childCadence = childCadence(for: parent.cadence), !trimmedTitle.isEmpty else { return }
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = AchievementGoalRecord(
            title: trimmedTitle,
            emoji: trimmedEmoji.isEmpty ? defaultEmoji(for: childCadence) : String(trimmedEmoji.prefix(1)),
            cadence: childCadence,
            rule: "",
            targetCount: 1,
            targetValueText: nil,
            periodText: defaultPeriodText(for: childCadence),
            rewardText: "",
            colorHex: parent.colorHex,
            roleName: parent.roleName,
            vision: parent.vision,
            yearGoal: childCadence == "월간" ? parent.title : parent.yearGoal,
            quarterGoal: nil,
            monthGoal: childCadence == "주간" ? parent.title : parent.monthGoal,
            linkedMemoIDs: []
        )
        modelContext.insert(record)
        try? modelContext.save()
    }

    private func defaultEmoji(for cadence: String) -> String {
        switch cadence {
        case "연간": return "🏁"
        case "월간": return "📅"
        case "주간": return "🎯"
        default: return "🎯"
        }
    }

    private func defaultPeriodText(for cadence: String) -> String? {
        switch cadence {
        case "연간": return "올해"
        case "월간": return "이번 달"
        case "주간": return "이번 주"
        default: return nil
        }
    }

    private func deleteGoalRecord(_ record: AchievementGoalRecord) {
        let deletedID = record.id
        modelContext.delete(record)
        try? modelContext.save()
        if selectedGoalID == deletedID {
            selectedGoalID = goals.first(where: { $0.id != deletedID })?.id
        }
        if managingGoalID == deletedID {
            managingGoalID = nil
        }
    }

    private func syncGoalTitleReferences(oldTitle: String, newTitle: String, cadence: String) {
        guard oldTitle != newTitle else { return }
        guard !oldTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        for record in goalRecords {
            switch cadence {
            case "역할":
                if record.roleName == oldTitle {
                    record.roleName = newTitle
                    record.updatedAt = Date()
                }
            case "비전":
                if record.vision == oldTitle {
                    record.vision = newTitle
                    record.updatedAt = Date()
                }
            case "연간":
                if record.yearGoal == oldTitle {
                    record.yearGoal = newTitle
                    record.updatedAt = Date()
                }
            case "월간":
                if record.monthGoal == oldTitle {
                    record.monthGoal = newTitle
                    record.updatedAt = Date()
                }
            default:
                break
            }
        }
    }

    /// 부모에서 자식을 떼어낸다. 자식 목표 자체는 남는다.
    private func detachChildGoal(_ child: AchievementGoalRecord, from parent: AchievementGoalRecord) {
        switch parent.cadence {
        case "연간":
            child.yearGoal = nil
        case "월간":
            child.monthGoal = nil
        default:
            return
        }
        child.updatedAt = Date()
        try? modelContext.save()
    }

    private func connectChildGoals(_ childGoalIDs: Set<UUID>, to parent: AchievementGoalRecord) {
        guard !childGoalIDs.isEmpty else { return }

        for child in goalRecords where childGoalIDs.contains(child.id) {
            child.roleName = parent.roleName
            child.vision = parent.vision

            switch parent.cadence {
            case "연간":
                child.yearGoal = parent.title
            case "월간":
                child.yearGoal = parent.yearGoal
                child.quarterGoal = nil
                child.monthGoal = parent.title
            default:
                break
            }

            child.updatedAt = Date()
            connectDescendantGoals(of: child)
        }
    }

    private func connectDescendantGoals(of parent: AchievementGoalRecord) {
        switch parent.cadence {
        case "연간":
            for month in goalRecords where month.cadence == "월간" && nonEmpty(month.yearGoal) == parent.title {
                month.roleName = parent.roleName
                month.vision = parent.vision
                month.yearGoal = parent.title
                month.quarterGoal = nil
                month.updatedAt = Date()
                connectDescendantGoals(of: month)
            }
        case "월간":
            for week in goalRecords where week.cadence == "주간" && nonEmpty(week.monthGoal) == parent.title {
                week.roleName = parent.roleName
                week.vision = parent.vision
                week.yearGoal = parent.yearGoal
                week.quarterGoal = nil
                week.monthGoal = parent.title
                week.updatedAt = Date()
            }
        default:
            break
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func cadenceRank(_ cadence: String) -> Int {
        switch cadence {
        case "연간": return 0
        case "월간": return 1
        case "주간": return 2
        default: return 3
        }
    }

    private func dateForCurrentMonth(day: Int, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month], from: displayedMonth)
        components.day = day
        return calendar.date(from: components) ?? displayedMonth
    }

    private func moveDisplayedMonth(by monthOffset: Int) {
        let calendar = Calendar.current
        let monthStart = calendar.dateInterval(of: .month, for: displayedMonth)?.start ?? displayedMonth
        if let nextMonth = calendar.date(byAdding: .month, value: monthOffset, to: monthStart) {
            displayedMonth = nextMonth
        }
    }

    private func monthCalendarGoals(on date: Date, calendar: Calendar) -> [AchievementGoal] {
        monthlyGoals.filter { goal in
            memos.contains { memo in
                goal.sourceMemoIDs.contains(memo.id)
                    && calendar.isDate(AchievementDataBuilder.memoDate(memo), inSameDayAs: date)
            }
        }
    }

}
