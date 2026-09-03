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
 목표 작성 시트.
 
  아직 크다. `AchievementDetailWindow` 와 같은 이유로 ViewModel 이전 때 함께 가른다.

 원래 `AchievementViews.swift`(9,854줄) 한 파일에 있었다. 2026-09-03 분할.
 */

struct AchievementGoalComposerSheet: View {
    /// 지금 폼에 채워 넣은 추천. «적용» 을 눌렀을 때만 채워진다.
    ///
    /// 적용과 저장은 **다른 순간**이다 — 적용은 폼을 채울 뿐이고 목표는 저장에서 생긴다.
    /// 적용만 하고 닫으면 채택이 아니므로, 출처를 여기 들고 있다가 **저장할 때** 심는다.
    @State private var appliedSuggestion: AchievementGoalSuggestion?

    /// 목표에 묶을 수 있는 할일. **저장소가 이미 걸러 준다**(Todo 섹션 · 안 끝난 것 ·
    /// 보관·삭제 제외). 예전에는 전체를 받아 여기서 같은 조건을 다시 썼다.
    let memos: [AchievementMemoDetail]
    let existingGoals: [AchievementGoal]
    let onClose: () -> Void
    /// 저장한 목표, 이어붙일 기존 하위 목표, 함께 새로 만들 하위 목표 제목들.
    /// 저장한 뒤 **만들어진 목표의 id 를 돌려준다.** 추천 채택 기록에 그 id 가 필요하다 —
    /// 예전에는 여기서 레코드를 직접 만들어 id 를 알고 있었다.
    let onSave: (AchievementGoalDraft, Set<UUID>, [String]) throws -> UUID

    @AppStorage(Constants.AppStorageKey.achievementSuggestionCount)
    private var weeklySuggestionLimit: Int = Constants.defaultAchievementSuggestionCount
    @AppStorage(Constants.AppStorageKey.achievementSuggestionMaxTodoCount)
    private var maxTodosPerWeeklyGoal: Int = Constants.defaultAchievementSuggestionMaxTodoCount
    @AppStorage(Constants.AppStorageKey.achievementMonthlySuggestionMinWeeklyGoalCount)
    private var minWeeklyGoalsForMonthlySuggestions: Int = Constants.defaultAchievementMonthlySuggestionMinWeeklyGoalCount
    @AppStorage(Constants.AppStorageKey.achievementMonthlySuggestionCount)
    private var monthlySuggestionLimit: Int = Constants.defaultAchievementMonthlySuggestionCount
    @AppStorage(Constants.AppStorageKey.achievementMinTodosForWeeklySuggestions)
    private var minTodosForWeeklySuggestions: Int = Constants.defaultAchievementMinTodosForWeeklySuggestions
    @AppStorage(Constants.AppStorageKey.achievementMaxWeeklyGoalsPerMonthlyGoal)
    private var maxWeeklyGoalsPerMonthlyGoal: Int = Constants.defaultAchievementMaxWeeklyGoalsPerMonthlyGoal
    @AppStorage(Constants.AppStorageKey.achievementSuggestionExcludedMemoIcons)
    private var excludedMemoIconsRaw: String = Constants.defaultAchievementSuggestionExcludedMemoIconsRaw
    @AppStorage(Constants.AppStorageKey.achievementDismissedSuggestionKeys)
    private var dismissedSuggestionKeysRaw: String = ""

    @State private var selectedInputMode = "직접 입력"
    @State private var selectedTargetLevel = "주간"
    @State private var title = ""
    @State private var selectedEmoji = "🎯"
    @State private var selectedPersonaTitle = ""
    @State private var selectedVisionTitle = ""
    @State private var selectedChildGoalIDs = Set<UUID>()
    @State private var targetValueText = ""
    @State private var periodText = "이번 주"
    @State private var criterion = ""
    @State private var colorHex = "#E87333"
    @State private var selectedMemoIDs = Set<UUID>()
    @State private var validationMessage: String?
    @State private var suggestions: [AchievementGoalSuggestion] = []
    @State private var guidance: [GoalRecommendationGuidance] = []
    @State private var isLoadingSuggestions = false
    @State private var suggestionMessage: String?
    @State private var didLoadSuggestions = false
    @State private var isAdvancedSettingsExpanded = false
    @State private var selectedPeriodDate = Date()
    @State private var hasDueDate = false
    @State private var expandedSuggestionKeys = Set<String>()
    /// 하위 목표를 찾거나 새로 만들 때 쓰는 한 줄 입력.
    @State private var childSearchText = ""
    /// 아직 존재하지 않아 저장할 때 함께 만들 하위 목표 제목들.
    @State private var newChildTitles: [String] = []
    @State private var memoSearchText = ""
    @FocusState private var isEmojiInputFocused: Bool

    private let inputModes = ["AI 추천", "직접 입력"]
    /// 자주 만드는 월간·주간이 앞줄에 오도록 둔다.
    private let targetLevels = ["월간", "주간", "역할", "비전"]
    private let colors = ["#E87333", "#2F5BEA", "#7A52D4", "#D94F73", "#2F9E73"]

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    modePicker
                    if selectedInputMode == "AI 추천" {
                        aiPlaceholder
                    } else {
                        directInputForm
                    }
                }
                .padding(14)
            }

            Button {
                save()
            } label: {
                Text("목표 만들기")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.accentInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(PopoverChrome.primaryButtonFill, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.48)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(width: 340)
        .frame(maxHeight: .infinity)
        .background(PopoverChrome.surface)
        .onAppear {
            if !didLoadSuggestions {
                loadGoalSuggestions()
            }
        }
        .onChange(of: selectedInputMode) { _, mode in
            if mode == "AI 추천", !didLoadSuggestions {
                loadGoalSuggestions()
            }
        }
        .onChange(of: weeklySuggestionLimit) { _, _ in
            reloadSuggestionsAfterSettingsChange()
        }
        .onChange(of: maxTodosPerWeeklyGoal) { _, _ in
            reloadSuggestionsAfterSettingsChange()
        }
        .onChange(of: minWeeklyGoalsForMonthlySuggestions) { _, _ in
            reloadSuggestionsAfterSettingsChange()
        }
        .onChange(of: monthlySuggestionLimit) { _, _ in
            reloadSuggestionsAfterSettingsChange()
        }
        .onChange(of: minTodosForWeeklySuggestions) { _, _ in
            reloadSuggestionsAfterSettingsChange()
        }
        .onChange(of: maxWeeklyGoalsPerMonthlyGoal) { _, _ in
            reloadSuggestionsAfterSettingsChange()
        }
        .onChange(of: excludedMemoIconsRaw) { _, _ in
            reloadSuggestionsAfterSettingsChange()
        }
    }

    private var header: some View {
        HStack {
            Text("목표 추가")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
            Spacer()
            Button("닫기") {
                onClose()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(PopoverChrome.inkSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(PopoverChrome.surfaceAlt.opacity(0.7))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PopoverChrome.divider)
                .frame(height: PopoverChrome.borderWidth)
        }
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(inputModes, id: \.self) { mode in
                Button {
                    selectedInputMode = mode
                    validationMessage = nil
                } label: {
                    Text(mode)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(selectedInputMode == mode ? PopoverChrome.accentInk : PopoverChrome.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selectedInputMode == mode ? PopoverChrome.accent : Color.clear, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(4)
        .background(PopoverChrome.surfaceAlt.opacity(0.84), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous))
    }

    private var aiPlaceholder: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("추천 묶음")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.ink)
                    Text(suggestionMessage ?? "할일은 주간 목표로, 주간 목표는 월간 목표로 묶어 제안합니다.")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    loadGoalSuggestions(force: true)
                } label: {
                    HStack(spacing: 6) {
                        if isLoadingSuggestions {
                            ProgressView()
                                .scaleEffect(0.58)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .bold))
                        }
                        Text(isLoadingSuggestions ? "추천 중" : "다시 추천")
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(PopoverChrome.ink)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isLoadingSuggestions)
                .help("다시 추천 받기")
            }

            if isLoadingSuggestions && suggestions.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("묶을 수 있는 목표를 찾는 중")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
            } else if !guidance.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Text("목표로 묶기 전에 조금만 구체화해 보세요")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.ink)
                    ForEach(guidance) { item in
                        guidanceCard(item)
                    }
                }
            } else if suggestions.isEmpty {
                Text("추천할 묶음이 없습니다. 직접 입력에서 할일을 선택해 목표로 만들 수 있습니다.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
            } else {
                VStack(spacing: 9) {
                    ForEach(suggestions) { suggestion in
                        suggestionCard(suggestion)
                    }
                }
            }

            Button {
                selectedInputMode = "직접 입력"
            } label: {
                Text("직접 할일 선택하기")
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(PopoverChrome.accentSoft.opacity(0.68), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func suggestionCard(_ suggestion: AchievementGoalSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                Text(suggestion.emoji)
                    .font(.system(size: 18))
                    .frame(width: 28, height: 28)
                    .background(PopoverChrome.accentSoft.opacity(0.7), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    // 배지는 폭이 고정이라 제목과 한 줄을 나눠 쓰면 **제목이 먼저 잘린다.**
                    // 위로 올려 제목이 카드 폭을 통째로 쓰게 한다.
                    HStack(spacing: 5) {
                        Text(suggestion.cadence.rawValue)
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundStyle(suggestion.cadence == .monthly ? PopoverChrome.accent : PopoverChrome.inkSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                (suggestion.cadence == .monthly ? PopoverChrome.accentSoft : PopoverChrome.surfaceAlt).opacity(0.76),
                                in: Capsule()
                            )
                        // 룰 기반은 **항상** 표시한다. 사용자가 «AI 추천» 을 직접 골랐는데
                        // 규칙이 만든 결과를 받으면서 모른다면, 기대한 것과 다른 걸 준 것이다.
                        // 어느 공급자였는지는 개발 중에만 궁금하므로 나머지는 DEBUG 로 둔다.
                        if suggestion.source == .rule {
                            Text("규칙")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(PopoverChrome.inkSecondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(PopoverChrome.surfaceAlt.opacity(0.6), in: Capsule())
                                .help("AI가 묶음을 만들지 못해 규칙으로 묶은 초안입니다.")
                        } else {
                            #if DEBUG
                            Text(suggestion.source.rawValue)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(PopoverChrome.inkSecondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(PopoverChrome.surfaceAlt.opacity(0.6), in: Capsule())
                            #endif
                        }
                    }
                    Text(suggestion.title)
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.ink)
                        // 줄 수를 막지 않는다 — 잘린 제목은 어느 목표인지 알 수 없게 만든다.
                        // `fixedSize` 가 없으면 높이가 좁다고 판단해 그대로 말줄임으로 돌아간다.
                        .fixedSize(horizontal: false, vertical: true)
                    Text(suggestion.reason)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .lineLimit(2)
                }
                // 남는 폭을 제목이 갖게 한다. 이게 없으면 텍스트 열과 `Spacer` 가 폭을 나눠 갖는다.
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 4)
                Button {
                    dismissSuggestion(suggestion)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .frame(width: 24, height: 24)
                        .background(PopoverChrome.surfaceAlt.opacity(0.72), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("이 조합 추천 제외")
            }

            VStack(alignment: .leading, spacing: 5) {
                if suggestion.cadence == .monthly {
                    ForEach(visibleChildGoalIDs(for: suggestion), id: \.self) { id in
                        if let goal = goal(for: id) {
                            HStack(spacing: 6) {
                                Image(systemName: goal.isComplete ? "checkmark.circle.fill" : "target")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(goal.isComplete ? PopoverChrome.accent : PopoverChrome.inkTertiary)
                                Text("\(goal.emoji) \(AchievementDataBuilder.shortText(goal.title, limit: 28))")
                                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(PopoverChrome.ink)
                                    .lineLimit(1)
                            }
                        }
                    }
                    if suggestion.childGoalIDs.count > 3 {
                        Button {
                            toggleSuggestionExpansion(suggestion)
                        } label: {
                            Label(
                                isSuggestionExpanded(suggestion) ? "접기" : "외 \(suggestion.childGoalIDs.count - 3)개 주간 목표",
                                systemImage: isSuggestionExpanded(suggestion) ? "chevron.up" : "chevron.down"
                            )
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundStyle(PopoverChrome.inkTertiary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    ForEach(visibleMemoIDs(for: suggestion), id: \.self) { id in
                        if let memo = memo(for: id) {
                            HStack(spacing: 6) {
                                Image(systemName: memo.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(memo.isCompleted ? PopoverChrome.accent : PopoverChrome.inkTertiary)
                                Text(AchievementDataBuilder.shortText(memo.content, limit: 30))
                                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(PopoverChrome.ink)
                                    .lineLimit(1)
                            }
                        }
                    }
                    if suggestion.memoIDs.count > 3 {
                        Button {
                            toggleSuggestionExpansion(suggestion)
                        } label: {
                            Label(
                                isSuggestionExpanded(suggestion) ? "접기" : "외 \(suggestion.memoIDs.count - 3)개",
                                systemImage: isSuggestionExpanded(suggestion) ? "chevron.up" : "chevron.down"
                            )
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundStyle(PopoverChrome.inkTertiary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(9)
            .background(PopoverChrome.surfaceAlt.opacity(0.58), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))

            HStack(spacing: 8) {
                Label(suggestion.scheduleText, systemImage: "calendar")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .lineLimit(1)
                Spacer()
                Button {
                    applySuggestion(suggestion)
                } label: {
                    Text("적용")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.accentInk)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(PopoverChrome.primaryButtonFill, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(11), style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(11), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
    }

    private func guidanceCard(_ item: GoalRecommendationGuidance) -> some View {
        let inputTitle = memos.first(where: { $0.id == item.inputID })?.content
            ?? existingGoals.first(where: { $0.id == item.inputID })?.title
            ?? "입력 항목"
        return VStack(alignment: .leading, spacing: 6) {
            Text(inputTitle)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
                .lineLimit(2)
            if !item.missing.isEmpty {
                Text("보완할 점: \(item.missing.joined(separator: ", "))")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
            }
            Text(item.suggestion)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
    }

    private var directInputForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let validationMessage {
                Text(validationMessage)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
            }

            fieldLabel("어떤 목표인가요?")
            targetLevelGrid

            fieldLabel("목표 이름")
            TextField(goalPlaceholder, text: $title)
                .textFieldStyle(.plain)
                .padding(10)
                .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous)
                        .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
                )

            primarySourcePicker

            DisclosureGroup(isExpanded: $isAdvancedSettingsExpanded) {
                advancedSettingsForm
                    .padding(.top, 10)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .bold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("세부 설정")
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundStyle(PopoverChrome.ink)
                        Text("비워두면 앱이 자동으로 채웁니다.")
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(PopoverChrome.inkTertiary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation {
                        isAdvancedSettingsExpanded.toggle()
                    }
                }
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(PopoverChrome.inkSecondary)
            .padding(11)
            .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
        }
    }

    @ViewBuilder
    private var primarySourcePicker: some View {
        if shouldShowMemoPicker {
            memoPicker
        } else {
            childGoalPicker
        }
    }

    private var advancedSettingsForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            fieldLabel("이모지")
            emojiPicker

            if supportsPersonaVisionGroup {
                personaVisionPicker
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("목표 수치")
                    TextField(defaultTargetValueText, text: $targetValueText)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        fieldLabel("마감일")
                        Spacer(minLength: 0)
                        if hasDueDate {
                            Button("지우기") {
                                hasDueDate = false
                                periodText = defaultPeriodText(for: selectedTargetLevel)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundStyle(PopoverChrome.inkTertiary)
                        }
                    }
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { selectedPeriodDate },
                            set: { date in
                                selectedPeriodDate = date
                                hasDueDate = true
                                periodText = periodText(for: date)
                            }
                        ),
                        displayedComponents: .date
                    )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .opacity(hasDueDate ? 1 : 0.5)
                        .padding(.horizontal, 10)
                        .frame(height: 36, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
                    Text(hasDueDate ? "기한이 지나면 목표에 ‘기한 지남’이 표시돼요." : "지정하지 않으면 마감일 없이 계속 진행돼요.")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                }
            }

            fieldLabel("달성 기준")
            TextEditor(text: $criterion)
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 70)
                .padding(8)
                .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))

            colorPicker
        }
    }

    private var targetLevelGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2), spacing: 6) {
            ForEach(targetLevels, id: \.self) { level in
                Button {
                    selectedTargetLevel = level
                    selectedEmoji = emoji(for: level)
                    if level == "역할" {
                        selectedPersonaTitle = ""
                        selectedVisionTitle = ""
                    } else if level == "비전" {
                        selectedVisionTitle = ""
                    }
                    if !showsMemoPicker(for: level) {
                        selectedMemoIDs.removeAll()
                    }
                    selectedChildGoalIDs = selectedChildGoalIDs.filter { id in
                        childGoalCandidates(for: level).contains { $0.id == id }
                    }
                    if level == "주간" {
                        periodText = periodText.isEmpty ? "이번 주" : periodText
                    } else if level == "월간" {
                        periodText = periodText.isEmpty || periodText == "이번 주" ? "이번 달" : periodText
                    }
                } label: {
                    VStack(spacing: 2) {
                        Text(level)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                        if let subtitle = targetLevelSubtitle(for: level) {
                            Text(subtitle)
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        }
                    }
                        .foregroundStyle(selectedTargetLevel == level ? PopoverChrome.accentInk : PopoverChrome.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(selectedTargetLevel == level ? PopoverChrome.accent : PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous)
                                .stroke(selectedTargetLevel == level ? Color.clear : PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var personaVisionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel(selectedTargetLevel == "비전" ? "페르소나 선택" : "페르소나/비전 묶음")

            HStack(spacing: 8) {
                Menu {
                    Button("선택 안함") {
                        selectedPersonaTitle = ""
                        selectedVisionTitle = ""
                    }
                    ForEach(personaGoals) { goal in
                        Button {
                            selectedPersonaTitle = goal.title
                            if selectedTargetLevel == "비전" {
                                selectedVisionTitle = ""
                            }
                            if !visionCandidates.contains(where: { $0.title == selectedVisionTitle }) {
                                selectedVisionTitle = ""
                            }
                        } label: {
                            Text("\(goal.emoji) \(goal.title)")
                        }
                    }
                } label: {
                    pickerLabel(selectedPersonaTitle.isEmpty ? "페르소나 없음" : selectedPersonaTitle)
                }
                .buttonStyle(.plain)

                if selectedTargetLevel != "비전" {
                    Menu {
                        Button("선택 안함") {
                            selectedVisionTitle = ""
                        }
                        ForEach(visionCandidates) { goal in
                            Button {
                                selectedVisionTitle = goal.title
                                if selectedPersonaTitle.isEmpty, !goal.roleName.isEmpty {
                                    selectedPersonaTitle = goal.roleName
                                }
                            } label: {
                                Text("\(goal.emoji) \(goal.title)")
                            }
                        }
                    } label: {
                        pickerLabel(selectedVisionTitle.isEmpty ? "비전 없음" : selectedVisionTitle)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 하위 목표를 고르는 자리.
    ///
    /// 한 입력창이 찾기와 만들기를 겸한다. 사용자가 위에서 아래로 짜는지 아래에서 위로 짜는지
    /// 의식하지 않아도 되도록, 떠오르는 이름을 치면 있으면 잇고 없으면 만들어 준다.
    private var childGoalPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let level = childGoalLevel {
                HStack(spacing: 6) {
                    fieldLabel("하위 \(level) 목표")
                    Text("선택")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(PopoverChrome.surfaceAlt, in: Capsule())
                    Spacer()
                }

                searchField(
                    text: $childSearchText,
                    placeholder: "찾거나 새로 입력…"
                )

                childGoalSuggestionList(level: level)
                pickedChildChips(level: level)
            }
        }
    }

    @ViewBuilder
    private func childGoalSuggestionList(level: String) -> some View {
        let matches = matchingChildGoalCandidates
        let canCreate = !trimmedChildSearch.isEmpty && !childTitleAlreadyUsed(trimmedChildSearch)

        if matches.isEmpty && !canCreate {
            Text(childGoalCandidates.isEmpty
                 ? "연결할 수 있는 \(level) 목표가 없습니다. 이름을 입력하면 새로 만들 수 있어요."
                 : "찾는 목표가 없습니다.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PopoverChrome.surfaceAlt, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(matches) { goal in
                        Toggle(isOn: Binding(
                            get: { selectedChildGoalIDs.contains(goal.id) },
                            set: { isSelected in
                                if isSelected {
                                    selectedChildGoalIDs.insert(goal.id)
                                    validationMessage = nil
                                } else {
                                    selectedChildGoalIDs.remove(goal.id)
                                }
                            }
                        )) {
                            AchievementChildGoalPickerRow(goal: goal)
                        }
                        .toggleStyle(.checkbox)
                    }

                    if canCreate {
                        if !matches.isEmpty {
                            Divider().overlay(PopoverChrome.divider)
                        }
                        Button {
                            newChildTitles.append(trimmedChildSearch)
                            childSearchText = ""
                            validationMessage = nil
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text("«\(trimmedChildSearch)» 새로 만들기")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(PopoverChrome.accent)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
            }
            .frame(maxHeight: matches.count > 5 ? 230 : nil)
            .popoverScrollbar()
            .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
        }
    }

    /// 담아둔 하위 목표. 기존 것과 새로 만들 것을 한 줄에 나란히 보여준다.
    @ViewBuilder
    private func pickedChildChips(level: String) -> some View {
        let picked = childGoalCandidates.filter { selectedChildGoalIDs.contains($0.id) }

        if !picked.isEmpty || !newChildTitles.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 240), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(picked) { goal in
                    pickedChip(emoji: goal.emoji, title: goal.title, isNew: false) {
                        selectedChildGoalIDs.remove(goal.id)
                    }
                }
                ForEach(Array(newChildTitles.enumerated()), id: \.offset) { index, title in
                    pickedChip(emoji: emoji(for: level), title: title, isNew: true) {
                        newChildTitles.remove(at: index)
                    }
                }
            }
        }
    }

    private func pickedChip(emoji: String, title: String, isNew: Bool, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(emoji)
                .font(.system(size: 10))
            Text(title)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .lineLimit(1)
            if isNew {
                Text("새로")
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.accentInk)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(PopoverChrome.accent, in: Capsule())
            }
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(PopoverChrome.accent)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(PopoverChrome.accentSoft.opacity(0.28), in: Capsule())
    }

    private func searchField(text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(PopoverChrome.inkTertiary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(9)
        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
    }

    private var trimmedChildSearch: String {
        childSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchingChildGoalCandidates: [AchievementGoal] {
        guard !trimmedChildSearch.isEmpty else { return childGoalCandidates }
        return childGoalCandidates.filter { $0.title.localizedCaseInsensitiveContains(trimmedChildSearch) }
    }

    /// 이미 담았거나 같은 이름이 있으면 새로 만들자고 권하지 않는다.
    private func childTitleAlreadyUsed(_ title: String) -> Bool {
        if newChildTitles.contains(where: { $0.caseInsensitiveCompare(title) == .orderedSame }) {
            return true
        }
        return childGoalCandidates.contains { $0.title.caseInsensitiveCompare(title) == .orderedSame }
    }

    private var memoPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                fieldLabel("연결할 할일")
                Text("선택")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(PopoverChrome.surfaceAlt, in: Capsule())
                Spacer()
            }

            if !linkableMemos.isEmpty {
                searchField(text: $memoSearchText, placeholder: "할일 찾기…")
            }

            if linkableMemos.isEmpty {
                Text("연결할 수 있는 미완료 할일이 없습니다. 먼저 메모장에서 할일을 추가해 주세요.")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PopoverChrome.surfaceAlt, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
            } else {
                ScrollView {
                    // 바깥만 lazy 로 두면 섹션 컨테이너만 지연되고 그 안의 행은 전부 만들어진다.
                    // 둘 다 바꿔야 화면에 보이는 만큼만 만든다.
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(memoPickerSections) { section in
                            LazyVStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Text(section.icon)
                                        .font(.system(size: 12))
                                    Text(section.label)
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundStyle(PopoverChrome.inkTertiary)
                                    Text("\(section.memos.count)")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundStyle(PopoverChrome.inkTertiary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(PopoverChrome.card.opacity(0.72), in: Capsule())
                                }

                                ForEach(section.memos) { memo in
                                    Toggle(isOn: Binding(
                                        get: { selectedMemoIDs.contains(memo.id) },
                                        set: { isSelected in
                                            if isSelected {
                                                selectedMemoIDs.insert(memo.id)
                                                validationMessage = nil
                                            } else {
                                                selectedMemoIDs.remove(memo.id)
                                            }
                                        }
                                    )) {
                                        AchievementMemoPickerRow(memo: memo)
                                    }
                                    .toggleStyle(.checkbox)
                                }
                            }
                        }
                    }
                    .padding(10)
                }
                .frame(maxHeight: linkableMemos.count > 5 ? 230 : nil)
                .popoverScrollbar()
                .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
            }
        }
    }

    private var emojiPicker: some View {
        HStack(spacing: 8) {
            Text(selectedEmoji)
                .font(.system(size: 20))
                .frame(width: 38, height: 36)
                .background(PopoverChrome.accentSoft, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))

            TextField("이모지", text: Binding(
                get: { selectedEmoji },
                set: { value in
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    selectedEmoji = trimmed.isEmpty ? "🎯" : String(trimmed.prefix(1))
                }
            ))
            .focused($isEmojiInputFocused)
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .padding(.horizontal, 10)
            .frame(width: 64, height: 36)
            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))

            Button {
                isEmojiInputFocused = true
                DispatchQueue.main.async {
                    NSApplication.shared.orderFrontCharacterPalette(nil)
                }
            } label: {
                Label("이모지 선택", systemImage: "face.smiling")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
            }
            .buttonStyle(.plain)
            .help("macOS 문자 뷰어 열기")
        }
    }

    private var colorPicker: some View {
        HStack(spacing: 7) {
            fieldLabel("색상")
            Spacer()
            ForEach(colors, id: \.self) { color in
                Button {
                    colorHex = color
                } label: {
                    Circle()
                        .fill(AchievementDataBuilder.color(from: color))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(colorHex == color ? PopoverChrome.ink : Color.clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var suggestionSourceMemos: [AchievementMemoDetail] {
        let weeklyLinkedIDs = Set(existingGoals.filter { $0.cadence == "주간" }.flatMap(\.sourceMemoIDs))
        return memos.filter { memo in
            !weeklyLinkedIDs.contains(memo.id) && isUsableSuggestionMemo(memo)
        }
    }

    private var linkableMemos: [AchievementMemoDetail] {
        memos.sorted(by: isMemoOrderedBefore)
    }

    /// 검색어로 좁힌 할일. 이미 고른 것은 사라지지 않도록 남긴다.
    private var visibleLinkableMemos: [AchievementMemoDetail] {
        let query = memoSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return linkableMemos }
        return linkableMemos.filter {
            $0.content.localizedCaseInsensitiveContains(query) || selectedMemoIDs.contains($0.id)
        }
    }

    private var memoPickerSections: [AchievementMemoPickerSection] {
        let iconRanks = Dictionary(uniqueKeysWithValues: MemoIcon.options.enumerated().map { ($0.element, $0.offset) })
        return Dictionary(grouping: visibleLinkableMemos, by: { $0.icon ?? MemoIcon.defaultIcon })
            .map { icon, memos in
                AchievementMemoPickerSection(
                    icon: icon,
                    label: MemoIcon.label(for: icon),
                    memos: memos.sorted(by: isMemoOrderedBefore)
                )
            }
            .sorted { lhs, rhs in
                let lhsRank = iconRanks[lhs.icon] ?? Int.max
                let rhsRank = iconRanks[rhs.icon] ?? Int.max
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                return lhs.label.localizedCompare(rhs.label) == .orderedAscending
            }
    }

    private func memoPickerDate(for memo: AchievementMemoDetail) -> Date? {
        [memo.startDate, memo.deadline].compactMap { $0 }.max()
    }

    private func isMemoOrderedBefore(_ lhs: AchievementMemoDetail, _ rhs: AchievementMemoDetail) -> Bool {
        let lhsDate = memoPickerDate(for: lhs)
        let rhsDate = memoPickerDate(for: rhs)

        switch (lhsDate, rhsDate) {
        case let (lhsDate?, rhsDate?):
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            break
        }

        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.content.localizedCompare(rhs.content) == .orderedAscending
    }

    private var excludedMemoIcons: Set<String> {
        let raw = excludedMemoIconsRaw == Constants.legacyAchievementSuggestionExcludedMemoIconsRaw
            ? Constants.defaultAchievementSuggestionExcludedMemoIconsRaw
            : excludedMemoIconsRaw
        let icons = raw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { MemoIcon.options.contains($0) }
        return Set(icons)
    }

    private func isUsableSuggestionMemo(_ memo: AchievementMemoDetail) -> Bool {
        let content = memo.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard content.count >= 3 else { return false }
        let icon = memo.icon ?? MemoIcon.defaultIcon
        if excludedMemoIcons.contains(icon) {
            return false
        }
        if icon == "🔗", content.localizedCaseInsensitiveContains("http") {
            return false
        }
        return true
    }

    private var weeklyGoalsForMonthlySuggestions: [AchievementGoal] {
        let weekly = existingGoals.filter { $0.cadence == "주간" }
        let unlinked = weekly.filter { ($0.monthGoal ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return unlinked
    }

    private var clampedWeeklySuggestionLimit: Int {
        clamped(weeklySuggestionLimit, in: Constants.achievementSuggestionCountRange)
    }

    private var clampedMaxTodosPerWeeklyGoal: Int {
        clamped(maxTodosPerWeeklyGoal, in: Constants.achievementSuggestionMaxTodoCountRange)
    }

    private var clampedMinWeeklyGoalsForMonthlySuggestions: Int {
        clamped(minWeeklyGoalsForMonthlySuggestions, in: Constants.achievementMonthlySuggestionMinWeeklyGoalCountRange)
    }

    private var clampedMonthlySuggestionLimit: Int {
        clamped(monthlySuggestionLimit, in: Constants.achievementMonthlySuggestionCountRange)
    }

    private var clampedMinTodosForWeeklySuggestions: Int {
        clamped(minTodosForWeeklySuggestions, in: Constants.achievementMinTodosForWeeklySuggestionsRange)
    }

    private var clampedMaxWeeklyGoalsPerMonthlyGoal: Int {
        clamped(maxWeeklyGoalsPerMonthlyGoal, in: Constants.achievementMaxWeeklyGoalsPerMonthlyGoalRange)
    }

    private func memo(for id: UUID) -> AchievementMemoDetail? {
        memos.first { $0.id == id }
    }

    private func goal(for id: UUID) -> AchievementGoal? {
        existingGoals.first { $0.id == id }
    }

    private func loadGoalSuggestions(force: Bool = false) {
        guard force || !isLoadingSuggestions else { return }
        // weekly
        let minTodosForWeeklySuggestions = clampedMinTodosForWeeklySuggestions // 추천 시작 기준: 할 일이 N개 이상일 때
        let weeklySuggestionLimit = clampedWeeklySuggestionLimit // 한 번에 보여줄 최대 주간 목표 수
        let maxTodosPerWeeklyGoal = clampedMaxTodosPerWeeklyGoal // 주간 목표 하나에 묶을 최대 할 일 수
        let weeklyTodoSnapshots = AchievementGoalSuggestionBuilder.snapshots(from: suggestionSourceMemos) // 주간 할 일 스냅샷. (주간 목표 추천 시 입력 데이터 복사본/필터를 통과한 할 일 목록)
        // monthly
        let minWeeklyGoalsForMonthlySuggestions = clampedMinWeeklyGoalsForMonthlySuggestions // 추천 시작 기준: 주간 목표가 N개 이상일 때
        let monthlySuggestionLimit = clampedMonthlySuggestionLimit // 한 번에 보여줄 최대 월간 목표 수
        let maxWeeklyGoalsPerMonthlyGoal = clampedMaxWeeklyGoalsPerMonthlyGoal // 월간 목표 하나에 묶을 최대 주간 목표 수
        let weeklyGoalSnapshots = AchievementGoalSuggestionBuilder.snapshots(from: weeklyGoalsForMonthlySuggestions) // 주간 목표 스냅샷. (월간 목표 추천 시 입력 데이터 복사본/필터를 통과한 주간 목표 목록)

        // 후보 할일이 너무 적으면 하나의 주간 목표로 의미 있게 묶을 수 없으므로 추천을 시작하지 않는다.
        let canSuggestWeekly = weeklyTodoSnapshots.count >= minTodosForWeeklySuggestions
        // 주간 목표가 충분히 쌓였을 때만, 그것들을 더 큰 월간 목표로 묶어 본다.
        let canSuggestMonthly = weeklyGoalSnapshots.count >= minWeeklyGoalsForMonthlySuggestions

        suggestions = []
        guidance = []
        suggestionMessage = canSuggestMonthly
            ? "할일과 주간 목표의 의미를 분석하고 있습니다."
            : "할일의 의미를 분석하고 있습니다."
        isLoadingSuggestions = true // '추천 중' 로딩 표시를 위한 플래그
        didLoadSuggestions = true

        // 버튼 한 번에 붙는 id. 주간·월간이 이 값을 공유해야 기록에서 한 실행으로 묶인다.
        let runID = AIRunLog.newRunID()
        // 목표 추천에는 사용자가 직접 남긴 참고 사항만 보탠다. 닉네임은 추천 근거가 아니므로
        // 컨텍스트에 넣지 않는다.
        let recommendationContext = GoalRecommendationContext(profile: CompanionUserProfile.load().note)

        Task {
            // 앞선 실행이 걸어 둔 언로드 예약을 취소한다. 지금 쓸 모델을 밑에서 걷어내면 안 된다.
            await SuggestionModelUnloader.shared.beginRun()
            // 공급자를 **여기서 한 번만** 읽는다. 주간·월간이 각자 읽으면 순차로 돌 때
            // 두 읽기 사이가 수십 초까지 벌어져, 그사이 설정을 바꾸면 한 실행 안에서
            // 공급자가 갈린다(실측 2026-08-19: 주간 mlx → 7초 뒤 월간 appleFoundation).
            // 버튼 한 번은 한 공급자로 끝나야 기록도 비교도 성립한다.
            let provider = AchievementFoundationGoalSuggestionProvider.selectedProvider
            // 어떻게 돌렸는지는 **기록에 남는다**(`RunRecord.variant`). 어느 쪽이 빠른지는
            // 공급자마다 다른데 지금 기본값은 관측에 기댄 추측이라, 뒤집어 재 볼 수 있어야 한다.
            let strategy = SuggestionExecutionStrategy.resolved(provider: provider)

            @Sendable func weeklyRun() async -> AchievementGoalRecommendationResult {
                guard canSuggestWeekly else { return .noSuggestion }
                return await AchievementFoundationGoalSuggestionProvider.suggestions(
                    from: weeklyTodoSnapshots,
                    suggestionCount: weeklySuggestionLimit,
                    maxMemoCount: maxTodosPerWeeklyGoal,
                    runID: runID,
                    candidateCount: weeklyTodoSnapshots.count,
                    variant: strategy.rawValue,
                    recommendationContext: recommendationContext,
                    provider: provider
                )
            }
            @Sendable func monthlyRun() async -> AchievementGoalRecommendationResult {
                guard canSuggestMonthly else { return .noSuggestion }
                return await AchievementFoundationGoalSuggestionProvider.monthlySuggestions(
                    from: weeklyGoalSnapshots,
                    suggestionCount: monthlySuggestionLimit,
                    maxGoalsPerSuggestion: maxWeeklyGoalsPerMonthlyGoal,
                    runID: runID,
                    candidateCount: weeklyGoalSnapshots.count,
                    variant: strategy.rawValue,
                    recommendationContext: recommendationContext,
                    provider: provider
                )
            }

            // 주간·월간을 동시에 보낼지, 하나씩 보낼지는 **공급자가 정한다.**
            //
            // 로컬 모델(Ollama·MLX)은 요청을 하나씩만 처리한다(실측 2026-08-19: 같은 모델에
            // 두 요청을 동시에 보내면 뒤엣것이 18.6초를 한 글자도 못 받고 기다렸다). 그런데
            // 60초 타임아웃은 **보낸 순간부터** 도므로, 기다린 시간이 자기 몫에서 깎여 나간다.
            // 실측에서 타임아웃 14건 중 11건이 이 모양이었다 — 같은 실행의 다른 태스크가
            // 같은 공급자로 성공하는 동안 이쪽은 큐에서 예산을 다 쓰고 죽었다.
            //
            // 순차로 바꿔도 **총 시간은 그대로다.** 어차피 하나씩 처리되고 있었고,
            // 달라지는 건 타이머가 자기 차례에 시작한다는 것뿐이다.
            //
            // AFM 은 반대다. 앱 밖(시스템)에서 돌아 진짜로 겹쳐 실행되고(실측: 24.0초짜리와
            // 43.8초짜리가 겹쳐서 43.8초에 끝났다), 105건 중 타임아웃이 0건이다. 여기까지
            // 순차로 만들면 얻는 것 없이 느려지기만 한다.
            let weeklyModelValue: AchievementGoalRecommendationResult
            let monthlyModelValue: AchievementGoalRecommendationResult
            switch strategy {
            case .parallel:
                async let weekly = weeklyRun()
                async let monthly = monthlyRun()
                (weeklyModelValue, monthlyModelValue) = await (weekly, monthly)
            case .sequential:
                weeklyModelValue = await weeklyRun()
                monthlyModelValue = await monthlyRun()
            }
            // 주간·월간이 **모두** 돌아온 뒤에 유예 타이머를 건다. 한쪽만 끝났을 때 걸면
            // 아직 도는 쪽이 쓰던 모델을 30초 뒤에 뺏는다.
            await SuggestionModelUnloader.shared.endRun()
            await MainActor.run {
                let weeklyModel = mergeSuggestions(
                    weeklyModelValue.suggestions,
                    cadence: .weekly,
                    displayLimit: weeklySuggestionLimit
                )
                let monthlyModel = mergeSuggestions(
                    monthlyModelValue.suggestions,
                    cadence: .monthly,
                    displayLimit: monthlySuggestionLimit
                )

                // AI 결과가 유효하지 않을 때만 규칙 기반 폴백을 만든다.
                let weeklyGuidance = weeklyModelValue.guidance
                let monthlyGuidance = monthlyModelValue.guidance
                let weeklyRuleSuggestions = weeklyModelValue.shouldFallbackToNextProvider && canSuggestWeekly
                    ? AchievementGoalSuggestionBuilder.ruleBasedSuggestions(
                        from: weeklyTodoSnapshots,
                        suggestionCount: weeklySuggestionLimit,
                        maxMemoCount: maxTodosPerWeeklyGoal
                    )
                    : []
                let monthlyRuleSuggestions = monthlyModelValue.shouldFallbackToNextProvider && canSuggestMonthly
                    ? AchievementGoalSuggestionBuilder.monthlyRuleBasedSuggestions(
                        from: weeklyGoalSnapshots,
                        suggestionCount: monthlySuggestionLimit,
                        maxGoalsPerSuggestion: maxWeeklyGoalsPerMonthlyGoal
                    )
                    : []

                let weekly = weeklyModel.suggestions.isEmpty
                    ? mergeSuggestions(weeklyRuleSuggestions, cadence: .weekly, displayLimit: weeklySuggestionLimit).suggestions
                    : weeklyModel.suggestions
                let monthly = monthlyModel.suggestions.isEmpty
                    ? mergeSuggestions(monthlyRuleSuggestions, cadence: .monthly, displayLimit: monthlySuggestionLimit).suggestions
                    : monthlyModel.suggestions

                // 룰이 대신 만든 경우도 **기록에 남긴다.** 오래도록 안 남겨서, 화면에는 떴는데
                // AI 실험실에는 없는 상태였다 — «모델이 실패했는데 사용자는 결과를 봤다» 가
                // 통째로 안 보였다. 채택률을 룰과 모델로 나눠 재려면 이 줄이 있어야 한다.
                if weeklyModel.suggestions.isEmpty && weeklyGuidance.isEmpty {
                    AIRunLog.recordRuleFallback(
                        runID: runID, task: "weekly_goal",
                        candidateCount: weeklyTodoSnapshots.count, suggestions: weekly
                    )
                }
                if canSuggestMonthly, monthlyModel.suggestions.isEmpty && monthlyGuidance.isEmpty {
                    AIRunLog.recordRuleFallback(
                        runID: runID, task: "monthly_goal",
                        candidateCount: weeklyGoalSnapshots.count, suggestions: monthly
                    )
                }
                logSuggestionFunnel(
                    cadence: .weekly,
                    inputCount: weeklyTodoSnapshots.count,
                    modelParsed: weeklyModelValue.suggestions.count,
                    stats: weeklyModel.stats,
                    shownCount: weekly.count
                )
                if canSuggestMonthly {
                    logSuggestionFunnel(
                        cadence: .monthly,
                        inputCount: weeklyGoalSnapshots.count,
                        modelParsed: monthlyModelValue.suggestions.count,
                        stats: monthlyModel.stats,
                        shownCount: monthly.count
                    )
                }
                suggestions = weekly + monthly
                guidance = weeklyGuidance + monthlyGuidance
                isLoadingSuggestions = false
                if !guidance.isEmpty {
                    suggestionMessage = "지금 입력만으로는 목표를 묶기 어려워, 항목별로 구체화할 방법을 안내합니다."
                } else if weeklyModel.suggestions.isEmpty && monthlyModel.suggestions.isEmpty {
                    suggestionMessage = finalRuleSuggestionMessage(
                        weeklyCount: weekly.count,
                        monthlyCount: monthly.count,
                        canSuggestWeekly: canSuggestWeekly,
                        weeklyTodoMinimum: minTodosForWeeklySuggestions,
                        canSuggestMonthly: canSuggestMonthly,
                        monthlyMinWeeklyCount: minWeeklyGoalsForMonthlySuggestions
                    )
                } else if weeklyModel.suggestions.isEmpty || (canSuggestMonthly && monthlyModel.suggestions.isEmpty) {
                    // 모델이 못 만들어 **규칙이 대신한** 경우. 예전에는 «만들었습니다» 라고만 해서
                    // 사용자가 AI 결과를 받은 줄 알았다.
                    suggestionMessage = "AI가 묶음을 만들지 못해 규칙으로 묶었습니다. 다시 시도하면 달라질 수 있습니다."
                } else if canSuggestMonthly && monthly.isEmpty {
                    // 월간을 시도했는데 하나도 못 만든 경우. 예전에는 «만들었습니다» 라고만 해서
                    // 사용자가 **월간이 왜 없는지 모른 채** 빈 자리를 봤다.
                    //
                    // 이유까지는 말하지 않는다. 실측(2026-08-19/20)에서 원인이 셋으로 갈렸는데
                    // (묶을 게 없음 · 응답 잘림 · 산문만 냄), 사용자가 할 수 있는 일은
                    // «다시 눌러 보기» 로 같다. 원인은 기록(`RunRecord.parse`)에 남는다.
                    suggestionMessage = "주간 목표 초안을 만들었습니다. 이번엔 함께 묶을 만한 주간 목표를 찾지 못해 월간 목표는 비워 뒀습니다."
                } else {
                    suggestionMessage = "할일과 주간 목표의 의미를 보고 목표 초안을 만들었습니다."
                }
            }
        }
    }

    private func reloadSuggestionsAfterSettingsChange() {
        guard didLoadSuggestions else { return }
        expandedSuggestionKeys.removeAll()
        suggestions = []
        if selectedInputMode == "AI 추천" {
            loadGoalSuggestions(force: true)
        } else {
            didLoadSuggestions = false
            suggestionMessage = nil
        }
    }

    private func mergeSuggestions(_ values: [AchievementGoalSuggestion]) -> [AchievementGoalSuggestion] {
        let weekly = mergeSuggestions(values, cadence: .weekly, displayLimit: clampedWeeklySuggestionLimit)
        let monthly = mergeSuggestions(values, cadence: .monthly, displayLimit: clampedMonthlySuggestionLimit)
        return weekly.suggestions + monthly.suggestions
    }

    /// 추천 한 번의 퍼널을 한 줄로 남긴다. 재료 → 모델 파싱 → 필터 → 노출 순서로 어디서 잃었는지 보인다.
    private func logSuggestionFunnel(
        cadence: AchievementGoalCadence,
        inputCount: Int,
        modelParsed: Int,
        stats: AchievementSuggestionFilterStats,
        shownCount: Int
    ) {
        // 모델 결과가 필터를 하나도 통과하지 못하면 룰 기반으로 대체된다.
        let usedRuleFallback = stats.shown == 0
        achievementSuggestionLog.info(
            """
            funnel cadence=\(cadence.levelName, privacy: .public) \
            input=\(inputCount, privacy: .public) parsed=\(modelParsed, privacy: .public) \
            \(stats.summary, privacy: .public) \
            fallback=\(usedRuleFallback, privacy: .public) final=\(shownCount, privacy: .public) \
            dismissedKeys=\(self.dismissedSuggestionKeys.count, privacy: .public)
            """
        )
    }

    private func mergeSuggestions(
        _ values: [AchievementGoalSuggestion],
        cadence: AchievementGoalCadence,
        displayLimit: Int
    ) -> (suggestions: [AchievementGoalSuggestion], stats: AchievementSuggestionFilterStats) {
        var seen = Set<Set<UUID>>()
        var result: [AchievementGoalSuggestion] = []
        var stats = AchievementSuggestionFilterStats()
        for suggestion in values where suggestion.cadence == cadence {
            if let reason = rejectionReason(for: suggestion) {
                switch reason {
                case .shortTitle: stats.shortTitle += 1
                case .toolNameTitle: stats.toolNameTitle += 1
                case .insufficientIDs: stats.insufficientIDs += 1
                }
                continue
            }
            let keyIDs = cadence == .monthly ? suggestion.childGoalIDs : suggestion.memoIDs
            guard !dismissedSuggestionKeys.contains(suggestionKey(for: suggestion)) else {
                stats.dismissed += 1
                continue
            }
            let key = Set(keyIDs)
            guard seen.insert(key).inserted else {
                stats.duplicate += 1
                continue
            }
            result.append(suggestion)
        }
        stats.overflow = max(0, result.count - displayLimit)
        let shown = Array(result.prefix(displayLimit))
        stats.shown = shown.count
        return (shown, stats)
    }

    private func dismissSuggestion(_ suggestion: AchievementGoalSuggestion) {
        // 명시적 거절은 **무반응과 다른 신호**다. 그냥 안 고른 것은 «못 봤다» 일 수도 있지만
        // ✕ 를 누른 것은 «보고 버렸다» 이다.
        AIRunLog.recordDismissal(suggestion: suggestion)
        let key = suggestionKey(for: suggestion)
        var keys = dismissedSuggestionKeys
        keys.insert(key)
        dismissedSuggestionKeysRaw = encodeDismissedSuggestionKeys(keys)
        expandedSuggestionKeys.remove(key)
        suggestions.removeAll { suggestionKey(for: $0) == key }
        if suggestions.isEmpty {
            suggestionMessage = "제외하지 않은 추천 묶음이 없습니다. 다시 추천을 받아볼 수 있습니다."
        }
    }

    private var dismissedSuggestionKeys: Set<String> {
        Set(dismissedSuggestionKeysRaw
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
    }

    private func encodeDismissedSuggestionKeys(_ keys: Set<String>) -> String {
        keys.sorted().joined(separator: "\n")
    }

    private func visibleMemoIDs(for suggestion: AchievementGoalSuggestion) -> [UUID] {
        isSuggestionExpanded(suggestion) ? suggestion.memoIDs : Array(suggestion.memoIDs.prefix(3))
    }

    private func visibleChildGoalIDs(for suggestion: AchievementGoalSuggestion) -> [UUID] {
        isSuggestionExpanded(suggestion) ? suggestion.childGoalIDs : Array(suggestion.childGoalIDs.prefix(3))
    }

    private func isSuggestionExpanded(_ suggestion: AchievementGoalSuggestion) -> Bool {
        expandedSuggestionKeys.contains(suggestionKey(for: suggestion))
    }

    private func toggleSuggestionExpansion(_ suggestion: AchievementGoalSuggestion) {
        let key = suggestionKey(for: suggestion)
        if expandedSuggestionKeys.contains(key) {
            expandedSuggestionKeys.remove(key)
        } else {
            expandedSuggestionKeys.insert(key)
        }
    }

    private func suggestionKey(for suggestion: AchievementGoalSuggestion) -> String {
        let ids = (suggestion.cadence == .monthly ? suggestion.childGoalIDs : suggestion.memoIDs)
            .map(\.uuidString)
            .sorted()
            .joined(separator: ",")
        return "\(suggestion.cadence.rawValue):\(ids)"
    }

    private func rejectionReason(for suggestion: AchievementGoalSuggestion) -> AchievementSuggestionRejection? {
        let title = suggestion.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.count >= 4 else { return .shortTitle }

        // 이루려는 상태가 아니라 도구·형식 이름을 그대로 제목으로 삼은 추천은 목표로 쓸 수 없다.
        let lowercasedTitle = title.lowercased()
        let toolNameTitles = [
            "markdown 목표",
            "kakaotalk 목표",
            "obsidian 목표",
            "링크 정리 목표",
        ]
        if toolNameTitles.contains(where: { lowercasedTitle.contains($0) }) {
            return .toolNameTitle
        }

        let keyIDs = suggestion.cadence == .monthly ? suggestion.childGoalIDs : suggestion.memoIDs
        return Set(keyIDs).count >= 2 ? nil : .insufficientIDs
    }

    private func applySuggestion(_ suggestion: AchievementGoalSuggestion) {
        appliedSuggestion = suggestion
        selectedInputMode = "직접 입력"
        selectedTargetLevel = suggestion.cadence.levelName
        selectedEmoji = suggestion.emoji
        title = suggestion.title
        selectedMemoIDs = suggestion.cadence == .weekly ? Set(suggestion.memoIDs) : []
        selectedChildGoalIDs = suggestion.cadence == .monthly ? Set(suggestion.childGoalIDs) : []
        applyCommonHierarchy(from: suggestion)
        targetValueText = suggestion.targetValueText
        periodText = suggestion.cadence.periodText
        criterion = suggestion.criterion
        validationMessage = nil
    }

    private func applyCommonHierarchy(from suggestion: AchievementGoalSuggestion) {
        guard suggestion.cadence == .monthly else { return }
        let childGoals = existingGoals.filter { suggestion.childGoalIDs.contains($0.id) }
        if let roleName = commonNonEmpty(childGoals.map(\.roleName)) {
            selectedPersonaTitle = roleName
        }
        if let vision = commonNonEmpty(childGoals.map(\.vision)) {
            selectedVisionTitle = vision
        }
    }

    private func commonNonEmpty(_ values: [String]) -> String? {
        let trimmed = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard let first = trimmed.first, trimmed.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    private func initialSuggestionMessage(weeklyCount: Int, monthlyCount: Int, canSuggestMonthly: Bool) -> String {
        if weeklyCount == 0 && monthlyCount == 0 {
            return canSuggestMonthly
                ? "직접 선택할 수 있는 목표는 있지만 자동 묶음은 아직 없습니다."
                : "주간 목표가 더 쌓이면 월간 목표 추천도 함께 보여줍니다."
        }
        if monthlyCount > 0 {
            return "할일 묶음과 주간 목표 묶음을 함께 만들었습니다."
        }
        return "비슷한 할일을 묶어 주간 목표 초안을 만들었습니다."
    }

    private func finalRuleSuggestionMessage(
        weeklyCount: Int,
        monthlyCount: Int,
        canSuggestWeekly: Bool,
        weeklyTodoMinimum: Int,
        canSuggestMonthly: Bool,
        monthlyMinWeeklyCount: Int
    ) -> String {
        if weeklyCount == 0 && monthlyCount == 0 {
            if !canSuggestWeekly {
                return "할일이 (weeklyTodoMinimum)개 이상 쌓이면 주간 목표를 추천합니다."
            }
            return canSuggestMonthly
                ? "추천할 묶음이 없습니다. 직접 목표를 선택해 만들 수 있습니다."
                : "주간 목표가 \(monthlyMinWeeklyCount)개 이상 쌓이면 월간 목표도 추천합니다."
        }
        if monthlyCount > 0 {
            return "할일과 주간 목표를 묶어 목표 초안을 만들었습니다."
        }
        return "비슷한 할일을 묶어 주간 목표 초안을 만들었습니다."
    }

    /// 제목만 있으면 만들 수 있다.
    /// 할일·하위 목표 연결은 지금 해도 되고 나중에 목표 관리에서 이어도 된다.
    private var canSave: Bool {
        selectedInputMode == "직접 입력"
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var supportsPersonaVisionGroup: Bool {
        ["비전", "월간", "주간"].contains(selectedTargetLevel)
    }

    private var shouldShowMemoPicker: Bool {
        showsMemoPicker(for: selectedTargetLevel)
    }

    private var personaGoals: [AchievementGoal] {
        existingGoals.filter { $0.cadence == "역할" }
    }

    private var visionCandidates: [AchievementGoal] {
        existingGoals.filter { goal in
            guard goal.cadence == "비전" else { return false }
            return selectedPersonaTitle.isEmpty || goal.roleName == selectedPersonaTitle
        }
    }

    private var selectedPersonaGoal: AchievementGoal? {
        personaGoals.first { $0.title == selectedPersonaTitle }
    }

    private var selectedVisionGoal: AchievementGoal? {
        existingGoals.first { $0.cadence == "비전" && $0.title == selectedVisionTitle }
    }

    private var childGoalLevel: String? {
        childGoalLevel(for: selectedTargetLevel)
    }

    private var childGoalCandidates: [AchievementGoal] {
        childGoalCandidates(for: selectedTargetLevel)
    }

    private func childGoalLevel(for level: String) -> String? {
        switch level {
        case "비전":
            return "월간"
        case "월간":
            return "주간"
        default:
            return nil
        }
    }

    private func childGoalCandidates(for level: String) -> [AchievementGoal] {
        guard let childLevel = childGoalLevel(for: level) else { return [] }
        return existingGoals.filter { goal in
            guard goal.cadence == childLevel else {
                return false
            }
            if !selectedPersonaTitle.isEmpty, goal.roleName != selectedPersonaTitle {
                return false
            }
            if !selectedVisionTitle.isEmpty, goal.vision != selectedVisionTitle {
                return false
            }
            return true
        }
    }

    private var defaultTargetValueText: String {
        "\(max(1, selectedSourceCount))개"
    }

    private var selectedSourceCount: Int {
        if shouldShowMemoPicker {
            return selectedLinkableMemoIDs.count
        }
        return selectedChildGoalIDs.count + pendingNewChildTitles.count
    }

    /// 저장할 때 함께 만들 하위 목표. 현재 단계에 하위가 없으면 비운다.
    private var pendingNewChildTitles: [String] {
        childGoalLevel == nil ? [] : newChildTitles
    }

    private var selectedLinkableMemoIDs: Set<UUID> {
        selectedMemoIDs.intersection(Set(linkableMemos.map(\.id)))
    }

    private func defaultPeriodText(for level: String) -> String {
        switch level {
        case "월간":
            return "이번 달"
        case "주간":
            return "이번 주"
        case "비전":
            return "장기"
        default:
            return "계속"
        }
    }

    private func periodText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일까지"
        return formatter.string(from: date)
    }

    private func defaultCriterionText(for level: String, linkedMemoCount: Int, childGoalCount: Int) -> String {
        switch level {
        case "월간":
            return "연결한 주간 목표 \(max(1, childGoalCount))개 달성"
        case "비전":
            return childGoalCount > 0 ? "연결한 월간 목표 \(childGoalCount)개 달성" : "비전 방향 유지"
        case "역할":
            return "페르소나 방향 유지"
        default:
            return "연결한 할일 \(max(1, linkedMemoCount))개 완료"
        }
    }

    private var goalPlaceholder: String {
        switch selectedTargetLevel {
        case "역할": return "예: AI 엔지니어"
        case "비전": return "예: RAG 제품을 출시한다"
        case "월간": return "예: 검색 품질 개선"
        default: return "예: 딥워크 주 5시간"
        }
    }

    private func targetLevelSubtitle(for level: String) -> String? {
        switch level {
        case "역할":
            return "(페르소나)"
        case "비전":
            return "(지향점)"
        default:
            return nil
        }
    }

    private var breadcrumbText: String {
        targetLevels.joined(separator: " · ")
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(PopoverChrome.inkTertiary)
    }

    private func pickerLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
                .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(PopoverChrome.inkSecondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
    }

    private func save() {
        validationMessage = nil
        guard selectedInputMode == "직접 입력" else {
            validationMessage = "AI 추천은 아직 준비 중입니다. 직접 입력으로 등록해 주세요."
            return
        }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationMessage = "\(selectedTargetLevel) 목표를 입력해 주세요."
            return
        }
        let trimmedTitle = AchievementDataBuilder.shortText(title, limit: 40)
        let childGoals = existingGoals.filter { selectedChildGoalIDs.contains($0.id) }
        let linkedMemoIDs = Array(selectedLinkableMemoIDs.union(childGoals.flatMap(\.sourceMemoIDs)))
        let hierarchy = hierarchyValues(title: trimmedTitle)
        let resolvedTargetValueText = optionalText(targetValueText) ?? defaultTargetValueText
        let resolvedPeriodText = optionalText(periodText) ?? defaultPeriodText(for: selectedTargetLevel)
        let resolvedCriterion = optionalText(criterion) ?? defaultCriterionText(
            for: selectedTargetLevel,
            linkedMemoCount: linkedMemoIDs.count,
            childGoalCount: selectedChildGoalIDs.count + pendingNewChildTitles.count
        )
        let draft = AchievementGoalDraft(
            title: trimmedTitle,
            emoji: selectedEmoji,
            cadence: selectedTargetLevel,
            rule: resolvedCriterion,
            targetCount: max(1, linkedMemoIDs.count),
            targetValueText: resolvedTargetValueText,
            periodText: resolvedPeriodText,
            dueDate: hasDueDate ? selectedPeriodDate : nil,
            colorHex: colorHex,
            roleName: hierarchy.roleName,
            vision: hierarchy.vision,
            yearGoal: hierarchy.yearGoal,
            monthGoal: hierarchy.monthGoal,
            linkedMemoIDs: linkedMemoIDs,
            // 추천에서 온 목표면 출처를 심는다. 직접 만든 목표는 `nil` 로 남아 둘이 갈린다.
            sourceRunID: appliedSuggestion?.runID,
            sourceSuggestionID: appliedSuggestion?.id
        )
        do {
            let goalID = try onSave(draft, selectedChildGoalIDs, pendingNewChildTitles)
            if let applied = appliedSuggestion {
                AIRunLog.recordAdoption(suggestion: applied, goalID: goalID, titleEdited: applied.title != trimmedTitle)
            }
            onClose()
        } catch {
            validationMessage = "목표 저장에 실패했습니다: \(error.localizedDescription)"
        }
    }

    private func hierarchyValues(title: String) -> (roleName: String, vision: String, yearGoal: String?, monthGoal: String?) {
        let roleName = selectedPersonaGoal?.title ?? selectedVisionGoal?.roleName ?? ""
        let vision = selectedVisionGoal?.title ?? ""

        switch selectedTargetLevel {
        case "역할":
            return (title, "", nil, nil)
        case "비전":
            return (selectedPersonaGoal?.title ?? "", title, nil, nil)
        case "월간":
            return (roleName, vision, nil, nil)
        default:
            return (roleName, vision, nil, nil)
        }
    }

    private func emoji(for level: String) -> String {
        switch level {
        case "역할": return "👤"
        case "비전": return "🧭"
        case "월간": return "📅"
        default: return "🎯"
        }
    }

    private func showsMemoPicker(for level: String) -> Bool {
        level == "주간"
    }

    private func optionalText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func clamped(_ value: Int, in range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
