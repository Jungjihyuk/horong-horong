import SwiftUI

struct PomodoroReflectionEditSheet: View {
    let reflection: StatsPomodoroReflection
    let linkedTaskTitle: String?
    let usesLinkedTaskCompletionOption: Bool
    let recordsLinkedTaskCompletion: Bool
    let onSave: (
        PomodoroFocusExperience,
        PomodoroProgressResult,
        PomodoroIncompleteReason?
    ) throws -> Void
    let onCancel: () -> Void

    @State private var focusExperience: PomodoroFocusExperience
    @State private var progressResult: PomodoroProgressResult?
    @State private var incompleteReason: PomodoroIncompleteReason?
    @State private var saveErrorMessage: String?
    @State private var isSaving = false

    init(
        reflection: StatsPomodoroReflection,
        linkedTaskTitle: String?,
        usesLinkedTaskCompletionOption: Bool,
        recordsLinkedTaskCompletion: Bool,
        onSave: @escaping (
            PomodoroFocusExperience,
            PomodoroProgressResult,
            PomodoroIncompleteReason?
        ) throws -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.reflection = reflection
        self.linkedTaskTitle = linkedTaskTitle
        self.usesLinkedTaskCompletionOption = usesLinkedTaskCompletionOption
        self.recordsLinkedTaskCompletion = recordsLinkedTaskCompletion
        self.onSave = onSave
        self.onCancel = onCancel
        _focusExperience = State(initialValue: reflection.focusExperience ?? .unsure)
        _progressResult = State(
            initialValue: Self.initialProgressResult(rawValue: reflection.progressResultRawValue)
        )
        _incompleteReason = State(initialValue: reflection.incompleteReason)
    }

    static func initialProgressResult(rawValue: String) -> PomodoroProgressResult? {
        PomodoroProgressResult(rawValue: rawValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.vertical, 20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    focusExperienceSection
                    progressResultSection

                    if progressResult?.requiresReason == true {
                        incompleteReasonSection
                    }

                    if let saveErrorMessage {
                        Text(saveErrorMessage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                }
                .padding(24)
            }

            Divider()

            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .frame(width: 520, height: 480)
        .background(PopoverChrome.surface)
        .onChange(of: progressResult) { _, newValue in
            if newValue?.requiresReason != true {
                incompleteReason = nil
            }
            saveErrorMessage = nil
        }
        .interactiveDismissDisabled(isSaving)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "quote.bubble.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(PopoverChrome.accent)

            VStack(alignment: .leading, spacing: 4) {
                Text("포모도로 회고 수정")
                    .font(.title3.bold())
                    .foregroundStyle(PopoverChrome.ink)
                Text("선택을 바꾸면 이후 개인화 데이터에도 수정된 값이 사용됩니다.")
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
            }

            Spacer()

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(PopoverChrome.inkTertiary)
            .keyboardShortcut(.cancelAction)
            .disabled(isSaving)
        }
    }

    private var focusExperienceSection: some View {
        questionSection(
            title: "몰입 경험",
            question: "이번 세션에서는 어떠셨나요?"
        ) {
            Picker("몰입 경험", selection: $focusExperience) {
                ForEach(PomodoroFocusExperience.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var progressResultSection: some View {
        questionSection(
            title: "작업 진행 결과",
            question: usesLinkedTaskCompletionOption
                ? "이 할 일을 얼마나 진행했나요?"
                : "계획한 만큼 진행했나요?"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if let linkedTaskTitle {
                    Label(linkedTaskTitle, systemImage: "checklist")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .lineLimit(2)
                }

                Picker("작업 진행 결과", selection: $progressResult) {
                    Text("결과를 선택해 주세요").tag(PomodoroProgressResult?.none)
                    ForEach(PomodoroProgressResult.allCases) { option in
                        Text(
                            option.label(
                                recordsLinkedTaskCompletion: usesLinkedTaskCompletionOption
                            )
                        )
                        .tag(PomodoroProgressResult?.some(option))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)

                if usesLinkedTaskCompletionOption,
                   progressResult == .completedAsPlanned {
                    Text("저장하면 성취 탭에서도 완료 상태가 함께 반영됩니다.")
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.inkTertiary)
                } else if recordsLinkedTaskCompletion {
                    Text("저장하면 이 세션의 완료 근거가 삭제되고, 이후 다른 변경이 없었다면 할 일이 진행 중으로 돌아갑니다.")
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.inkTertiary)
                }
            }
        }
    }

    private var incompleteReasonSection: some View {
        questionSection(
            title: "가장 큰 이유",
            question: "작업이 남은 가장 큰 이유는 무엇인가요?"
        ) {
            Picker("가장 큰 이유", selection: $incompleteReason) {
                Text("이유를 선택해 주세요").tag(PomodoroIncompleteReason?.none)
                ForEach(PomodoroIncompleteReason.allCases) { option in
                    Text(option.label).tag(PomodoroIncompleteReason?.some(option))
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func questionSection<Content: View>(
        title: String,
        question: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(PopoverChrome.accent)
            Text(question)
                .font(.callout.weight(.semibold))
                .foregroundStyle(PopoverChrome.ink)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            PopoverChrome.surfaceAlt,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PopoverChrome.border, lineWidth: 1)
        )
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            Button("취소", action: onCancel)
                .buttonStyle(.bordered)
                .disabled(isSaving)

            Button("저장", action: save)
                .buttonStyle(.borderedProminent)
                .tint(PopoverChrome.accent)
                .disabled(saveDisabled)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var saveDisabled: Bool {
        isSaving
            || progressResult == nil
            || (progressResult?.requiresReason == true && incompleteReason == nil)
    }

    private func save() {
        guard !saveDisabled, let progressResult else { return }
        isSaving = true
        saveErrorMessage = nil
        do {
            try onSave(focusExperience, progressResult, incompleteReason)
        } catch {
            isSaving = false
            saveErrorMessage = "저장하지 못했어요. 잠시 후 다시 시도해 주세요."
        }
    }
}
