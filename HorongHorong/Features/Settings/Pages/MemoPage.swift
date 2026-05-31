import SwiftUI
import SwiftData
import AppKit

struct MemoPage: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Memo.updatedAt, order: .reverse) private var allMemos: [Memo]

    @State private var store = HotkeyStore.shared
    @State private var autoClose: Bool = true
    @State private var autoSave: Bool = true
    @State private var reminderLists: [ReminderListOption] = []
    @State private var isLoadingReminderLists = false
    @State private var isImportingReminders = false
    @State private var isRevertingUncheckedReminders = false
    @State private var reminderImportMessage = ""
    private let reminderListColumns = [
        GridItem(.adaptive(minimum: 170, maximum: 240), spacing: 10, alignment: .leading)
    ]

    @AppStorage(Constants.AppStorageKey.remindersImportEnabled)
    private var remindersImportEnabled = false
    @AppStorage(Constants.AppStorageKey.remindersImportSelectedCalendarIDs)
    private var selectedReminderCalendarIDsValue = ""

    private var quickMemoBinding: Binding<HotkeyCombo> {
        Binding(get: { store.quickMemo }, set: { store.quickMemo = $0 })
    }

    private var selectedReminderCalendarIDs: Set<String> {
        get {
            Set(selectedReminderCalendarIDsValue
                .split(separator: "\n")
                .map(String.init)
                .filter { !$0.isEmpty })
        }
        nonmutating set {
            selectedReminderCalendarIDsValue = newValue.sorted().joined(separator: "\n")
        }
    }

    private var uncheckedLinkedReminderMemos: [Memo] {
        let selectedIDs = selectedReminderCalendarIDs
        return allMemos.filter { memo in
            guard memo.isLinkedToRemindersValue,
                  memo.reminderIdentifier != nil,
                  let calendarID = memo.reminderCalendarIdentifier else {
                return false
            }
            return !selectedIDs.contains(calendarID)
        }
    }

    var body: some View {
        SettingsPageScroll {
            SettingsPageHeader(title: SettingsTab.memo.label, subtitle: SettingsTab.memo.subtitle)

            SettingsGroupCard("퀵 메모") {
                SettingsRow(
                    "퀵 메모 단축키",
                    subtitle: "단축키로 어디서든 플로팅 메모 패널을 호출해 빠르게 메모할 수 있어요. 같은 단축키를 다시 누르면 패널이 닫힙니다. 박스를 클릭해 단축키를 바꿀 수 있습니다."
                ) {
                    HotkeyRecorderField(combo: quickMemoBinding)
                    if store.quickMemo != .defaultQuickMemo {
                        Button {
                            store.resetQuickMemoToDefault()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .help("기본값(⌘⇧N) 으로 되돌리기")
                    }
                }
                SettingsRow(
                    "포커스 잃을 때 자동 저장",
                    subtitle: "패널이 닫힐 때 내용이 비어있지 않으면 저장합니다.",
                    comingSoon: true
                ) {
                    Toggle("", isOn: $autoSave).labelsHidden()
                }
                SettingsRow(
                    "저장 후 자동으로 닫기",
                    subtitle: "Enter ↵ 로 저장 시 패널을 자동으로 닫습니다.",
                    comingSoon: true
                ) {
                    Toggle("", isOn: $autoClose).labelsHidden()
                }
            }

            remindersImportCard
        }
        .onAppear {
            if remindersImportEnabled {
                loadReminderLists(selectDefaultsIfNeeded: false)
            }
        }
    }

    private var remindersImportCard: some View {
        SettingsGroupCard("미리알림 가져오기") {
            SettingsRow(
                "미리알림 앱 연동",
                subtitle: "선택한 미리알림 목록의 미완료 항목을 호롱호롱 메모로 가져옵니다. 가져온 뒤에는 호롱호롱에서 미리알림으로 동기화합니다."
            ) {
                Toggle("", isOn: Binding(
                    get: { remindersImportEnabled },
                    set: { enabled in
                        if enabled {
                            enableRemindersImport()
                        } else {
                            remindersImportEnabled = false
                            reminderImportMessage = ""
                        }
                    }
                ))
                .labelsHidden()
            }

            if remindersImportEnabled {
                reminderListSelection

                SettingsRow(
                    "선택한 목록 가져오기",
                    subtitle: "이미 가져온 미리알림은 중복 생성하지 않습니다."
                ) {
                    Button {
                        importSelectedReminders()
                    } label: {
                        if isImportingReminders {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("가져오기")
                        }
                    }
                    .disabled(isImportingReminders || selectedReminderCalendarIDs.isEmpty)

                    Button {
                        loadReminderLists(selectDefaultsIfNeeded: false)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(isLoadingReminderLists)
                    .help("미리알림 목록 새로고침")
                }

                SettingsRow(
                    "체크 해제한 목록 되돌리기",
                    subtitle: "체크 해제한 목록에서 가져온 메모를 호롱호롱에서만 삭제합니다. 미리알림 앱의 원본 항목은 그대로 남습니다."
                ) {
                    Button(role: .destructive) {
                        revertUncheckedReminderMemos()
                    } label: {
                        if isRevertingUncheckedReminders {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("되돌리기")
                        }
                    }
                    .disabled(isRevertingUncheckedReminders || uncheckedLinkedReminderMemos.isEmpty)
                    .help("대상 \(uncheckedLinkedReminderMemos.count)개")
                }
            }
        }
    }

    private var reminderListSelection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isLoadingReminderLists {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("미리알림 목록을 불러오는 중입니다")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if reminderLists.isEmpty {
                Text("가져올 수 있는 미리알림 목록이 없습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: reminderListColumns, alignment: .leading, spacing: 10) {
                    ForEach(reminderLists) { list in
                        reminderListToggle(list)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !reminderImportMessage.isEmpty {
                Text(reminderImportMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 0.5)
                .padding(.leading, 14)
        }
    }

    private func reminderListToggle(_ list: ReminderListOption) -> some View {
        Toggle(isOn: reminderListBinding(for: list.id)) {
            HStack(spacing: 6) {
                Text(list.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if list.isDefault {
                    Text("기본")
                        .font(.caption2.bold())
                        .foregroundStyle(SettingsTheme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(SettingsTheme.accent.opacity(0.12), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
    }

    private func reminderListBinding(for identifier: String) -> Binding<Bool> {
        Binding {
            selectedReminderCalendarIDs.contains(identifier)
        } set: { isSelected in
            var identifiers = selectedReminderCalendarIDs
            if isSelected {
                identifiers.insert(identifier)
            } else {
                identifiers.remove(identifier)
            }
            selectedReminderCalendarIDs = identifiers
        }
    }

    private func enableRemindersImport() {
        remindersImportEnabled = true
        loadReminderLists(selectDefaultsIfNeeded: true)
    }

    private func loadReminderLists(selectDefaultsIfNeeded: Bool) {
        isLoadingReminderLists = true
        reminderImportMessage = ""
        Task { @MainActor in
            do {
                let lists = try await MemoReminderLinkService.shared.reminderImportLists()
                reminderLists = lists
                if selectDefaultsIfNeeded && selectedReminderCalendarIDs.isEmpty {
                    selectedReminderCalendarIDs = Set(lists.map(\.id))
                }
                if lists.isEmpty {
                    let diagnostics = MemoReminderLinkService.shared.reminderAccessDiagnostics()
                    reminderImportMessage = """
                    미리알림 목록을 찾지 못했습니다. 미리알림 앱에 iCloud 또는 로컬 목록이 있는지, 호롱호롱에 전체 접근 권한이 있는지 확인해 주세요.
                    상태: \(diagnostics.authorizationStatus), 소스: \(diagnostics.sourceCount), 목록: \(diagnostics.reminderCalendarCount), 쓰기 가능: \(diagnostics.writableReminderCalendarCount)
                    """
                } else {
                    reminderImportMessage = "\(lists.count)개의 미리알림 목록을 불러왔습니다."
                }
            } catch {
                remindersImportEnabled = false
                reminderLists = []
                reminderImportMessage = error.localizedDescription
            }
            isLoadingReminderLists = false
            refocusSettingsWindow()
        }
    }

    private func importSelectedReminders() {
        let calendarIDs = selectedReminderCalendarIDs
        guard !calendarIDs.isEmpty else {
            reminderImportMessage = "가져올 미리알림 목록을 선택해 주세요."
            return
        }

        isImportingReminders = true
        reminderImportMessage = ""
        Task { @MainActor in
            do {
                let items = try await MemoReminderLinkService.shared.reminderItems(calendarIDs: calendarIDs)
                let existingReminderIDs = Set(allMemos.compactMap(\.reminderIdentifier))
                var importedCount = 0

                for item in items where !item.isCompleted && !existingReminderIDs.contains(item.id) {
                    let memo = Memo(content: memoContent(from: item), icon: MemoIcon.defaultIcon)
                    memo.startDate = item.startDate
                    memo.deadline = item.dueDate
                    memo.reminderIdentifier = item.id
                    memo.reminderCalendarIdentifier = item.calendarIdentifier
                    memo.isLinkedToRemindersValue = true
                    modelContext.insert(memo)
                    importedCount += 1
                }

                try modelContext.save()
                reminderImportMessage = importedCount == 0
                    ? "새로 가져올 미완료 미리알림이 없습니다."
                    : "\(importedCount)개의 미리알림을 메모로 가져왔습니다."
            } catch {
                reminderImportMessage = error.localizedDescription
            }
            isImportingReminders = false
        }
    }

    private func revertUncheckedReminderMemos() {
        let targets = uncheckedLinkedReminderMemos
        guard !targets.isEmpty else {
            reminderImportMessage = "되돌릴 미리알림 연결 메모가 없습니다."
            return
        }

        isRevertingUncheckedReminders = true
        Task { @MainActor in
            for memo in targets {
                NotificationManager.shared.cancel(identifier: "memo.deadline.\(memo.id.uuidString)")
                modelContext.delete(memo)
            }

            do {
                try modelContext.save()
                reminderImportMessage = "\(targets.count)개의 메모를 호롱호롱에서 제거했습니다. 미리알림 앱의 원본은 그대로 남아 있습니다."
            } catch {
                reminderImportMessage = error.localizedDescription
            }
            isRevertingUncheckedReminders = false
        }
    }

    private func memoContent(from item: ReminderListItem) -> String {
        var lines = [item.title]
        if let notes = item.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            lines.append(notes)
        }
        if let url = item.url?.absoluteString, !lines.contains(where: { $0.contains(url) }) {
            lines.append(url)
        }
        return lines.joined(separator: "\n")
    }

    private func refocusSettingsWindow() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if let settingsWindow = NSApp.windows.first(where: { window in
                let identifier = window.identifier?.rawValue ?? ""
                return identifier.contains("com_apple_SwiftUI_Settings")
                    || window.title.localizedCaseInsensitiveContains("설정")
            }) {
                settingsWindow.makeKeyAndOrderFront(nil)
                settingsWindow.orderFrontRegardless()
            }
        }
    }
}
