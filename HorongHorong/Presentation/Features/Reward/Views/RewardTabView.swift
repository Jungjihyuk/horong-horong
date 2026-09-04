import SwiftUI

/// 성취 창의 "보상" 탭.
/// 모은 포인트를 호롱불로 보여주고, 보상 목록을 관리하고, 적립·사용 이력을 훑는다.
struct RewardTabView: View {
    /// 달성했지만 아직 보상을 고르지 않은 월간 목표. 이게 있어야 보상을 받을 수 있다.
    /// `AchievementGoal` 이 성취 화면 쪽 타입이라 거기서 만들어 넘겨받는다.
    let unlockedMonthlyGoals: [RewardClaimableGoal]

    @Environment(\.appearanceDensity) private var appearanceDensity
    @State private var viewModel: RewardViewModel

    @State private var showComposer = false
    @State private var editingItem: RewardItem?
    @State private var pendingDeletion: RewardItem?
    @State private var showHistory = false

    init(repository: RewardRepository, unlockedMonthlyGoals: [RewardClaimableGoal] = []) {
        self.unlockedMonthlyGoals = unlockedMonthlyGoals
        _viewModel = State(initialValue: RewardViewModel(repository: repository))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: appearanceDensity.informationMetric(18)) {
            // 이력은 계속 쌓여 화면을 아래로 늘리므로 별도 창으로 뺀다.
            HStack {
                Spacer()
                Button {
                    showHistory = true
                } label: {
                    Label("적립·사용 이력", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(LanternSecondaryButtonStyle())
                .controlSize(.small)
                .fixedSize()
            }

            LanternOilJarView(
                progress: viewModel.progress,
                unlockedGoalTitles: viewModel.unlockedGoals.map(\.title)
            )
            .frame(maxWidth: .infinity)

            if !viewModel.failureMessage.isEmpty {
                Text(viewModel.failureMessage)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.red)
            }

            catalogSection
            trophySection
        }
        // 원장은 성취 화면에서도 바뀐다. 나타날 때마다 다시 읽어야 적립이 반영된다.
        .onAppear {
            viewModel.unlockedMonthlyGoals = unlockedMonthlyGoals
            viewModel.reload()
        }
        .onChange(of: unlockedMonthlyGoals) { _, goals in
            viewModel.unlockedMonthlyGoals = goals
        }
        .onReceive(NotificationCenter.default.publisher(for: SwiftDataRewardRepository.didChangeNotification)) { _ in
            viewModel.reload()
        }
        .sheet(isPresented: $showHistory) {
            RewardHistorySheet(entries: viewModel.entries)
        }
        .sheet(item: Binding(get: { viewModel.unboxed }, set: { if $0 == nil { viewModel.dismissUnboxing() } })) { reward in
            RewardUnboxingOverlay(
                emoji: reward.emoji,
                title: reward.title,
                costPoints: reward.costPoints,
                remainingBalance: reward.remainingBalance
            ) {
                viewModel.dismissUnboxing()
            }
        }
        .sheet(isPresented: $showComposer) {
            RewardItemComposer(item: nil) { title, emoji, cost, note in
                viewModel.addItem(title: title, emoji: emoji, costPoints: cost, note: note)
            }
        }
        .sheet(item: $editingItem) { item in
            RewardItemComposer(item: item) { title, emoji, cost, note in
                viewModel.updateItem(id: item.id, title: title, emoji: emoji, costPoints: cost, note: note)
            }
        }
        .alert("보상을 지울까요?", isPresented: .constant(pendingDeletion != nil)) {
            Button("취소", role: .cancel) { pendingDeletion = nil }
            Button("지우기", role: .destructive) {
                if let pendingDeletion {
                    viewModel.deleteItem(id: pendingDeletion.id)
                }
                pendingDeletion = nil
            }
        } message: {
            Text("지난 사용 이력은 그대로 남습니다.")
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

            if viewModel.visibleItems.isEmpty {
                emptyCard(
                    icon: "gift",
                    title: "아직 정한 보상이 없어요",
                    subtitle: "월간 목표를 달성했을 때 나에게 줄 보상을 미리 정해두세요."
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.visibleItems) { item in
                        catalogRow(item)
                    }
                }
            }
        }
    }

    private func catalogRow(_ item: RewardItem) -> some View {
        let canAfford = viewModel.balance >= item.costPoints

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
                    Text(viewModel.unlockedGoals.isEmpty
                         ? "포인트는 충분해요. 월간 목표를 달성하면 받을 수 있어요"
                         : "지금 받을 수 있어요")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .lineLimit(1)
                } else {
                    Text("\(item.costPoints - viewModel.balance)P 더 모으면 받을 수 있어요")
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

            // 버튼은 항상 자리를 지킨다. 조건에 따라 나타났다 사라지면 줄마다 모양이 달라진다.
            Button("받기") { viewModel.redeem(item) }
                .buttonStyle(LanternPrimaryButtonStyle())
                .controlSize(.small)
                .fixedSize()
                .disabled(!viewModel.canRedeem(item))
                .opacity(viewModel.canRedeem(item) ? 1 : 0.4)
                .help(viewModel.redeemHelpText(item))

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
        if !viewModel.receivedRewards.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    sectionTitle("받은 보상", systemImage: "trophy")
                    Text("\(viewModel.receivedRewards.count)")
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
                    ForEach(viewModel.receivedRewards) { entry in
                        trophyCard(entry)
                    }
                }
            }
        }
    }

    private func trophyCard(_ entry: RewardEntry) -> some View {
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
    let item: RewardItem?
    let onSave: (String, String, Int, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var emoji: String
    @State private var costText: String
    @State private var note: String

    init(item: RewardItem?, onSave: @escaping (String, String, Int, String) -> Void) {
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

// MARK: - 적립·사용 이력 창

/// 이력은 계속 쌓이므로 보상 탭에 눌러두지 않고 별도 창에서 본다.
private struct RewardHistorySheet: View {
    let entries: [RewardEntry]

    @Environment(\.dismiss) private var dismiss

    private var earnedTotal: Int {
        entries.filter { $0.kind == .earn }.reduce(0) { $0 + $1.amount }
    }

    private var spentTotal: Int {
        entries.filter { $0.kind == .spend }.reduce(0) { $0 - $1.amount }
    }

    /// 실패 마감으로 깎인 합. **`spentTotal` 에 섞지 않는다** — 보상을 산 적이 없는데
    /// «쓴 것» 이 쌓이면 이력을 읽을 수 없다. 따로 세지 않으면 «받은 것 − 쓴 것 ≠ 잔액» 이 된다.
    private var penalizedTotal: Int {
        entries.filter { $0.kind == .penalty }.reduce(0) { $0 - $1.amount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("적립·사용 이력")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                Spacer()
                // 깎인 게 없으면 굳이 «놓친 0P» 를 띄우지 않는다.
                Text(
                    penalizedTotal > 0
                        ? "모은 \(earnedTotal)P · 쓴 \(spentTotal)P · 놓친 \(penalizedTotal)P"
                        : "모은 \(earnedTotal)P · 쓴 \(spentTotal)P"
                )
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
            }

            if entries.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.title2)
                        .foregroundStyle(PopoverChrome.inkTertiary)
                    Text("아직 이력이 없어요")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                    Text("주간 목표를 달성하고 «보상 받기»를 누르면 여기에 쌓입니다.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    // 원장은 지워지지 않고 계속 쌓인다.
                    LazyVStack(spacing: 6) {
                        ForEach(entries) { entry in
                            row(entry)
                        }
                    }
                }
                // 항목이 적으면 창도 짧아진다. ScrollView 는 그냥 두면 남는 공간을 다 차지한다.
                .frame(height: min(340, CGFloat(entries.count) * 62))
            }

            HStack {
                Spacer()
                Button("닫기") { dismiss() }
                    .buttonStyle(LanternSecondaryButtonStyle())
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(PopoverChrome.surface)
        .appearanceAccentTint(.popover)
    }

    /// 종류마다 다른 아이콘. **`switch` 로 적는다** — `== .earn` 비교로 두면
    /// 종류를 늘려도 컴파일러가 여기를 짚어 주지 않아 새 종류가 조용히 «선물» 로 그려진다.
    private static func icon(for kind: RewardEntryKind) -> String {
        switch kind {
        case .earn: return "drop.fill"
        case .spend: return "gift.fill"
        case .penalty: return "flame.slash"
        }
    }

    private static func fallbackTitle(for kind: RewardEntryKind) -> String {
        switch kind {
        case .earn: return "포인트 적립"
        case .spend: return "보상 사용"
        case .penalty: return "실패 마감 차감"
        }
    }

    private func row(_ entry: RewardEntry) -> some View {
        let isEarn = entry.kind == .earn

        return HStack(spacing: 10) {
            // 기름 방울은 채운 것, 선물은 받은 것, 꺼진 불꽃은 놓친 것.
            // 위아래 화살표보다 이 화면의 이야기에 맞는다.
            Image(systemName: Self.icon(for: entry.kind))
                .font(.system(size: 12))
                .foregroundStyle(isEarn ? PopoverChrome.accent : PopoverChrome.inkTertiary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.note.isEmpty ? Self.fallbackTitle(for: entry.kind) : entry.note)
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
                .monospacedDigit()
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
}
