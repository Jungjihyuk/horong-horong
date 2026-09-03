import Foundation
import SwiftUI

/// 설정 → 몰입. 개인화 비교 상태와 최근 10분 판정 규칙을 한 화면에서 조절한다.
struct FocusPage: View {
    let repository: StatsRecordRepository

    @AppStorage(Constants.AppStorageKey.companionFocusNudgeEnabled)
    private var isEnabled: Bool = Constants.defaultCompanionFocusNudgeEnabled
    @AppStorage(Constants.AppStorageKey.companionFocusNudgeMessages)
    private var messages: String = ""
    @AppStorage(Constants.AppStorageKey.companionFocusNudgeDetectionMode)
    private var detectionModeRawValue = Constants.defaultFocusNudgeDetectionMode.rawValue
    @AppStorage(Constants.AppStorageKey.companionFocusNudgeRequiredFeedbackCount)
    private var requiredFeedbackCount = Constants.defaultFocusNudgeRequiredFeedbackCount
    @AppStorage(Constants.AppStorageKey.companionFocusNudgeManualFocusPercent)
    private var manualFocusPercent = Constants.defaultFocusNudgeManualFocusPercent
    @AppStorage(Constants.AppStorageKey.companionFocusNudgeManualMaxAppSwitches)
    private var manualMaximumAppSwitches = Constants.defaultFocusNudgeManualMaxAppSwitches
    @AppStorage(Constants.AppStorageKey.companionFocusNudgeFrequencyMode)
    private var frequencyModeRawValue = Constants.defaultFocusNudgeFrequencyMode.rawValue
    @AppStorage(Constants.AppStorageKey.companionFocusNudgeMaximumPerSession)
    private var maximumNudgesPerSession = Constants.defaultFocusNudgeMaximumPerSession

    @State private var personalization: FocusPersonalizationAnalysis?

    private var detectionMode: FocusNudgeDetectionMode {
        FocusNudgeDetectionMode(rawValue: detectionModeRawValue)
            ?? Constants.defaultFocusNudgeDetectionMode
    }

    private var frequencyMode: FocusNudgeFrequencyMode {
        FocusNudgeFrequencyMode(rawValue: frequencyModeRawValue)
            ?? Constants.defaultFocusNudgeFrequencyMode
    }

    var body: some View {
        SettingsPageScroll {
            SettingsPageHeader(title: SettingsTab.focus.label, subtitle: SettingsTab.focus.subtitle)

            SettingsGroupCard("집중 넛지") {
                SettingsRow(
                    "최근 10분의 흐트러짐 감지",
                    subtitle: "기준을 벗어나면 이유와 측정값을 함께 알려줍니다."
                ) {
                    Toggle("", isOn: $isEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("판정 방식")
                        .font(.callout)

                    HStack(alignment: .top, spacing: 10) {
                        automaticDetectionModeCard
                        manualDetectionModeCard
                    }

                    if detectionMode == .personalized,
                       let personalization,
                       !personalization.hasEnoughFeedback {
                        Label(
                            "필요한 회고가 모일 때까지 규칙 기반을 적용합니다.",
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }

            if detectionMode == .personalized {
                personalizationCard
            } else {
                ruleCard(title: "규칙 기반 기준")
            }

            frequencyCard
            messageCard
        }
        .task { loadPersonalization() }
        .onChange(of: detectionModeRawValue) { _, _ in loadPersonalization() }
        .onChange(of: requiredFeedbackCount) { _, newValue in
            let clamped = FocusNudgeSettingsStore.clampedFeedbackCount(newValue)
            if clamped != newValue {
                requiredFeedbackCount = clamped
            } else {
                loadPersonalization()
            }
        }
    }

    // MARK: - 판정 방식 선택

    private var automaticDetectionModeCard: some View {
        let isSelected = detectionMode == .personalized
        let isPersonalized = isPersonalizedRuleCurrentlyApplied

        return detectionModeCard(
            .personalized,
            title: "개인 회고 기반",
            systemImage: "person.text.rectangle",
            accessibilityValue: automaticModeAccessibilityValue
        ) {
            HStack(spacing: 8) {
                detectionStateNode(
                    "규칙",
                    systemImage: "slider.horizontal.3",
                    color: .orange,
                    isActive: isSelected && !isPersonalized
                )

                automaticTransitionConnector(
                    isSelected: isSelected,
                    isComplete: isPersonalized
                )

                detectionStateNode(
                    "개인",
                    systemImage: "person.crop.circle",
                    color: .green,
                    isActive: isSelected && isPersonalized
                )
            }
        }
    }

    private var manualDetectionModeCard: some View {
        let isSelected = detectionMode == .ruleBased

        return detectionModeCard(
            .ruleBased,
            title: "규칙 기반",
            systemImage: "slider.horizontal.3",
            accessibilityValue: isSelected
                ? "선택됨, 규칙 기반 적용 중"
                : "선택 안 됨"
        ) {
            HStack {
                Spacer()
                detectionStateNode(
                    "내 규칙",
                    systemImage: "ruler",
                    color: Color.accentColor,
                    isActive: isSelected
                )
                Spacer()
            }
        }
    }

    private func detectionModeCard<Content: View>(
        _ mode: FocusNudgeDetectionMode,
        title: String,
        systemImage: String,
        accessibilityValue: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isSelected = detectionMode == mode

        return Button {
            detectionModeRawValue = mode.rawValue
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: systemImage)
                    Text(title)
                        .fontWeight(.semibold)
                    Spacer(minLength: 6)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                }
                .font(.caption)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                content()
                    .frame(maxWidth: .infinity)
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.08)
                            : Color.primary.opacity(0.03)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(
                        isSelected
                            ? Color.accentColor.opacity(0.55)
                            : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 1.2 : 0.6
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
    }

    private func detectionStateNode(
        _ title: String,
        systemImage: String,
        color: Color,
        isActive: Bool
    ) -> some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(isActive ? color.opacity(0.18) : Color.primary.opacity(0.045))
                Circle()
                    .stroke(
                        isActive ? color.opacity(0.65) : Color.primary.opacity(0.10),
                        lineWidth: isActive ? 1.2 : 0.6
                    )
                Image(systemName: systemImage)
                    .font(.caption.bold())
                    .foregroundStyle(isActive ? color : Color.secondary)
            }
            .frame(width: 30, height: 30)

            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(isActive ? color : Color.secondary)
                .lineLimit(1)
        }
        .frame(minWidth: 42)
    }

    private func automaticTransitionConnector(
        isSelected: Bool,
        isComplete: Bool
    ) -> some View {
        let count = automaticTransitionProgressCount
        let ratio = automaticTransitionProgressRatio
        let color = isComplete ? Color.green : Color.orange

        return VStack(spacing: 5) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(color.opacity(isSelected ? 0.85 : 0.30))
                        .frame(width: geometry.size.width * ratio)
                }
            }
            .frame(height: 4)

            if isComplete {
                Image(systemName: "checkmark")
                    .font(.caption2.bold())
                    .foregroundStyle(isSelected ? Color.green : Color.secondary)
            } else {
                Text("\(count)/\(requiredFeedbackCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var isPersonalizedRuleCurrentlyApplied: Bool {
        detectionMode == .personalized
            && personalization?.isReady == true
            && personalization?.suggestedRule != nil
    }

    private var automaticTransitionProgressCount: Int {
        guard let personalization else { return 0 }
        return min(
            min(
                personalization.focusedFeedbackCount,
                personalization.distractedFeedbackCount
            ),
            personalization.requiredFeedbackCount
        )
    }

    private var automaticTransitionProgressRatio: Double {
        guard let personalization, personalization.requiredFeedbackCount > 0 else { return 0 }
        return min(
            Double(automaticTransitionProgressCount)
                / Double(personalization.requiredFeedbackCount),
            1
        )
    }

    private var automaticModeAccessibilityValue: String {
        guard detectionMode == .personalized else { return "선택 안 됨" }
        if isPersonalizedRuleCurrentlyApplied {
            return "선택됨, 개인 기준 적용 중"
        }
        return "선택됨, 규칙 기반 적용 중, 회고 \(automaticTransitionProgressCount)"
            + "/\(requiredFeedbackCount)"
    }

    // MARK: - 개인화

    private var personalizationCard: some View {
        SettingsGroupCard("개인화") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Label("비교할 회고 수", systemImage: "slider.horizontal.3")
                            .font(.callout)
                        Spacer()
                        Text("각 \(requiredFeedbackCount)개")
                            .font(.callout.bold().monospacedDigit())
                    }

                    Slider(
                        value: feedbackCountBinding,
                        in: 10...100,
                        step: 5
                    )
                    .disabled(!isEnabled)
                    .accessibilityLabel("결과별로 비교할 회고 개수")
                    .accessibilityValue("집중 잘함과 흐트러짐 각각 \(requiredFeedbackCount)개")
                }

                Divider()

                if let personalization {
                    currentAppliedRule(personalization)

                    Divider()

                    feedbackProgress(personalization)

                    if !personalization.isReady {
                        learningStatus(personalization)
                    }
                    evidenceView(
                        personalization.evidence,
                        rule: personalization.isReady ? personalization.suggestedRule : nil
                    )
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }

    private func feedbackProgress(_ analysis: FocusPersonalizationAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("각 결과의 최근 회고를 따로 비교합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(personalizationStateLabel(analysis))
                    .font(.caption2.bold())
                    .foregroundStyle(analysis.isReady ? Color.green : Color.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill((analysis.isReady ? Color.green : Color.secondary).opacity(0.12))
                    )
            }

            HStack(spacing: 10) {
                feedbackGroupProgress(
                    "집중 잘함",
                    count: analysis.focusedFeedbackCount,
                    requiredCount: analysis.requiredFeedbackCount,
                    systemImage: "checkmark.circle.fill",
                    color: .green
                )
                feedbackGroupProgress(
                    "흐트러짐",
                    count: analysis.distractedFeedbackCount,
                    requiredCount: analysis.requiredFeedbackCount,
                    systemImage: "arrow.triangle.branch",
                    color: .orange
                )
            }
        }
    }

    private func feedbackGroupProgress(
        _ title: String,
        count: Int,
        requiredCount: Int,
        systemImage: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .foregroundStyle(color)
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text("\(count)/\(requiredCount)")
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            ProgressView(
                value: min(Double(count) / Double(requiredCount), 1)
            )
            .tint(color)
        }
        .font(.caption)
        .padding(9)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
    }

    private func currentAppliedRule(_ analysis: FocusPersonalizationAnalysis) -> some View {
        let personalizedRule = analysis.isReady ? analysis.suggestedRule : nil
        let rule = personalizedRule ?? manualRule
        let isPersonalized = personalizedRule != nil
        let color = isPersonalized ? Color.green : Color.orange
        let fallbackMessage = analysis.hasEnoughFeedback
            ? "현재 회고에서는 구분 가능한 개인 기준을 찾지 못해 규칙 기반을 사용합니다."
            : "비교할 회고가 충분해지면 개인 기준으로 자동 전환됩니다."

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("현재 적용 기준", systemImage: "scope")
                    .font(.callout.bold())
                Spacer()
                tenMinuteWindowBadge
                Label(
                    isPersonalized ? "개인 기준 적용 중" : "규칙 기반 적용 중",
                    systemImage: isPersonalized
                        ? "checkmark.circle.fill"
                        : "arrow.triangle.2.circlepath"
                )
                .font(.caption.bold())
                .foregroundStyle(color)
            }

            HStack(spacing: 10) {
                readOnlyRuleValue(
                    systemImage: "timer",
                    value: "\(Self.focusDurationText(ratio: rule.minimumFocusRatio)) 이상",
                    detail: "최근 10분 중 \(Self.percent(rule.minimumFocusRatio))%"
                )
                readOnlyRuleValue(
                    systemImage: "arrow.left.arrow.right",
                    value: "\(rule.maximumAppSwitches)회 이하",
                    detail: "최근 10분 내 앱 전환"
                )
            }

            if !isPersonalized {
                Label(
                    fallbackMessage,
                    systemImage: "arrow.right.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(color.opacity(0.18), lineWidth: 0.5)
        )
    }

    private var manualRule: FocusNudgeDetectionRule {
        FocusNudgeDetectionRule(
            minimumFocusRatio: Double(manualFocusPercent) / 100,
            maximumAppSwitches: manualMaximumAppSwitches
        )
    }

    private func readOnlyRuleValue(
        systemImage: String,
        value: String,
        detail: String
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.callout.bold().monospacedDigit())
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
    }

    @ViewBuilder
    private func evidenceView(
        _ evidence: FocusPersonalizationEvidence,
        rule: FocusNudgeDetectionRule?
    ) -> some View {
        if let focusedRatio = evidence.focusedAverageFocusRatio,
           let distractedRatio = evidence.distractedAverageFocusRatio,
           let focusedSwitches = evidence.focusedAverageAppSwitches,
           let distractedSwitches = evidence.distractedAverageAppSwitches {
            VStack(alignment: .leading, spacing: 10) {
                Text("비교 근거")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                PersonalizationMetricView(
                    title: "몰입 시간",
                    focusedValue: Self.focusDurationText(ratio: focusedRatio),
                    distractedValue: Self.focusDurationText(ratio: distractedRatio),
                    focusedProgress: focusedRatio,
                    distractedProgress: distractedRatio,
                    thresholdProgress: rule?.minimumFocusRatio,
                    thresholdLabel: rule.map {
                        "기준 \(Self.focusDurationText(ratio: $0.minimumFocusRatio))"
                    }
                )

                let switchScale = Double(
                    max(
                        10,
                        max(
                            evidence.maximumObservedAppSwitches,
                            (rule?.maximumAppSwitches ?? 0) + 2
                        )
                    )
                )
                PersonalizationMetricView(
                    title: "앱 전환",
                    focusedValue: Self.decimal(focusedSwitches, suffix: "회"),
                    distractedValue: Self.decimal(distractedSwitches, suffix: "회"),
                    focusedProgress: focusedSwitches / switchScale,
                    distractedProgress: distractedSwitches / switchScale,
                    thresholdProgress: rule.map { Double($0.maximumAppSwitches) / switchScale },
                    thresholdLabel: rule.map { "기준 \($0.maximumAppSwitches)회" }
                )
            }
            .padding(.top, 2)
        }
    }

    private func learningStatus(_ analysis: FocusPersonalizationAnalysis) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "hourglass")
                .foregroundStyle(.secondary)
            Text(personalizationStatusText(analysis))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
    }

    private func personalizationStateLabel(_ analysis: FocusPersonalizationAnalysis) -> String {
        if analysis.isReady { return "기준 준비됨" }
        if !analysis.hasEnoughFeedback { return "회고 모으는 중" }
        return "비교 중"
    }

    private func personalizationStatusText(_ analysis: FocusPersonalizationAnalysis) -> String {
        if !analysis.hasEnoughFeedback {
            let focusedRemaining = max(
                0,
                analysis.requiredFeedbackCount - analysis.focusedFeedbackCount
            )
            let distractedRemaining = max(
                0,
                analysis.requiredFeedbackCount - analysis.distractedFeedbackCount
            )
            var missing: [String] = []
            if focusedRemaining > 0 { missing.append("집중 잘함 \(focusedRemaining)개") }
            if distractedRemaining > 0 { missing.append("흐트러짐 \(distractedRemaining)개") }
            return missing.joined(separator: " · ") + "가 더 필요해요."
        }
        return "두 결과가 겹쳐 현재는 규칙 기반을 사용하고 있어요."
    }

    // MARK: - 규칙 기반

    private func ruleCard(title: String) -> some View {
        SettingsGroupCard(title) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    tenMinuteWindowBadge
                    Spacer()
                }

                ruleSlider(
                    title: "몰입 시간",
                    systemImage: "timer",
                    valueText: "\(Self.focusDurationText(percent: manualFocusPercent)) / 10분",
                    detailText: "\(manualFocusPercent)%",
                    value: manualFocusPercentBinding,
                    range: 5...95,
                    step: 5,
                    accessibilityLabel: "최근 10분 최소 몰입 시간"
                )

                orDivider

                ruleSlider(
                    title: "앱 전환",
                    systemImage: "arrow.left.arrow.right",
                    valueText: "최대 \(manualMaximumAppSwitches)회",
                    detailText: "\(manualMaximumAppSwitches + 1)회째 감지",
                    value: manualAppSwitchesBinding,
                    range: 0...100,
                    step: 1,
                    accessibilityLabel: "최근 10분 최대 앱 전환"
                )

                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.accentColor)
                    Text("\(Self.focusDurationText(percent: manualFocusPercent)) 미만 또는 앱 전환 \(manualMaximumAppSwitches + 1)회째")
                        .font(.caption.bold())
                    Spacer(minLength: 0)
                    Text("잔소리")
                        .font(.caption2.bold())
                        .foregroundStyle(Color.accentColor)
                }
                .padding(9)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }

    private func ruleSlider(
        title: String,
        systemImage: String,
        valueText: String,
        detailText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        accessibilityLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.callout)
                Spacer()
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(valueText)
                    .font(.callout.bold().monospacedDigit())
            }
            Slider(value: value, in: range, step: step)
                .disabled(!isEnabled)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(valueText)
        }
    }

    private var orDivider: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
            Text("또는")
                .font(.caption2.bold())
                .foregroundStyle(.tertiary)
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
        }
    }

    private var tenMinuteWindowBadge: some View {
        Label("최근 10분", systemImage: "clock.arrow.circlepath")
            .font(.caption2.bold())
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.09), in: Capsule())
    }

    // MARK: - 반복 방식

    private var frequencyCard: some View {
        SettingsGroupCard("반복 방식") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    frequencyOption(
                        .unlimited,
                        title: "제한 없음",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    frequencyOption(
                        .limited,
                        title: "최대 횟수",
                        systemImage: "number.square"
                    )
                }

                if frequencyMode == .limited {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("세션당 최대")
                                .font(.callout)
                            Spacer()
                            Text("\(maximumNudgesPerSession)회")
                                .font(.callout.bold().monospacedDigit())
                        }
                        Slider(value: maximumNudgesBinding, in: 1...10, step: 1)
                            .disabled(!isEnabled)
                            .accessibilityLabel("세션당 최대 잔소리 횟수")
                            .accessibilityValue("\(maximumNudgesPerSession)회")
                    }
                }
            }
            .padding(14)
        }
    }

    private func frequencyOption(
        _ mode: FocusNudgeFrequencyMode,
        title: String,
        systemImage: String
    ) -> some View {
        let isSelected = frequencyMode == mode
        return Button {
            frequencyModeRawValue = mode.rawValue
        } label: {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                Text(title)
                    .fontWeight(.semibold)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                }
            }
            .font(.callout)
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.07),
                        lineWidth: 0.7
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    // MARK: - 문구

    private var messageCard: some View {
        SettingsGroupCard("해줄 말") {
            VStack(alignment: .leading, spacing: 6) {
                Text("한 줄에 하나씩 적어주세요. 위반 이유 뒤에 이어서 말합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $messages)
                    .font(.system(size: 12))
                    .frame(height: 72)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .disabled(!isEnabled)

                HStack {
                    Text(messagePreview)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 8)
                    Text("\(messages.count)/\(Constants.companionFocusNudgeMessagesMaxLength)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(
                            messages.count > Constants.companionFocusNudgeMessagesMaxLength
                                ? AnyShapeStyle(Color.red)
                                : AnyShapeStyle(.tertiary)
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Bindings / Formatting

    private var feedbackCountBinding: Binding<Double> {
        Binding(
            get: { Double(requiredFeedbackCount) },
            set: { requiredFeedbackCount = Int($0.rounded()) }
        )
    }

    private var manualFocusPercentBinding: Binding<Double> {
        Binding(
            get: { Double(manualFocusPercent) },
            set: { manualFocusPercent = Int($0.rounded()) }
        )
    }

    private var manualAppSwitchesBinding: Binding<Double> {
        Binding(
            get: { Double(manualMaximumAppSwitches) },
            set: { manualMaximumAppSwitches = Int($0.rounded()) }
        )
    }

    private var maximumNudgesBinding: Binding<Double> {
        Binding(
            get: { Double(maximumNudgesPerSession) },
            set: { maximumNudgesPerSession = Int($0.rounded()) }
        )
    }

    private var messagePreview: String {
        let parsed = FocusScoreMessages.parse(messages)
        guard parsed.isEmpty else { return "등록한 말 \(parsed.count)개를 돌아가며 씁니다." }
        return "기본 문구 예: \(FocusScoreMessages.fallback[0])"
    }

    private func loadPersonalization() {
        guard detectionMode == .personalized else {
            personalization = nil
            return
        }
        personalization = repository.focusPersonalization(
            requiredFeedbackCount: requiredFeedbackCount
        )
    }

    private static func percent(_ ratio: Double) -> Int {
        Int((ratio * 100).rounded())
    }

    private static func focusDurationText(percent: Int) -> String {
        focusDurationText(ratio: Double(percent) / 100)
    }

    private static func focusDurationText(ratio: Double) -> String {
        let seconds = Int((ratio * 10 * 60).rounded())
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if minutes == 0 { return "\(remainingSeconds)초" }
        if remainingSeconds == 0 { return "\(minutes)분" }
        return "\(minutes)분 \(remainingSeconds)초"
    }

    private static func decimal(_ value: Double, suffix: String) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.05 {
            return "\(Int(rounded))\(suffix)"
        }
        return String(format: "%.1f%@", value, suffix)
    }
}

private struct PersonalizationMetricView: View {
    let title: String
    let focusedValue: String
    let distractedValue: String
    let focusedProgress: Double
    let distractedProgress: Double
    let thresholdProgress: Double?
    let thresholdLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let thresholdLabel {
                    Text(thresholdLabel)
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                }
            }
            metricRow("집중", value: focusedValue, progress: focusedProgress, color: .green)
            metricRow("흐트러짐", value: distractedValue, progress: distractedProgress, color: .orange)
        }
    }

    private func metricRow(
        _ label: String,
        value: String,
        progress: Double,
        color: Color
    ) -> some View {
        HStack(spacing: 7) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06))
                    Capsule()
                        .fill(color.opacity(0.72))
                        .frame(width: proxy.size.width * min(max(progress, 0), 1))
                    if let thresholdProgress {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 2, height: 10)
                            .offset(
                                x: max(
                                    0,
                                    min(proxy.size.width - 2, proxy.size.width * thresholdProgress - 1)
                                )
                            )
                    }
                }
            }
            .frame(height: 7)
            Text(value)
                .font(.caption2.monospacedDigit())
                .frame(width: 54, alignment: .trailing)
        }
    }
}
