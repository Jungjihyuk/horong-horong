import AppKit
import SwiftData
import SwiftUI

@MainActor
final class PomodoroReflectionPanel {
    static let shared = PomodoroReflectionPanel()

    private var panel: NSPanel?

    private init() {}

    func show(focusSessionID: UUID, modelContext: ModelContext) {
        let sessionID = focusSessionID
        let descriptor = FetchDescriptor<PomodoroReflection>(
            predicate: #Predicate { reflection in
                reflection.focusSessionID == sessionID
            }
        )
        guard ((try? modelContext.fetchCount(descriptor)) ?? 0) == 0 else { return }

        let sessionDescriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        let session = try? modelContext.fetch(sessionDescriptor).first
        let canRecordLinkedTaskCompletion = session?.linkedMemoID.map {
            PomodoroTaskCompletionRecorder.hasLinkedMemo(id: $0, modelContext: modelContext)
        } ?? false
        let suggestedAppCategory = session?.category ?? Constants.defaultFocusCategory
        let focusRange: (start: Date, end: Date)?
        if let session,
           let endedAt = session.endedAt {
            let expectedEnd = session.startedAt.addingTimeInterval(
                TimeInterval(max(0, session.focusMinutes) * 60)
            )
            focusRange = (session.startedAt, min(endedAt, expectedEnd))
        } else {
            focusRange = nil
        }
        let unclassifiedApps: [UnclassifiedAppUsage]
        let productivityManagementAppUsages: [ProductivityManagementAppUsage]
        if let focusRange {
            unclassifiedApps = AppClassificationService.unclassifiedApps(
                from: focusRange.start,
                to: focusRange.end,
                modelContext: modelContext
            )
            productivityManagementAppUsages =
                AppClassificationService.productivityManagementAppUsages(
                    from: focusRange.start,
                    to: focusRange.end,
                    modelContext: modelContext
                )
        } else {
            unclassifiedApps = []
            productivityManagementAppUsages = []
        }

        close(animated: false)

        let panel = PomodoroReflectionWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 580),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelFrame = panel.frame
            panel.setFrameOrigin(
                NSPoint(
                    x: screenFrame.midX - panelFrame.width / 2,
                    y: screenFrame.midY - panelFrame.height / 2 + 40
                )
            )
        }

        let contentView = PomodoroReflectionView(
            taskTitle: session?.taskTitleSnapshot,
            isLinkedTask: session?.linkedMemoID != nil,
            canRecordLinkedTaskCompletion: canRecordLinkedTaskCompletion,
            suggestedAppCategory: suggestedAppCategory,
            unclassifiedApps: unclassifiedApps,
            productivityManagementAppUsages: productivityManagementAppUsages,
            onSave: {
                [weak self] focusExperience,
                progressResult,
                incompleteReason,
                appChoices,
                productivityManagementAppCategories in
                guard !progressResult.requiresReason || incompleteReason != nil else {
                    throw PomodoroReflectionSaveError.missingIncompleteReason
                }

                let answeredAt = Date()
                let reflection = PomodoroReflection(
                    focusSessionID: sessionID,
                    focusExperience: focusExperience,
                    progressResult: progressResult,
                    incompleteReason: incompleteReason,
                    answeredAt: answeredAt
                )
                modelContext.insert(reflection)
                session?.reflectionDeferredAt = nil
                do {
                    try AppClassificationService.apply(
                        choices: appChoices,
                        apps: unclassifiedApps,
                        modelContext: modelContext
                    )
                    if let focusRange {
                        for (bundleIdentifier, category) in productivityManagementAppCategories {
                            try AppClassificationService
                                .prepareProductivityManagementAppSessionClassification(
                                    bundleIdentifier: bundleIdentifier,
                                    from: focusRange.start,
                                    to: focusRange.end,
                                    category: category,
                                    modelContext: modelContext
                                )
                        }
                    }
                    let recordsLinkedTaskCompletion = progressResult == .completedAsPlanned
                        && session?.linkedMemoID.map {
                            PomodoroTaskCompletionRecorder.hasLinkedMemo(
                                id: $0,
                                modelContext: modelContext
                            )
                        } == true
                    let affectedMemo: Memo?
                    if recordsLinkedTaskCompletion, let session {
                        affectedMemo = try PomodoroTaskCompletionRecorder.recordCompletion(
                            for: session,
                            completedAt: answeredAt,
                            modelContext: modelContext
                        )
                    } else {
                        affectedMemo = nil
                    }
                    try modelContext.save()
                    CategoryManager.shared.loadUserRules(from: modelContext)
                    NotificationCenter.default.post(name: .pomodoroReflectionDidChange, object: nil)
                    NotificationCenter.default.post(name: .pomodoroSessionDidChange, object: nil)
                    if recordsLinkedTaskCompletion,
                       let linkedMemoID = session?.linkedMemoID {
                        NotificationCenter.default.post(
                            name: .pomodoroLinkedTaskDidComplete,
                            object: linkedMemoID
                        )
                    }
                    if let affectedMemo {
                        PomodoroTaskCompletionRecorder.applyPostSaveEffects(
                            to: affectedMemo,
                            modelContext: modelContext
                        )
                    }
                    self?.close()
                } catch {
                    modelContext.rollback()
                    throw error
                }
            },
            onCancel: { [weak self] in
                session?.reflectionDeferredAt = Date()
                do {
                    try modelContext.save()
                    NotificationCenter.default.post(
                        name: .pomodoroSessionDidChange,
                        object: sessionID
                    )
                } catch {
                    modelContext.rollback()
                }
                self?.close()
            }
        )

        panel.contentView = NSHostingView(rootView: contentView)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        panel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }

        self.panel = panel
    }

    func close(animated: Bool = true) {
        guard let panel else { return }
        if !animated {
            panel.orderOut(nil)
            self.panel = nil
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self, weak panel] in
            MainActor.assumeIsolated {
                panel?.orderOut(nil)
                if self?.panel === panel {
                    self?.panel = nil
                }
            }
        })
    }
}

private enum PomodoroReflectionSaveError: Error {
    case missingIncompleteReason
}

private final class PomodoroReflectionWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct PomodoroReflectionView: View {
    private enum Step {
        case focusExperience
        case progressResult
        case incompleteReason
        case appClassification
    }

    private enum AppSelection: Hashable {
        case later
        case category(String)
        case excluded
    }

    private enum ProductivityManagementAppSelection: Hashable {
        case management
        case category(String)
    }

    let taskTitle: String?
    let isLinkedTask: Bool
    let canRecordLinkedTaskCompletion: Bool
    let suggestedAppCategory: String
    let unclassifiedApps: [UnclassifiedAppUsage]
    let productivityManagementAppUsages: [ProductivityManagementAppUsage]
    let onSave: (
        PomodoroFocusExperience,
        PomodoroProgressResult,
        PomodoroIncompleteReason?,
        [String: UnclassifiedAppChoice],
        [String: String]
    ) throws -> Void
    let onCancel: () -> Void

    @State private var step: Step = .focusExperience
    @State private var focusExperience: PomodoroFocusExperience?
    @State private var progressResult: PomodoroProgressResult?
    @State private var incompleteReason: PomodoroIncompleteReason?
    @State private var appSelections: [String: AppSelection] = [:]
    @State private var productivityManagementAppSelections:
        [String: ProductivityManagementAppSelection] = [:]
    @State private var saveErrorMessage: String?
    @State private var isSaving = false

    private var needsAppClassification: Bool {
        !unclassifiedApps.isEmpty || !productivityManagementAppUsages.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            Divider()
                .overlay(PopoverChrome.divider)

            if isLinkedTask {
                sessionContextCard
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(stepLabel)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.accent)
                Text(question)
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                if step == .incompleteReason {
                    Text("가장 큰 이유 하나를 골라주세요.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                } else if step == .appClassification,
                          !productivityManagementAppUsages.isEmpty {
                    Text("생산성 관리로 분류된 앱 사용이 작업의 일부였다면 이 세션에만 반영해요.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                }
            }

            ScrollView {
                LazyVStack(spacing: 7) {
                    options
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)

            if let saveErrorMessage {
                Text(saveErrorMessage)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.red)
            }

            footer
        }
        .padding(26)
        .frame(width: 560, height: 580)
        .background(
            PopoverChrome.surface,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(PopoverChrome.border, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(PopoverChrome.accent)

            VStack(alignment: .leading, spacing: 3) {
                Text("포모도로 돌아보기")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                Text("방금 느낀 상태를 기록해 나만의 몰입 패턴을 찾아요.")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
            }

            Spacer(minLength: 0)

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .frame(width: 28, height: 28)
                    .background(PopoverChrome.surfaceAlt, in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("나중에 회고하기")
        }
    }

    private var sessionContextCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(taskTitle ?? "이름을 확인할 수 없는 할 일")
                    .lineLimit(2)
            } icon: {
                Image(systemName: "checklist")
            }
        }
        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
        .foregroundStyle(PopoverChrome.inkSecondary)
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            PopoverChrome.accentSoft.opacity(0.3),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PopoverChrome.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var options: some View {
        switch step {
        case .focusExperience:
            ForEach(PomodoroFocusExperience.allCases) { option in
                optionButton(
                    label: option.label,
                    isSelected: focusExperience == option
                ) {
                    focusExperience = option
                    saveErrorMessage = nil
                }
            }
        case .progressResult:
            ForEach(PomodoroProgressResult.allCases) { option in
                optionButton(
                    label: option.label(
                        recordsLinkedTaskCompletion: canRecordLinkedTaskCompletion
                    ),
                    subtitle: canRecordLinkedTaskCompletion && option == .completedAsPlanned
                        ? "선택하면 성취 탭에서도 완료로 표시돼요."
                        : nil,
                    isSelected: progressResult == option
                ) {
                    progressResult = option
                    if !option.requiresReason {
                        incompleteReason = nil
                    }
                    saveErrorMessage = nil
                }
            }
        case .incompleteReason:
            ForEach(PomodoroIncompleteReason.allCases) { option in
                optionButton(
                    label: option.label,
                    isSelected: incompleteReason == option
                ) {
                    incompleteReason = option
                    saveErrorMessage = nil
                }
            }
        case .appClassification:
            ForEach(productivityManagementAppUsages) { usage in
                productivityManagementAppClassificationRow(usage)
            }
            ForEach(unclassifiedApps) { app in
                appClassificationRow(app)
            }
        }
    }

    private func productivityManagementAppClassificationRow(
        _ usage: ProductivityManagementAppUsage
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "timer")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(PopoverChrome.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(usage.appName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                Text("\(formattedDuration(usage.durationSeconds)) 사용")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }

            Spacer(minLength: 8)

            Picker(
                "",
                selection: Binding(
                    get: {
                        productivityManagementAppSelections[usage.bundleIdentifier]
                            ?? .management
                    },
                    set: {
                        productivityManagementAppSelections[usage.bundleIdentifier] = $0
                        saveErrorMessage = nil
                    }
                )
            ) {
                Text("생산성 관리")
                    .tag(ProductivityManagementAppSelection.management)
                Text("작업의 일부 · \(suggestedAppCategory)")
                    .tag(ProductivityManagementAppSelection.category(suggestedAppCategory))
                ForEach(
                    Constants.allCategories.filter { $0 != suggestedAppCategory },
                    id: \.self
                ) { category in
                    Text("\(Constants.categoryEmoji(for: category)) \(category)")
                        .tag(ProductivityManagementAppSelection.category(category))
                }
            }
            .labelsHidden()
            .frame(width: 190)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .background(
            PopoverChrome.surfaceAlt,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PopoverChrome.border, lineWidth: 1)
        )
    }

    private func appClassificationRow(_ app: UnclassifiedAppUsage) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "app.dashed")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(PopoverChrome.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(app.appName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                Text("\(formattedDuration(app.durationSeconds)) · \(app.bundleIdentifier)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Picker(
                "",
                selection: Binding(
                    get: { appSelections[app.bundleIdentifier] ?? .later },
                    set: {
                        appSelections[app.bundleIdentifier] = $0
                        saveErrorMessage = nil
                    }
                )
            ) {
                Text("나중에 분류").tag(AppSelection.later)
                Text("추천 · \(suggestedAppCategory)")
                    .tag(AppSelection.category(suggestedAppCategory))
                ForEach(
                    Constants.allCategories.filter { $0 != suggestedAppCategory },
                    id: \.self
                ) { category in
                    Text("\(Constants.categoryEmoji(for: category)) \(category)")
                        .tag(AppSelection.category(category))
                }
                Divider()
                Text("앞으로 기록 안 함").tag(AppSelection.excluded)
            }
            .labelsHidden()
            .frame(width: 170)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .background(
            PopoverChrome.surfaceAlt,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PopoverChrome.border, lineWidth: 1)
        )
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        if minutes > 0 { return "\(minutes)분" }
        return "\(max(0, seconds))초"
    }

    private func optionButton(
        label: String,
        subtitle: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isSelected ? PopoverChrome.accent : PopoverChrome.inkTertiary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(PopoverChrome.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .foregroundStyle(PopoverChrome.inkTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? PopoverChrome.accentSoft.opacity(0.5) : PopoverChrome.surfaceAlt,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? PopoverChrome.accent : PopoverChrome.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if step != .focusExperience {
                Button("이전", action: moveBack)
                    .buttonStyle(.bordered)
            }

            Spacer(minLength: 0)

            Button("나중에 하기", action: onCancel)
                .buttonStyle(.bordered)
                .disabled(isSaving)

            Button(primaryButtonTitle, action: moveForward)
                .buttonStyle(.borderedProminent)
                .tint(PopoverChrome.accent)
                .disabled(primaryButtonDisabled || isSaving)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var stepLabel: String {
        switch step {
        case .focusExperience: return "질문 1 · 몰입 경험"
        case .progressResult: return "질문 2 · 작업 진행 결과"
        case .incompleteReason: return "추가 질문 · 가장 큰 이유"
        case .appClassification: return "마지막 · 앱 사용 분류"
        }
    }

    private var question: String {
        switch step {
        case .focusExperience: return "이번 세션에서는 어떠셨나요?"
        case .progressResult:
            return canRecordLinkedTaskCompletion
                ? "이 할 일을 얼마나 진행했나요?"
                : "계획한 만큼 진행했나요?"
        case .incompleteReason: return "작업이 남은 가장 큰 이유는 무엇인가요?"
        case .appClassification: return "이번 세션의 앱 사용을 어떻게 분류할까요?"
        }
    }

    private var primaryButtonTitle: String {
        switch step {
        case .focusExperience:
            return "다음"
        case .progressResult:
            return progressResult?.requiresReason == true || needsAppClassification
                ? "다음"
                : "저장"
        case .incompleteReason:
            return needsAppClassification ? "다음" : "저장"
        case .appClassification:
            return "저장"
        }
    }

    private var primaryButtonDisabled: Bool {
        switch step {
        case .focusExperience: return focusExperience == nil
        case .progressResult: return progressResult == nil
        case .incompleteReason: return incompleteReason == nil
        case .appClassification: return false
        }
    }

    private func moveBack() {
        saveErrorMessage = nil
        switch step {
        case .focusExperience:
            break
        case .progressResult:
            step = .focusExperience
        case .incompleteReason:
            step = .progressResult
        case .appClassification:
            step = progressResult?.requiresReason == true ? .incompleteReason : .progressResult
        }
    }

    private func moveForward() {
        saveErrorMessage = nil
        switch step {
        case .focusExperience:
            guard focusExperience != nil else { return }
            step = .progressResult
        case .progressResult:
            guard let progressResult else { return }
            if progressResult.requiresReason {
                step = .incompleteReason
            } else if needsAppClassification {
                step = .appClassification
            } else {
                save()
            }
        case .incompleteReason:
            guard incompleteReason != nil else { return }
            if needsAppClassification {
                step = .appClassification
            } else {
                save()
            }
        case .appClassification:
            save()
        }
    }

    private func save() {
        guard !isSaving, let focusExperience, let progressResult else { return }
        isSaving = true
        let appChoices = appSelections.reduce(into: [String: UnclassifiedAppChoice]()) {
            result, entry in
            switch entry.value {
            case .later:
                break
            case let .category(category):
                result[entry.key] = .category(category)
            case .excluded:
                result[entry.key] = .excluded
            }
        }
        let productivityManagementAppCategories =
            productivityManagementAppSelections.reduce(into: [String: String]()) {
                result, entry in
                if case let .category(category) = entry.value {
                    result[entry.key] = category
                }
            }
        do {
            try onSave(
                focusExperience,
                progressResult,
                incompleteReason,
                appChoices,
                productivityManagementAppCategories
            )
        } catch {
            isSaving = false
            saveErrorMessage = "저장하지 못했어요. 잠시 후 다시 시도해 주세요."
        }
    }
}

#Preview {
    PomodoroReflectionView(
        taskTitle: "통계 회고 결과 화면 구현",
        isLinkedTask: true,
        canRecordLinkedTaskCompletion: true,
        suggestedAppCategory: "개발",
        unclassifiedApps: [
            UnclassifiedAppUsage(
                bundleIdentifier: "com.example.orca",
                appName: "Orca",
                durationSeconds: 18 * 60
            )
        ],
        productivityManagementAppUsages: [
            ProductivityManagementAppUsage(
                bundleIdentifier: Constants.horongHorongBundleIdentifier,
                appName: "호롱호롱",
                durationSeconds: 3 * 60
            ),
            ProductivityManagementAppUsage(
                bundleIdentifier: "com.apple.reminders",
                appName: "미리알림",
                durationSeconds: 2 * 60
            ),
        ],
        onSave: { _, _, _, _, _ in },
        onCancel: {}
    )
}
