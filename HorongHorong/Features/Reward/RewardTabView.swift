import SwiftUI
import SwiftData

/// 성취 창의 "보상" 탭.
/// 모은 포인트를 호롱불로 보여주고, 보상 목록을 관리하고, 적립·사용 이력을 훑는다.
struct RewardTabView: View {
    /// 달성했지만 아직 보상을 고르지 않은 월간 목표. 이게 있어야 보상을 받을 수 있다.
    /// `AchievementGoal`이 file-private 타입이라 성취 화면에서 만들어 넘겨받는다.
    var unlockedMonthlyGoals: [RewardClaimableGoal] = []

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appearanceDensity) private var appearanceDensity
    @Query(sort: \RewardCatalogItem.sortOrder) private var catalogItems: [RewardCatalogItem]
    @Query(sort: \RewardLedgerEntry.occurredAt, order: .reverse) private var entries: [RewardLedgerEntry]

    @State private var showComposer = false
    @State private var editingItem: RewardCatalogItem?
    @State private var pendingDeletion: RewardCatalogItem?
    @State private var unboxing: UnboxedReward?
    @State private var failureMessage = ""

    /// 개봉 연출에 넘길 결과. 원장은 이미 기록된 뒤다.
    private struct UnboxedReward: Identifiable {
        let id = UUID()
        let emoji: String
        let title: String
        let costPoints: Int
        let remainingBalance: Int
    }

    private var balance: Int {
        RewardLedger.balance(entries.map(\.snapshot))
    }

    private var progress: RewardProgress {
        RewardLedger.progress(balance: balance, items: catalogItems.map(\.snapshot))
    }

    private var visibleItems: [RewardCatalogItem] {
        catalogItems.filter { !$0.isArchived }
    }

    /// 아직 보상을 고르지 않은 달성 목표.
    private var unlockedGoals: [RewardClaimableGoal] {
        let snapshots = entries.map(\.snapshot)
        return unlockedMonthlyGoals.filter { !RewardLedger.hasRedeemed(goalID: $0.id, in: snapshots) }
    }

    /// 지금까지 받은 보상. 전리품 선반에 늘어놓는다.
    private var receivedRewards: [RewardLedgerEntry] {
        entries.filter { $0.kind == .spend }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: appearanceDensity.informationMetric(18)) {
            LanternOilJarView(
                progress: progress,
                unlockedGoalTitles: unlockedGoals.map(\.title)
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            if !failureMessage.isEmpty {
                Text(failureMessage)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.red)
            }

            catalogSection
            trophySection
            historySection
        }
        .sheet(item: $unboxing) { reward in
            RewardUnboxingOverlay(
                emoji: reward.emoji,
                title: reward.title,
                costPoints: reward.costPoints,
                remainingBalance: reward.remainingBalance
            ) {
                unboxing = nil
            }
        }
        .sheet(isPresented: $showComposer) {
            RewardItemComposer(item: nil) { title, emoji, cost, note in
                RewardEngine.addCatalogItem(
                    title: title, emoji: emoji, costPoints: cost, note: note, in: modelContext
                )
            }
        }
        .sheet(item: $editingItem) { item in
            RewardItemComposer(item: item) { title, emoji, cost, note in
                item.title = title
                item.emoji = emoji
                item.costPoints = max(1, cost)
                item.note = note
                item.updatedAt = Date()
                try? modelContext.save()
            }
        }
        .alert("보상을 지울까요?", isPresented: .constant(pendingDeletion != nil)) {
            Button("취소", role: .cancel) { pendingDeletion = nil }
            Button("지우기", role: .destructive) {
                if let pendingDeletion {
                    RewardEngine.deleteCatalogItem(pendingDeletion, in: modelContext)
                }
                pendingDeletion = nil
            }
        } message: {
            Text("지난 사용 이력은 그대로 남습니다.")
        }
    }

    /// 달성한 월간 목표 하나를 걸고 보상을 받는다. 원장에 사용 기록이 남고 포인트가 깎인다.
    private func redeem(_ item: RewardCatalogItem) {
        guard let unlocked = unlockedGoals.first else {
            failureMessage = "월간 목표를 달성해야 보상을 받을 수 있어요."
            return
        }
        // 차감 후 잔액은 직접 계산한다.
        // @Query 는 다음 런루프에 갱신되므로 여기서 balance 를 다시 읽으면 옛 값이 나온다.
        let remaining = balance - item.costPoints

        switch RewardEngine.redeem(item: item, forMonthlyGoal: unlocked, in: modelContext) {
        case .success:
            failureMessage = ""
            withAnimation(.easeIn(duration: 0.2)) {
                unboxing = UnboxedReward(
                    emoji: item.emoji,
                    title: item.title,
                    costPoints: item.costPoints,
                    remainingBalance: remaining
                )
            }
        case .failure(let error):
            failureMessage = error.message
        }
    }

    // MARK: - 보상 목록

    private var catalogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("보상 목록", systemImage: "gift")
                Spacer()
                Button {
                    showComposer = true
                } label: {
                    Label("보상 추가", systemImage: "plus")
                }
                .buttonStyle(LanternSecondaryButtonStyle())
                .controlSize(.small)
                .fixedSize()
            }

            if visibleItems.isEmpty {
                emptyCard(
                    icon: "gift",
                    title: "아직 정한 보상이 없어요",
                    subtitle: "월간 목표를 달성했을 때 나에게 줄 보상을 미리 정해두세요."
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(visibleItems) { item in
                        catalogRow(item)
                    }
                }
            }
        }
    }

    private func catalogRow(_ item: RewardCatalogItem) -> some View {
        let canAfford = balance >= item.costPoints

        return HStack(spacing: 10) {
            Text(item.emoji)
                .font(.system(size: 18))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(PopoverChrome.ink)
                    if canAfford {
                        Text("받을 수 있어요")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundStyle(PopoverChrome.accentInk)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(PopoverChrome.accent, in: Capsule())
                    }
                }
                if canAfford {
                    Text(unlockedGoals.isEmpty
                         ? "포인트는 충분해요. 월간 목표를 달성하면 받을 수 있어요"
                         : "지금 받을 수 있어요")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .lineLimit(1)
                } else {
                    Text("\(item.costPoints - balance)P 더 모으면 받을 수 있어요")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .lineLimit(1)
                }
                if !item.note.isEmpty {
                    Text(item.note)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text("\(item.costPoints) P")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(canAfford ? PopoverChrome.accent : PopoverChrome.inkTertiary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous)
                        .fill(canAfford ? PopoverChrome.accentSoft.opacity(0.25) : Color.clear)
                )

            if canAfford {
                Button("받기") { redeem(item) }
                    .buttonStyle(LanternPrimaryButtonStyle())
                    .controlSize(.small)
                    .fixedSize()
                    .disabled(unlockedGoals.isEmpty)
                    .help(unlockedGoals.isEmpty
                          ? "월간 목표를 달성하면 받을 수 있어요"
                          : "달성한 월간 목표를 걸고 이 보상을 받습니다")
            }

            Menu {
                Button("수정") { editingItem = item }
                Button("지우기", role: .destructive) { pendingDeletion = item }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(PopoverChrome.inkSecondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .popoverCard(padding: 11, radius: 12)
        .overlay {
            // 받을 수 있는 보상은 테두리로 한 번 더 구분한다.
            if canAfford {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(PopoverChrome.accent, lineWidth: 1.5)
            }
        }
    }

    // MARK: - 전리품

    @ViewBuilder
    private var trophySection: some View {
        if !receivedRewards.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    sectionTitle("받은 보상", systemImage: "trophy")
                    Text("\(receivedRewards.count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.accentInk)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(PopoverChrome.accent, in: Capsule())
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 116), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(receivedRewards) { entry in
                        trophyCard(entry)
                    }
                }
            }
        }
    }

    private func trophyCard(_ entry: RewardLedgerEntry) -> some View {
        VStack(spacing: 6) {
            Text(Self.trophyEmoji(from: entry.note))
                .font(.system(size: 26))
            Text(Self.trophyTitle(from: entry.note))
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(Self.trophyDateFormatter.string(from: entry.occurredAt))
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous)
                .fill(PopoverChrome.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous)
                .stroke(PopoverChrome.accentSoft.opacity(0.55), lineWidth: 1)
        )
    }

    /// 이력 문구는 "<이모지> <이름>" 형태로 저장된다. 원본 항목이 지워져도 여기서 복원한다.
    private static func trophyEmoji(from note: String) -> String {
        String(note.split(separator: " ", maxSplits: 1).first ?? "🎁")
    }

    private static func trophyTitle(from note: String) -> String {
        let parts = note.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return note }
        return String(parts[1])
    }

    private static let trophyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy. M. d."
        return formatter
    }()

    // MARK: - 이력

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("적립·사용 이력", systemImage: "clock.arrow.circlepath")

            if entries.isEmpty {
                emptyCard(
                    icon: "clock",
                    title: "아직 이력이 없어요",
                    subtitle: "주간 목표를 달성하고 «보상 받기»를 누르면 여기에 쌓입니다."
                )
            } else {
                VStack(spacing: 6) {
                    ForEach(entries) { entry in
                        historyRow(entry)
                    }
                }
            }
        }
    }

    private func historyRow(_ entry: RewardLedgerEntry) -> some View {
        let isEarn = entry.kind == .earn

        return HStack(spacing: 10) {
            Image(systemName: isEarn ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(isEarn ? PopoverChrome.accent : PopoverChrome.inkTertiary)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.note.isEmpty ? (isEarn ? "포인트 적립" : "보상 사용") : entry.note)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                    .lineLimit(1)
                Text(Self.dateFormatter.string(from: entry.occurredAt))
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }

            Spacer(minLength: 8)

            Text(isEarn ? "+\(entry.amount) P" : "\(entry.amount) P")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(isEarn ? PopoverChrome.accent : PopoverChrome.inkSecondary)
        }
        .popoverCard(padding: 10, radius: 11)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy. M. d. (E) HH:mm"
        return formatter
    }()

    // MARK: - 공통 조각

    private func sectionTitle(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(PopoverChrome.accent)
            Text(text)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
        }
    }

    private func emptyCard(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(PopoverChrome.inkTertiary)
            Text(title)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)
            Text(subtitle)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .popoverCard()
    }
}

// MARK: - 보상 추가·수정 시트

private struct RewardItemComposer: View {
    let item: RewardCatalogItem?
    let onSave: (String, String, Int, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var emoji: String
    @State private var costText: String
    @State private var note: String

    init(item: RewardCatalogItem?, onSave: @escaping (String, String, Int, String) -> Void) {
        self.item = item
        self.onSave = onSave
        _title = State(initialValue: item?.title ?? "")
        _emoji = State(initialValue: item?.emoji ?? "🎁")
        _costText = State(initialValue: String(item?.costPoints ?? 30))
        _note = State(initialValue: item?.note ?? "")
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var cost: Int {
        Int(costText.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    private var canSave: Bool {
        !trimmedTitle.isEmpty && cost > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(item == nil ? "보상 추가" : "보상 수정")
                .font(.system(size: 15, weight: .bold, design: .rounded))

            HStack(spacing: 8) {
                TextField("🎁", text: $emoji)
                    .frame(width: 46)
                    .multilineTextAlignment(.center)
                TextField("보상 이름 (예: 좋아하는 카페 가기)", text: $title)
            }
            .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Text("필요 포인트")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                TextField("30", text: $costText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Text("P")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                Spacer()
            }

            TextField("메모 (선택)", text: $note)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("취소") { dismiss() }
                    .buttonStyle(LanternSecondaryButtonStyle())
                Button(item == nil ? "추가" : "저장") {
                    onSave(trimmedTitle, emoji.isEmpty ? "🎁" : emoji, cost, note.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .buttonStyle(LanternPrimaryButtonStyle())
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(PopoverChrome.surface)
    }
}
