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
 목표 관리 시트.

 원래 `AchievementViews.swift`(9,854줄) 한 파일에 있었다. 2026-09-03 분할.
 */

struct AchievementGoalManagementSheet: View {
    @Environment(\.dismiss) private var dismiss

    let record: AchievementGoalDetail
    let linkedMemoCount: Int
    let memos: [AchievementMemoDetail]
    let childRecords: [AchievementGoalDetail]
    let availableChildRecords: [AchievementGoalDetail]
    let childCadence: String?
    /// 다른 주간 목표가 이미 가진 할일 → 그 목표. 여기 있는 할일은 고를 수 없다.
    let linkOwners: [UUID: AchievementGoalDetail]
    let onSave: (AchievementGoalDetail, AchievementGoalEditDraft) -> Void
    let onDelete: (AchievementGoalDetail) -> Void
    /// 자식을 부모에서 떼어낸다. 자식 목표 자체를 고치거나 지우는 일은 그 목표의 관리 창이 맡는다.
    let onDetachChild: (AchievementGoalDetail) -> Void

    @State private var title: String
    @State private var emoji: String
    @State private var rule: String
    @State private var rewardText: String
    @State private var selectedMemoIDs: Set<UUID>
    @State private var selectedAvailableChildIDs: Set<UUID> = []
    @State private var dueDate: Date
    @State private var hasDueDate: Bool
    @State private var showsDeleteConfirmation = false

    init(
        record: AchievementGoalDetail,
        linkedMemoCount: Int,
        memos: [AchievementMemoDetail] = [],
        childRecords: [AchievementGoalDetail] = [],
        availableChildRecords: [AchievementGoalDetail] = [],
        childCadence: String? = nil,
        linkOwners: [UUID: AchievementGoalDetail] = [:],
        onSave: @escaping (AchievementGoalDetail, AchievementGoalEditDraft) -> Void,
        onDelete: @escaping (AchievementGoalDetail) -> Void,
        onDetachChild: @escaping (AchievementGoalDetail) -> Void = { _ in }
    ) {
        self.record = record
        self.linkedMemoCount = linkedMemoCount
        self.memos = memos
        self.childRecords = childRecords
        self.availableChildRecords = availableChildRecords
        self.childCadence = childCadence
        self.linkOwners = linkOwners
        self.onSave = onSave
        self.onDelete = onDelete
        self.onDetachChild = onDetachChild
        _title = State(initialValue: record.title)
        _emoji = State(initialValue: record.emoji)
        _rule = State(initialValue: record.rule)
        _rewardText = State(initialValue: record.rewardText)
        // 저장된 연결에는 **최근 삭제로 보낸 할일** 의 id 가 그대로 남아 있다(복구하면
        // 다시 이어져야 하니까). 그걸 그대로 켜 두면 이 시트에서 저장하는 순간
        // 목록에 없는 할일이 되살아난다 — 지금 고를 수 있는 것만 남긴다.
        let selectableIDs = Set(memos.map(\.id))
        _selectedMemoIDs = State(
            initialValue: Set(record.linkedMemoIDs).intersection(selectableIDs).subtracting(linkOwners.keys)
        )
        _dueDate = State(initialValue: record.dueDate ?? Date())
        _hasDueDate = State(initialValue: record.dueDate != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("목표 관리")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.ink)
                    Text("\(record.cadence) · 연결된 할일 \(linkedMemoCount)개")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                }
                Spacer()
                Button("닫기") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    field(label: "이모지") {
                        TextField("🎯", text: $emoji)
                            .textFieldStyle(.plain)
                            .font(.system(size: 18))
                            .frame(width: 52)
                            .padding(10)
                            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous)
                                    .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
                            )
                    }
                    field(label: "목표명") {
                        TextField("목표명", text: $title)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                            .padding(10)
                            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous)
                                    .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
                            )
                    }
                }

                field(label: "달성 기준") {
                    TextField("예: 메모 3개 완료", text: $rule)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .padding(10)
                        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous)
                                .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
                        )
                }

                field(label: "마감일") {
                    HStack(spacing: 8) {
                        Toggle("", isOn: $hasDueDate)
                            .toggleStyle(.switch)
                            .labelsHidden()
                        if hasDueDate {
                            DatePicker("", selection: $dueDate, displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(.compact)
                        } else {
                            Text("마감일 없음")
                                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                                .foregroundStyle(PopoverChrome.inkTertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous)
                            .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
                    )
                }

                if childCadence != nil {
                    childGoalSection
                } else if supportsMemoLinks {
                    linkedMemoSection
                }
            }

            HStack(spacing: 10) {
                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    Text("삭제")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.red)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))

                Button {
                    onSave(record, AchievementGoalEditDraft(
                        title: title,
                        emoji: emoji,
                        rule: rule,
                        targetCount: supportsMemoLinks ? max(1, selectedMemoIDs.count) : record.targetCount,
                        rewardText: rewardText,
                        linkedMemoIDs: supportsMemoLinks ? Array(selectedMemoIDs) : nil,
                        dueDate: hasDueDate ? dueDate : nil,
                        additionalChildGoalIDs: selectedAvailableChildIDs.isEmpty ? nil : Array(selectedAvailableChildIDs)
                    ))
                    dismiss()
                } label: {
                    Text("저장")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.accentInk)
                .background(PopoverChrome.primaryButtonFill, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
            }
        }
        .padding(18)
        .frame(width: 420)
        .background(PopoverChrome.surface)
        .alert("목표를 삭제할까요?", isPresented: $showsDeleteConfirmation) {
            Button("삭제", role: .destructive) {
                onDelete(record)
                dismiss()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("삭제한 목표는 복구할 수 없습니다.")
        }
    }

    private var childGoalSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("하위 \(childCadence ?? "") 목표")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                Spacer()
                Text("\(childRecords.count)개")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .monospacedDigit()
            }

            if childRecords.isEmpty {
                Text("아직 연결된 \(childCadence ?? "") 목표가 없습니다.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
            } else {
                ScrollView {
                    VStack(spacing: 7) {
                        ForEach(childRecords, id: \.id) { child in
                            AchievementChildGoalEditorRow(
                                record: child,
                                onDetach: onDetachChild
                            )
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: childRecords.count > 3 ? 190 : nil)
                .popoverScrollbar()
                .background(PopoverChrome.surfaceAlt.opacity(0.58), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
            }

            if !availableChildRecords.isEmpty {
                Text("기존 \(childCadence ?? "") 목표 연결")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .padding(.top, 4)

                if !selectedAvailableChildIDs.isEmpty {
                    let hasOtherParentOrRole = availableChildRecords.contains { child in
                        selectedAvailableChildIDs.contains(child.id) && 
                        ((record.cadence == "월간" ? child.monthGoal != nil : child.yearGoal != nil) || (child.roleName != record.roleName))
                    }
                    if hasOtherParentOrRole {
                        Text("💡 다른 목표/역할에 연결된 항목을 선택하면 기존 연결이 해제되고 현재 목표로 이동됩니다.")
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(PopoverChrome.inkTertiary)
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(availableChildRecords, id: \.id) { child in
                            let currentParent = record.cadence == "월간" ? child.monthGoal : child.yearGoal
                            Toggle(isOn: Binding(
                                get: { selectedAvailableChildIDs.contains(child.id) },
                                set: { isSelected in
                                    if isSelected {
                                        selectedAvailableChildIDs.insert(child.id)
                                    } else {
                                        selectedAvailableChildIDs.remove(child.id)
                                    }
                                }
                            )) {
                                HStack(spacing: 6) {
                                    Text(child.emoji)
                                        .font(.system(size: 13))
                                    Text(child.title)
                                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                        .foregroundStyle(PopoverChrome.inkSecondary)
                                    
                                    let rolePrefix = (child.roleName != record.roleName && !child.roleName.isEmpty) ? "[\(child.roleName)] " : ""
                                    if let currentParent, !currentParent.isEmpty {
                                        Text("(\(rolePrefix)\(currentParent))")
                                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                            .foregroundStyle(PopoverChrome.inkTertiary)
                                    } else if !rolePrefix.isEmpty {
                                        Text("\(rolePrefix.trimmingCharacters(in: .whitespaces))")
                                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                            .foregroundStyle(PopoverChrome.inkTertiary)
                                    }
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                    .padding(8)
                }
                // 보상 입력칸을 없애며 생긴 자리를 여기에 준다. 한 번에 더 많은 목표를 훑을 수 있다.
                .frame(maxHeight: availableChildRecords.count > 3 ? 205 : nil)
                .popoverScrollbar()
                .background(PopoverChrome.surfaceAlt.opacity(0.58), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
            }
        }
        .padding(10)
        .background(PopoverChrome.surfaceAlt.opacity(0.42), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(11), style: .continuous))
    }

    private var supportsMemoLinks: Bool {
        record.cadence == "주간"
    }

    private var linkedMemoSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("연결된 할일")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                Spacer()
                Text("\(selectedMemoIDs.count)개")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .monospacedDigit()
            }

            if memos.isEmpty {
                Text("연결할 수 있는 할일이 없습니다.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
            } else {
                ScrollView {
                    // 기록이 늘면 이 목록도 함께 는다. VStack 이면 전부 즉시 만든다.
                    LazyVStack(alignment: .leading, spacing: 7) {
                        ForEach(memos) { memo in
                            Toggle(isOn: Binding(
                                get: { selectedMemoIDs.contains(memo.id) },
                                set: { isSelected in
                                    if isSelected {
                                        selectedMemoIDs.insert(memo.id)
                                    } else {
                                        selectedMemoIDs.remove(memo.id)
                                    }
                                }
                            )) {
                                AchievementMemoPickerRow(memo: memo, lockedByGoalTitle: linkOwners[memo.id]?.title)
                            }
                            .toggleStyle(.checkbox)
                            .disabled(linkOwners[memo.id] != nil)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: memos.count > 4 ? 220 : nil)
                .popoverScrollbar()
                .background(PopoverChrome.surfaceAlt.opacity(0.58), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
            }
        }
        .padding(10)
        .background(PopoverChrome.surfaceAlt.opacity(0.42), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(11), style: .continuous))
    }

    private func field<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)
            content()
        }
    }
}

/// 부모 목표에 딸린 하위 목표 한 줄.
///
/// 이름·이모지 수정과 삭제는 그 목표 자신의 관리 창이 맡는다.
/// 여기서는 부모와의 연결만 다룬다 — 실수로 남의 목표를 통째로 지우는 일이 없도록.
struct AchievementChildGoalEditorRow: View {
    let record: AchievementGoalDetail
    let onDetach: (AchievementGoalDetail) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(record.emoji)
                .font(.system(size: 15))
                .frame(width: 24)

            Text(record.title)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
                .lineLimit(1)

            Spacer(minLength: 6)

            Button {
                onDetach(record)
            } label: {
                Text("연결 해제")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(PopoverChrome.card, in: Capsule())
                    .overlay(Capsule().stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
            }
            .buttonStyle(.plain)
            .help("이 목표를 상위 목표에서 떼어냅니다. 목표 자체는 남습니다.")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(PopoverChrome.surfaceAlt.opacity(0.5), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
    }
}
