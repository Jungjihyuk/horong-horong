import SwiftData
import SwiftUI

struct PomodoroTaskCandidate: Identifiable, Equatable {
    let id: UUID
    let title: String
    let isToday: Bool
    let isGoalLinked: Bool
}

enum PomodoroTaskCandidateBuilder {
    static func candidates(
        memos: [Memo],
        goalRecords: [AchievementGoalRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [PomodoroTaskCandidate] {
        let linkedMemoIDs = Set(goalRecords.flatMap(\.linkedMemoIDs))

        return memos.compactMap { memo in
            guard !memo.isCompletedValue,
                  !memo.isArchivedValue else {
                return nil
            }
            let isToday = TodayPlanningReminderPolicy.isTodayTask(
                memo,
                now: now,
                calendar: calendar
            )
            let isGoalLinked = linkedMemoIDs.contains(memo.id)
            guard isToday || isGoalLinked else { return nil }

            let title = taskTitle(memo.content)
            return PomodoroTaskCandidate(
                id: memo.id,
                title: title.isEmpty ? "제목 없는 할 일" : title,
                isToday: isToday,
                isGoalLinked: isGoalLinked
            )
        }
    }

    static func taskTitle(_ value: String) -> String {
        value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct TimerGradientButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.vertical, 12)
            .padding(.horizontal, 22)
            .background {
                ZStack {
                    if PopoverChrome.isGamePixel && !configuration.isPressed {
                        RoundedRectangle(cornerRadius: PopoverChrome.controlRadius, style: .continuous)
                            .fill(PopoverChrome.pixelShadow)
                            .offset(x: 3, y: 3)
                    }

                    RoundedRectangle(cornerRadius: PopoverChrome.controlRadius, style: .continuous)
                        .fill(timerButtonFill)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: PopoverChrome.controlRadius, style: .continuous)
                    .stroke(PopoverChrome.isGamePixel ? PopoverChrome.border : Color.clear, lineWidth: PopoverChrome.borderWidth)
            )
            .shadow(
                color: PopoverChrome.isGamePixel
                    ? .clear
                    : Color(red: 0.92, green: 0.40, blue: 0.08).opacity(configuration.isPressed ? 0.22 : 0.32),
                radius: PopoverChrome.isGamePixel ? 0 : 13,
                x: 0,
                y: PopoverChrome.isGamePixel ? 0 : 8
            )
            .offset(x: PopoverChrome.isGamePixel && configuration.isPressed ? 2 : 0, y: PopoverChrome.isGamePixel && configuration.isPressed ? 2 : 0)
            .scaleEffect(!PopoverChrome.isGamePixel && configuration.isPressed ? 0.98 : 1)
    }

    private var timerButtonFill: some ShapeStyle {
        PopoverChrome.primaryButtonFill
    }
}

private struct PixelTimerColon: View {
    let opacity: Double

    var body: some View {
        VStack(spacing: 12) {
            Rectangle()
                .frame(width: 8, height: 8)
            Rectangle()
                .frame(width: 8, height: 8)
        }
        .foregroundStyle(PopoverChrome.accentSoft)
        .opacity(opacity)
        .frame(width: 26, height: 56, alignment: .center)
    }
}

private struct HybridPixelTimerNumber: View {
    let value: String

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(Array(value.enumerated()), id: \.offset) { _, character in
                HybridPixelDigit(character: character)
            }
        }
        .frame(height: 56, alignment: .center)
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct HybridPixelDigit: View {
    let character: Character

    private let width: CGFloat = 34
    private let height: CGFloat = 56

    private enum Segment {
        case top
        case upperLeft
        case upperRight
        case middle
        case lowerLeft
        case lowerRight
        case bottom
    }

    private var segments: [Segment] {
        switch character {
        case "1": return [.upperRight, .lowerRight]
        case "2": return [.top, .upperRight, .middle, .lowerLeft, .bottom]
        case "3": return [.top, .upperRight, .middle, .lowerRight, .bottom]
        case "4": return [.upperLeft, .upperRight, .middle, .lowerRight]
        case "5": return [.top, .upperLeft, .middle, .lowerRight, .bottom]
        case "7": return [.top, .upperRight, .lowerRight]
        case "8": return [.top, .upperLeft, .upperRight, .middle, .lowerLeft, .lowerRight, .bottom]
        case "9": return [.top, .upperLeft, .upperRight, .middle, .lowerRight, .bottom]
        default: return []
        }
    }

    private var blocks: [CGRect] {
        switch character {
        case "0":
            return [
                CGRect(x: 8, y: 0, width: 18, height: 4),
                CGRect(x: 4, y: 4, width: 4, height: 4),
                CGRect(x: 26, y: 4, width: 4, height: 4),
                CGRect(x: 0, y: 8, width: 4, height: 40),
                CGRect(x: 30, y: 8, width: 4, height: 40),
                CGRect(x: 4, y: 48, width: 4, height: 4),
                CGRect(x: 26, y: 48, width: 4, height: 4),
                CGRect(x: 8, y: 52, width: 18, height: 4),
            ]
        case "1":
            return [
                CGRect(x: 17, y: 0, width: 4, height: 56),
                CGRect(x: 13, y: 4, width: 4, height: 4),
                CGRect(x: 11, y: 52, width: 16, height: 4),
            ]
        case "2":
            return [
                CGRect(x: 8, y: 0, width: 18, height: 4),
                CGRect(x: 26, y: 4, width: 4, height: 4),
                CGRect(x: 30, y: 8, width: 4, height: 16),
                CGRect(x: 26, y: 24, width: 4, height: 4),
                CGRect(x: 4, y: 28, width: 22, height: 4),
                CGRect(x: 0, y: 32, width: 4, height: 16),
                CGRect(x: 4, y: 48, width: 4, height: 4),
                CGRect(x: 8, y: 52, width: 26, height: 4),
            ]
        case "5":
            return [
                CGRect(x: 4, y: 0, width: 26, height: 4),
                CGRect(x: 0, y: 4, width: 4, height: 22),
                CGRect(x: 4, y: 26, width: 22, height: 4),
                CGRect(x: 26, y: 30, width: 4, height: 4),
                CGRect(x: 30, y: 34, width: 4, height: 14),
                CGRect(x: 26, y: 48, width: 4, height: 4),
                CGRect(x: 4, y: 52, width: 22, height: 4),
            ]
        case "6":
            return [
                CGRect(x: 8, y: 0, width: 18, height: 4),
                CGRect(x: 4, y: 4, width: 4, height: 4),
                CGRect(x: 0, y: 8, width: 4, height: 40),
                CGRect(x: 4, y: 26, width: 26, height: 4),
                CGRect(x: 0, y: 26, width: 4, height: 4),
                CGRect(x: 30, y: 30, width: 4, height: 18),
                CGRect(x: 4, y: 48, width: 4, height: 4),
                CGRect(x: 26, y: 48, width: 4, height: 4),
                CGRect(x: 8, y: 52, width: 18, height: 4),
            ]
        case "9":
            return [
                CGRect(x: 8, y: 0, width: 18, height: 4),
                CGRect(x: 4, y: 4, width: 4, height: 4),
                CGRect(x: 26, y: 4, width: 4, height: 4),
                CGRect(x: 0, y: 8, width: 4, height: 18),
                CGRect(x: 30, y: 8, width: 4, height: 40),
                CGRect(x: 4, y: 26, width: 26, height: 4),
                CGRect(x: 26, y: 48, width: 4, height: 4),
                CGRect(x: 8, y: 52, width: 18, height: 4),
            ]
        default:
            return segments.flatMap(blocks(for:))
        }
    }

    private func blocks(for segment: Segment) -> [CGRect] {
        switch segment {
        case .top:
            return [
                CGRect(x: 8, y: 0, width: 18, height: 4),
                CGRect(x: 4, y: 4, width: 4, height: 4),
                CGRect(x: 26, y: 4, width: 4, height: 4),
            ]
        case .upperLeft:
            return [CGRect(x: 0, y: 8, width: 4, height: 18)]
        case .upperRight:
            return [CGRect(x: 30, y: 8, width: 4, height: 18)]
        case .middle:
            return [
                CGRect(x: 4, y: 26, width: 26, height: 4),
                CGRect(x: 0, y: 26, width: 4, height: 4),
                CGRect(x: 30, y: 26, width: 4, height: 4),
            ]
        case .lowerLeft:
            return [CGRect(x: 0, y: 32, width: 4, height: 16)]
        case .lowerRight:
            return [CGRect(x: 30, y: 32, width: 4, height: 16)]
        case .bottom:
            return [
                CGRect(x: 4, y: 48, width: 4, height: 4),
                CGRect(x: 26, y: 48, width: 4, height: 4),
                CGRect(x: 8, y: 52, width: 18, height: 4),
            ]
        }
    }

    var body: some View {
        Canvas { context, _ in
            for block in blocks {
                context.fill(
                    Path(block),
                    with: .color(PopoverChrome.pixelShadow)
                )
            }
        }
        .frame(width: width, height: height)
        .id(character)
    }
}

struct TimerView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \Memo.updatedAt, order: .reverse) private var memos: [Memo]
    @Query(sort: \AchievementGoalRecord.updatedAt, order: .reverse)
    private var goalRecords: [AchievementGoalRecord]
    @State private var hoveredPreset: Constants.PomodoroPreset?
    @State private var selectedTaskID: UUID?
    @State private var showsTaskPicker = false
    @State private var taskSearchText = ""
    @State private var hoveredTaskID: UUID?
    @State private var taskReferenceDate = Date()
    @AppStorage(Constants.AppStorageKey.selectedFocusCategory)
    private var selectedFocusCategory: String = Constants.defaultFocusCategory
    @AppStorage(Constants.AppStorageKey.pomodoroFocusMinutes)
    private var pomodoroFocusMinutes: Int = Constants.defaultPomodoroFocusMinutes
    @AppStorage(Constants.AppStorageKey.pomodoroBreakMinutes)
    private var pomodoroBreakMinutes: Int = Constants.defaultPomodoroBreakMinutes
    @AppStorage(Constants.AppStorageKey.longFocusFocusMinutes)
    private var longFocusFocusMinutes: Int = Constants.defaultLongFocusFocusMinutes
    @AppStorage(Constants.AppStorageKey.longFocusBreakMinutes)
    private var longFocusBreakMinutes: Int = Constants.defaultLongFocusBreakMinutes
    @AppStorage(Constants.AppStorageKey.customFocusMinutes)
    private var customFocusMinutes: Int = Constants.defaultCustomFocusMinutes
    @AppStorage(Constants.AppStorageKey.customBreakMinutes)
    private var customBreakMinutes: Int = Constants.defaultCustomBreakMinutes
    var timerManager: TimerManager
    var requestFocusEnd: () -> Void
    var closePopover: (() -> Void)?

    var body: some View {
        VStack(spacing: 4) {
            timerDisplay
            controlButtons
            postBreakTransitionPrompt
            presetSelector
        }
        .frame(maxWidth: .infinity, minHeight: 410, alignment: .top)
        .onAppear {
            taskReferenceDate = Date()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            taskReferenceDate = Date()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in
            taskReferenceDate = Date()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            taskReferenceDate = Date()
        }
    }

    private var timerDisplay: some View {
        VStack(spacing: 12) {
            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(statusText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                focusStatusIcon
                    .padding(.leading, 2)
            }
            .frame(height: 26)

            timerText

            if showsProgress {
                ProgressView(value: progress)
                    .tint(statusColor)
                    .animation(.linear, value: progress)
                    .padding(.horizontal, 24)
            } else {
                Color.clear
                    .frame(height: 4)
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var timerGlow: some View {
        if !PopoverChrome.isGamePixel {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.00, green: 0.67, blue: 0.31).opacity(isFocusing ? 0.44 : 0.34),
                            Color(red: 1.00, green: 0.75, blue: 0.39).opacity(0.18),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 128
                    )
                )
                .frame(width: 260, height: 90)
                .blur(radius: 8)
                .offset(y: 44)
                .allowsHitTesting(false)
        }
    }

    private var timerText: some View {
        ZStack {
            timerGlow

            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                if PopoverChrome.isGamePixel {
                    HStack(alignment: .center, spacing: 10) {
                        HybridPixelTimerNumber(value: minutesString)
                        PixelTimerColon(opacity: 1)
                        HybridPixelTimerNumber(value: secondsString)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .center)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                } else {
                    HStack(spacing: 0) {
                        Text(minutesString)
                            .foregroundStyle(PopoverChrome.ink)
                            .contentTransition(.numericText())
                        Text(":")
                            .font(.system(size: 46, weight: .semibold, design: .rounded))
                            .foregroundStyle(PopoverChrome.accent)
                            .opacity(colonOpacity(at: context.date))
                        Text(secondsString)
                            .foregroundStyle(PopoverChrome.ink)
                            .contentTransition(.numericText())
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .font(PopoverChrome.displayFont(size: 66, weight: .bold))
            .monospacedDigit()
            .shadow(
                color: PopoverChrome.isGamePixel ? .clear : Color(red: 0.95, green: 0.45, blue: 0.13).opacity(0.15),
                radius: PopoverChrome.isGamePixel ? 0 : 18,
                x: 0,
                y: PopoverChrome.isGamePixel ? 0 : 10
            )
            .animation(PopoverChrome.isGamePixel ? nil : .default, value: appState.remainingSeconds)
        }
        .frame(height: 78)
    }

    private var focusStatusIcon: some View {
        TimelineView(.animation(minimumInterval: 1 / 60)) { context in
            Image(focusIconName)
                .resizable()
                .interpolation(PopoverChrome.isGamePixel ? .none : .high)
                .scaledToFit()
                .frame(width: 35, height: 35)
                .offset(y: focusIconOffset(at: context.date))
                .shadow(
                    color: PopoverChrome.isGamePixel ? .clear : PopoverChrome.accent.opacity(isFocusing ? 0.26 : 0.12),
                    radius: PopoverChrome.isGamePixel ? 0 : 8,
                    x: 0,
                    y: PopoverChrome.isGamePixel ? 0 : 2
                )
        }
        .frame(width: 35, height: 35)
    }

    private var controlButtons: some View {
        HStack(spacing: 10) {
            switch appState.timerState {
            case .idle:
                Button {
                    startFocus()
                } label: {
                    Label("집중 시작", systemImage: "play.fill")
                }
                .buttonStyle(TimerGradientButtonStyle())
                .companionHighlight("timer.startFocus")

            case .focusing:
                Button {
                    timerManager.pause()
                } label: {
                    Label("일시정지", systemImage: "pause.fill")
                }
                .buttonStyle(LanternSecondaryButtonStyle())

                Button {
                    requestFocusEnd()
                } label: {
                    Label("종료", systemImage: "stop.fill")
                }
                .buttonStyle(LanternSecondaryButtonStyle())

            case .paused:
                Button {
                    timerManager.resume()
                } label: {
                    Label("재개", systemImage: "play.fill")
                }
                .buttonStyle(TimerGradientButtonStyle())

                Button {
                    requestFocusEnd()
                } label: {
                    Label("종료", systemImage: "stop.fill")
                }
                .buttonStyle(LanternSecondaryButtonStyle())

            case .breakAlert:
                Button {
                    timerManager.startBreak()
                } label: {
                    Label("휴식 시작", systemImage: "cup.and.saucer.fill")
                }
                .buttonStyle(TimerGradientButtonStyle())

                Button {
                    timerManager.reset()
                } label: {
                    Label("건너뛰기", systemImage: "forward.fill")
                }
                .buttonStyle(LanternSecondaryButtonStyle())

            case .breaking:
                Button {
                    timerManager.reset()
                } label: {
                    Label("휴식 종료", systemImage: "stop.fill")
                }
                .buttonStyle(LanternSecondaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .offset(y: -9)
    }

    @ViewBuilder
    private var postBreakTransitionPrompt: some View {
        if appState.timerState == .idle, let prompt = appState.breakTransitionPrompt {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PopoverChrome.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("휴식 후 다음 흐름")
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .foregroundStyle(PopoverChrome.ink)
                        Text("다음 행동을 알려주면 주의 전환 신호를 더 정확하게 해석할 수 있어요.")
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .foregroundStyle(PopoverChrome.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(spacing: 7) {
                    if timerManager.canContinueLastTask {
                        Button {
                            selectedFocusCategory = prompt.previousCategory
                            timerManager.continueAfterBreak(category: prompt.previousCategory)
                        } label: {
                            Label("같은 작업 계속", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(TimerGradientButtonStyle())
                    }

                    HStack(spacing: 7) {
                        Menu {
                            ForEach(productiveTransitionCategories, id: \.self) { category in
                                Button {
                                    selectedFocusCategory = category
                                    timerManager.resolveBreakTransition(.plannedTaskSwitch, nextCategory: category)
                                } label: {
                                    Text("\(Constants.categoryEmoji(for: category)) \(category)")
                                }
                            }
                        } label: {
                            Label("다른 작업", systemImage: "arrow.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(LanternSecondaryButtonStyle())

                        Button {
                            timerManager.resolveBreakTransition(.externalTransition)
                            closePopover?()
                        } label: {
                            Label("자리 비움", systemImage: "figure.walk")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(LanternSecondaryButtonStyle())
                    }

                }
            }
            .padding(12)
            .background(PopoverChrome.surfaceAlt.opacity(0.9), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(14), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PopoverChrome.radius(14), style: .continuous)
                    .stroke(PopoverChrome.divider, lineWidth: PopoverChrome.borderWidth)
            )
            .padding(.horizontal, 2)
            .padding(.bottom, 8)
            .offset(y: -6)
        }
    }

    private var presetSelector: some View {
        Group {
            if appState.timerState == .idle, appState.breakTransitionPrompt == nil {
                VStack(spacing: 8) {
                    Text("프리셋")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    presetChips
                        .companionHighlight("timer.preset")

                    HStack(spacing: 8) {
                        Text("카테고리")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(PopoverChrome.inkSecondary)
                        Spacer(minLength: 8)
                        Menu {
                            ForEach(Constants.allCategories, id: \.self) { cat in
                                Button {
                                    selectedFocusCategory = cat
                                } label: {
                                    Text("\(Constants.categoryEmoji(for: cat)) \(cat)")
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text("\(Constants.categoryEmoji(for: selectedFocusCategory)) \(selectedFocusCategory)")
                                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(PopoverChrome.ink)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(PopoverChrome.inkSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 10)
                        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous)
                                .stroke(PopoverChrome.divider, lineWidth: PopoverChrome.borderWidth)
                        )
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(PopoverChrome.surfaceAlt.opacity(0.82), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous))

                    pomodoroTaskPlanningCard
                }
            }
        }
    }

    private var pomodoroTaskPlanningCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("이번 포모도로 할 일")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)

                Spacer(minLength: 8)

                Text("선택 사항")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }

            if taskCandidates.isEmpty {
                Text("오늘 시작할 할 일이나 목표에 연결된 미완료 할 일이 없어요.")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Button {
                    taskSearchText = ""
                    hoveredTaskID = nil
                    showsTaskPicker.toggle()
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: selectedTask == nil ? "checklist" : "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(selectedTask == nil ? PopoverChrome.inkSecondary : PopoverChrome.accent)
                            .frame(width: 18)

                        Text(selectedTask?.title ?? "할 일 선택")
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(PopoverChrome.ink)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(PopoverChrome.inkTertiary)
                    }
                    .padding(.vertical, 9)
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
                    .background(
                        PopoverChrome.card,
                        in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous)
                            .stroke(PopoverChrome.divider, lineWidth: PopoverChrome.borderWidth)
                    )
                }
                .buttonStyle(.plain)
                .companionHighlight("timer.selectTask")
                .onReceive(
                    NotificationCenter.default.publisher(for: .companionOnboardingPerform)
                ) { notification in
                    // 온보딩이 "직접 눌러 보여주기" 를 요청하면 목록을 펼친다.
                    guard notification.object as? String == "timer.openTaskPicker" else { return }
                    taskSearchText = ""
                    hoveredTaskID = nil
                    showsTaskPicker = true
                }
                .popover(isPresented: $showsTaskPicker, arrowEdge: .bottom) {
                    pomodoroTaskPicker
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            PopoverChrome.surfaceAlt.opacity(0.82),
            in: RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous)
        )
    }

    private var pomodoroTaskPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text("할 일 선택")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.ink)
                    Spacer()
                    Text("\(taskCandidates.count)개")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                }

                Text("오늘 시작하거나 목표에 연결한 미완료 할 일이에요.")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
            }

            if taskCandidates.count >= 6 {
                TextField("할 일 검색", text: $taskSearchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .rounded))
            }

            Button {
                selectTask(nil)
                showsTaskPicker = false
            } label: {
                taskPickerRowLabel(
                    title: "연결하지 않고 시작",
                    systemImage: "minus.circle",
                    isSelected: selectedTaskID == nil,
                    isHovered: false
                )
            }
            .buttonStyle(.plain)

            Divider()
                .overlay(PopoverChrome.divider)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    taskPickerSection(
                        title: "오늘 시작할 일",
                        systemImage: "calendar",
                        candidates: visibleTodayTaskCandidates
                    )
                    taskPickerSection(
                        title: "목표에 연결된 할 일",
                        systemImage: "target",
                        candidates: visibleGoalTaskCandidates
                    )

                    if visibleTaskCandidates.isEmpty {
                        VStack(spacing: 7) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 18, weight: .medium))
                            Text("검색 결과가 없어요")
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .frame(maxWidth: .infinity, minHeight: 72)
                    }
                }
                .padding(.trailing, 3)
            }
            .frame(height: taskPickerListHeight)
        }
        .padding(16)
        .frame(width: 360)
        .background(PopoverChrome.surface)
    }

    @ViewBuilder
    private func taskPickerSection(
        title: String,
        systemImage: String,
        candidates: [PomodoroTaskCandidate]
    ) -> some View {
        if !candidates.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: systemImage)
                    Text(title)
                    Text("\(candidates.count)")
                        .foregroundStyle(PopoverChrome.inkTertiary)
                }
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)
                .padding(.horizontal, 7)

                ForEach(candidates) { task in
                    Button {
                        selectTask(task.id)
                        showsTaskPicker = false
                    } label: {
                        taskPickerRowLabel(
                            title: task.title,
                            systemImage: "circle",
                            isSelected: selectedTaskID == task.id,
                            isHovered: hoveredTaskID == task.id
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { isHovering in
                        hoveredTaskID = isHovering ? task.id : nil
                    }
                }
            }
        }
    }

    private func taskPickerRowLabel(
        title: String,
        systemImage: String,
        isSelected: Bool,
        isHovered: Bool
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? PopoverChrome.accent : PopoverChrome.inkTertiary)
                .frame(width: 17)

            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 8)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected
                ? PopoverChrome.accentSoft.opacity(0.72)
                : (isHovered ? PopoverChrome.card.opacity(0.78) : .clear),
            in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous)
                .stroke(
                    isSelected
                        ? PopoverChrome.accent.opacity(0.28)
                        : (isHovered ? PopoverChrome.divider : .clear),
                    lineWidth: 1
                )
        )
    }

    private var taskCandidates: [PomodoroTaskCandidate] {
        PomodoroTaskCandidateBuilder.candidates(
            memos: memos,
            goalRecords: goalRecords,
            now: taskReferenceDate
        )
    }

    private var visibleTaskCandidates: [PomodoroTaskCandidate] {
        let query = taskSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return taskCandidates }
        return taskCandidates.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private var visibleTodayTaskCandidates: [PomodoroTaskCandidate] {
        visibleTaskCandidates.filter(\.isToday)
    }

    private var visibleGoalTaskCandidates: [PomodoroTaskCandidate] {
        visibleTaskCandidates.filter { $0.isGoalLinked && !$0.isToday }
    }

    private var taskPickerListHeight: CGFloat {
        let sectionCount = [visibleTodayTaskCandidates, visibleGoalTaskCandidates]
            .filter { !$0.isEmpty }
            .count
        let contentHeight = CGFloat(visibleTaskCandidates.count * 43 + sectionCount * 27)
        return min(286, max(76, contentHeight))
    }

    private var selectedTask: PomodoroTaskCandidate? {
        guard let selectedTaskID else { return nil }
        return taskCandidates.first { $0.id == selectedTaskID }
    }

    private func selectTask(_ taskID: UUID?) {
        guard selectedTaskID != taskID else { return }
        selectedTaskID = taskID
    }

    private func startFocus() {
        let task = selectedTask
        timerManager.startFocus(
            category: selectedFocusCategory,
            linkedMemoID: task?.id,
            taskTitleSnapshot: task?.title
        )
        selectedTaskID = nil
    }

    private var productiveTransitionCategories: [String] {
        Constants.allCategories.filter { Constants.postBreakProductiveCategories.contains($0) }
    }

    private var presetChips: some View {
        HStack(spacing: 6) {
            ForEach(Constants.PomodoroPreset.allCases) { preset in
                Button {
                    applyPreset(preset)
                } label: {
                    Text(preset.rawValue)
                        .font(.system(size: 12.5, weight: currentPreset == preset ? .bold : .medium, design: .rounded))
                        .foregroundStyle(currentPreset == preset ? PopoverChrome.selectionInk : PopoverChrome.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous)
                                .fill(presetChipFill(for: preset))
                        )
                        .shadow(
                            color: PopoverChrome.isGamePixel ? .clear : (currentPreset == preset ? PopoverChrome.accent.opacity(0.28) : .clear),
                            radius: PopoverChrome.isGamePixel ? 0 : 8,
                            x: 0,
                            y: PopoverChrome.isGamePixel ? 0 : 4
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .onHover { isHovering in
                    hoveredPreset = isHovering ? preset : nil
                }
            }
        }
        .padding(4)
        .background(PopoverChrome.surfaceAlt.opacity(0.82), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(13), style: .continuous))
    }

    private var currentPreset: Constants.PomodoroPreset {
        if appState.focusMinutes == pomodoroFocusMinutes && appState.breakMinutes == pomodoroBreakMinutes {
            return .pomodoro
        } else if appState.focusMinutes == longFocusFocusMinutes && appState.breakMinutes == longFocusBreakMinutes {
            return .longFocus
        } else {
            return .custom
        }
    }

    private func applyPreset(_ preset: Constants.PomodoroPreset) {
        switch preset {
        case .pomodoro:
            appState.focusMinutes = pomodoroFocusMinutes
            appState.breakMinutes = pomodoroBreakMinutes
        case .longFocus:
            appState.focusMinutes = longFocusFocusMinutes
            appState.breakMinutes = longFocusBreakMinutes
        case .custom:
            appState.focusMinutes = customFocusMinutes
            appState.breakMinutes = customBreakMinutes
        }
    }

    private func presetChipFill(for preset: Constants.PomodoroPreset) -> Color {
        if currentPreset == preset {
            return PopoverChrome.selectionFill
        }
        if hoveredPreset == preset {
            return PopoverChrome.card
        }
        return .clear
    }

    private var statusText: String {
        switch appState.timerState {
        case .idle: return "준비"
        case .focusing: return "집중 중"
        case .paused: return "잠시 멈춤"
        case .breakAlert: return "집중 완료"
        case .breaking: return "휴식 중"
        }
    }

    private var statusColor: Color {
        switch appState.timerState {
        case .idle, .paused:
            return PopoverChrome.accent
        case .focusing:
            return .orange
        case .breakAlert:
            return .yellow
        case .breaking:
            return .green
        }
    }

    private var isFocusing: Bool {
        appState.timerState == .focusing
    }

    private var isFocusSessionActive: Bool {
        appState.timerState == .focusing || appState.timerState == .paused
    }

    private var showsProgress: Bool {
        switch appState.timerState {
        case .focusing, .breaking:
            return true
        default:
            return false
        }
    }

    private var focusIconName: String {
        isFocusSessionActive ? PopoverChrome.focusOnImageName : PopoverChrome.focusOffImageName
    }

    private var minutesString: String {
        let minutes = displayedSeconds / 60
        return String(format: "%02d", minutes)
    }

    private var secondsString: String {
        let seconds = displayedSeconds % 60
        return String(format: "%02d", seconds)
    }

    private var displayedSeconds: Int {
        appState.timerState == .idle ? appState.focusMinutes * 60 : appState.remainingSeconds
    }

    private func colonOpacity(at date: Date) -> Double {
        let cycle = 1.44
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
        let wave = (sin(phase * 2 * .pi - (.pi / 2)) + 1) / 2
        return 0.36 + (wave * 0.64)
    }

    private func focusIconOffset(at date: Date) -> CGFloat {
        let cycle = 3.1
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
        return CGFloat(sin(phase * 2 * .pi) * 1.4)
    }

    private var progress: Double {
        let total: Int
        switch appState.timerState {
        case .focusing, .paused:
            total = appState.focusMinutes * 60
        case .breaking:
            total = appState.breakMinutes * 60
        default:
            return 0
        }
        guard total > 0 else { return 0 }
        return Double(total - appState.remainingSeconds) / Double(total)
    }

}
