import SwiftUI

/// 할 일 상세의 «미리알림 · 분류» 카드.
///
/// 목록을 드롭다운이 아니라 칩으로 늘어놓는다 — 고를 목록이 대여섯 개뿐이라
/// 메뉴를 여는 한 번의 클릭이 순수한 손해다. 개수가 늘면 `TodoChipFlow` 가 줄을 바꾼다.
struct TodoReminderCard: View {
    let isLinked: Bool
    let isEditable: Bool
    let lists: [ReminderListOption]
    let selectedListID: String?
    let startDate: Date?
    let today: Date
    let statusMessage: String
    let swatch: (String) -> ReminderListSwatch
    let onToggleLink: () -> Void
    let onSelectList: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            headerRow

            if isLinked {
                if lists.isEmpty {
                    Text("미리알림 목록을 불러오는 중…")
                        .font(.system(size: 11.5, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                } else {
                    TodoChipFlow(spacing: 6) {
                        ForEach(lists) { list in
                            listChip(list)
                        }
                    }
                    destinationCaption
                }
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(13)
        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PopoverChrome.border.opacity(0.8), lineWidth: 1)
        )
    }

    private var headerRow: some View {
        HStack(spacing: 5) {
            Image(systemName: "bell")
                .font(.system(size: 11, weight: .bold))
            Text("미리알림 · 분류")
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
            Spacer(minLength: 8)
            Toggle("연동", isOn: Binding(get: { isLinked }, set: { _ in onToggleLink() }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .disabled(!isEditable)
            Text("연동")
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(isLinked ? PopoverChrome.ink : PopoverChrome.inkTertiary)
        }
        .foregroundStyle(PopoverChrome.inkTertiary)
    }

    private func listChip(_ list: ReminderListOption) -> some View {
        let selected = list.id == selectedListID
        let tint = swatch(list.id)
        return Button {
            onSelectList(list.id)
        } label: {
            Text(list.title)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(selected ? tint.ink : PopoverChrome.inkSecondary)
                .padding(.horizontal, 11)
                .frame(height: 27)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? tint.wash : PopoverChrome.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(selected ? tint.ink.opacity(0.35) : PopoverChrome.border, lineWidth: 1.2)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEditable)
    }

    @ViewBuilder
    private var destinationCaption: some View {
        if let title = lists.first(where: { $0.id == selectedListID })?.title {
            Text(TodoScheduleText.reminderDestination(listTitle: title, date: startDate, now: today))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
