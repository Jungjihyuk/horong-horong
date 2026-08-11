import SwiftUI
import SwiftData

/// 성취 창의 "보상" 탭.
/// 모은 포인트를 호롱불로 보여주고, 보상 목록을 관리하고, 적립·사용 이력을 훑는다.
struct RewardTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appearanceDensity) private var appearanceDensity
    @Query(sort: \RewardCatalogItem.sortOrder) private var catalogItems: [RewardCatalogItem]
    @Query(sort: \RewardLedgerEntry.occurredAt, order: .reverse) private var entries: [RewardLedgerEntry]

    @State private var showComposer = false
    @State private var editingItem: RewardCatalogItem?
    @State private var pendingDeletion: RewardCatalogItem?

    private var balance: Int {
        RewardLedger.balance(entries.map(\.snapshot))
    }

    private var pointsToNext: Int? {
        RewardLedger.pointsToNextReward(items: catalogItems.map(\.snapshot), balance: balance)
    }

    /// 기름 높이의 기준은 다음 보상 가격이다. 다 살 수 있으면 가득 채운다.
    private var fillRatio: Double {
        guard let pointsToNext else { return catalogItems.isEmpty ? 0 : 1 }
        return RewardLedger.fillRatio(balance: balance, target: balance + pointsToNext)
    }

    private var visibleItems: [RewardCatalogItem] {
        catalogItems.filter { !$0.isArchived }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: appearanceDensity.informationMetric(18)) {
            LanternOilJarView(balance: balance, pointsToNext: pointsToNext, fillRatio: fillRatio)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

            catalogSection
            historySection
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
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
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
    }

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
