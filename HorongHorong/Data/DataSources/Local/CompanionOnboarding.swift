import Combine
import Foundation
import SwiftData

/// 온보딩 한 단계에서 띄울 화면.
enum CompanionOnboardingScreen: String, Equatable, Sendable {
    case popoverTimer = "popover.timer"
    case popoverMemo = "popover.memo"
    case popoverStats = "popover.stats"
    case popoverAchievement = "popover.achievement"
    case windowStats = "window.stats"
    case settingsCompanion = "settings.companion"
    case settingsMemo = "settings.memo"
}

struct CompanionOnboardingStep: Equatable, Sendable {
    let title: String
    /// 호로롱이 말할 문장.
    let line: String
    let screen: CompanionOnboardingScreen?
    /// 이 단계에서 화면상 강조할 요소. 대본의 `<!-- highlight: ... -->` 값.
    let highlight: String?
    /// 이 단계에서 호로롱이 대신 눌러줄 동작. 대본의 `<!-- action: ... -->` 값.
    let action: String?
}

struct CompanionOnboardingScenario: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let steps: [CompanionOnboardingStep]
}

/// `Resources/Guide/onboarding.md` 를 읽어 단계 목록으로 바꾼다.
///
/// 문서는 사람이 읽고 고치는 것이 먼저다. 그래서 기계용 표시는 HTML 주석으로만 두어
/// GitHub 에서 렌더링될 때 보이지 않게 했다.
enum CompanionOnboardingScript {
    static let resourceName = "onboarding"

    /// `## 제목` + 바로 뒤의 `<!-- id: ... -->` 가 있는 것만 시나리오로 본다.
    /// 안내문처럼 id 가 없는 `##` 문단은 대본이 아니므로 건너뛴다.
    static func parse(_ markdown: String) -> [CompanionOnboardingScenario] {
        var scenarios: [CompanionOnboardingScenario] = []

        var scenarioTitle: String?
        var scenarioID: String?
        var steps: [CompanionOnboardingStep] = []

        var stepTitle: String?
        var stepScreen: CompanionOnboardingScreen?
        var stepHighlight: String?
        var stepAction: String?
        var stepLines: [String] = []

        func flushStep() {
            defer {
                stepTitle = nil
                stepScreen = nil
                stepHighlight = nil
                stepAction = nil
                stepLines = []
            }
            guard let stepTitle, !stepLines.isEmpty else { return }
            steps.append(
                CompanionOnboardingStep(
                    title: stepTitle,
                    line: stepLines.joined(separator: " "),
                    screen: stepScreen,
                    highlight: stepHighlight,
                    action: stepAction
                )
            )
        }

        func flushScenario() {
            flushStep()
            defer {
                scenarioTitle = nil
                scenarioID = nil
                steps = []
            }
            guard let scenarioID, let scenarioTitle, !steps.isEmpty else { return }
            scenarios.append(
                CompanionOnboardingScenario(id: scenarioID, title: scenarioTitle, steps: steps)
            )
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("## ") {
                flushScenario()
                scenarioTitle = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                continue
            }

            if line.hasPrefix("### ") {
                flushStep()
                stepTitle = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                continue
            }

            if let value = comment(named: "id", in: line) {
                // 단계가 시작되기 전에 나온 id 만 시나리오 것으로 본다.
                if stepTitle == nil { scenarioID = value }
                continue
            }

            if let value = comment(named: "screen", in: line) {
                stepScreen = CompanionOnboardingScreen(rawValue: value)
                continue
            }

            if let value = comment(named: "highlight", in: line) {
                stepHighlight = value
                continue
            }

            if let value = comment(named: "action", in: line) {
                stepAction = value
                continue
            }

            if line.hasPrefix(">") {
                let text = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { stepLines.append(text) }
            }
        }
        flushScenario()

        return scenarios
    }

    /// `<!-- name: value -->` 에서 value 를 꺼낸다.
    private static func comment(named name: String, in line: String) -> String? {
        guard line.hasPrefix("<!--"), line.hasSuffix("-->") else { return nil }
        let inner = line
            .dropFirst(4)
            .dropLast(3)
            .trimmingCharacters(in: .whitespaces)
        let parts = inner.split(separator: ":", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count == 2, parts[0] == name, !parts[1].isEmpty else { return nil }
        return parts[1]
    }

    /// 번들에 담긴 대본. 없으면 빈 배열이라 온보딩이 그냥 실행되지 않는다.
    static func loadFromBundle(_ bundle: Bundle = .main) -> [CompanionOnboardingScenario] {
        guard let url = bundle.url(forResource: resourceName, withExtension: "md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return parse(markdown)
    }
}

/// 온보딩을 자동으로 띄울지 판단한다.
enum CompanionOnboardingTrigger {
    /// 아직 본 적이 없고, 쓴 흔적도 전혀 없을 때만 자동 실행한다.
    ///
    /// 플래그만 보면 앱을 지웠다 깔아도 `UserDefaults` 가 남아 다시 안 뜬다.
    /// 데이터만 보면 기록을 모두 지운 기존 사용자에게 다시 뜬다. 그래서 둘 다 본다.
    static func shouldStartAutomatically(
        hasSeenOnboarding: Bool,
        memoCount: Int,
        focusSessionCount: Int
    ) -> Bool {
        guard !hasSeenOnboarding else { return false }
        return memoCount == 0 && focusSessionCount == 0
    }
}

/// 처음 사용자의 안내 화면에만 공급하는 메모리 전용 예시 데이터.
///
/// 실제 저장소와 다른 `ModelContainer`를 쓰므로 안내를 끝내면 통째로 사라진다.
@MainActor
final class CompanionOnboardingDemoStore: ObservableObject {
    static let shared = CompanionOnboardingDemoStore()

    @Published private(set) var modelContainer: ModelContainer?

    var isActive: Bool { modelContainer != nil }

    static func shouldUseDemoData(
        memoCount: Int,
        focusSessionCount: Int,
        achievementGoalCount: Int
    ) -> Bool {
        memoCount == 0 && focusSessionCount == 0 && achievementGoalCount == 0
    }

    @discardableResult
    func startIfNeeded(
        memoCount: Int,
        focusSessionCount: Int,
        achievementGoalCount: Int,
        now: Date = Date()
    ) -> Bool {
        stop()
        guard Self.shouldUseDemoData(
            memoCount: memoCount,
            focusSessionCount: focusSessionCount,
            achievementGoalCount: achievementGoalCount
        ) else {
            return false
        }

        do {
            let schema = HorongHorongModelSchema.make()
            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true
            )
            let container = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
            try Self.seed(container.mainContext, now: now)
            modelContainer = container
            return true
        } catch {
            modelContainer = nil
            return false
        }
    }

    func stop() {
        guard modelContainer != nil else { return }
        modelContainer = nil
    }

    private static func seed(_ context: ModelContext, now: Date) throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let anchor = max(now, today.addingTimeInterval(3 * 60 * 60))

        let memoSeeds: [(content: String, icon: String, pinned: Bool, completed: Bool)] = [
            ("프로젝트 기획안 마무리", "🐜", true, false),
            ("SwiftUI 강의 2강 듣기", "📚", false, false),
            ("사용자 인터뷰 질문 정리", "💡", false, false),
            ("온보딩 문구 다듬기", "📝", true, false),
            ("디자인 레퍼런스 조사", "🔗", false, false),
            ("지난주 회고 정리", "☕️", false, true),
        ]
        let memos = memoSeeds.enumerated().map { index, seed in
            let memo = Todo(content: seed.content, icon: seed.icon)
            memo.isPinned = seed.pinned
            memo.startDate = today
            memo.deadline = calendar.date(byAdding: .day, value: index % 3 + 1, to: today)
            memo.createdAt = anchor.addingTimeInterval(TimeInterval(-(index + 1) * 24 * 60 * 60))
            memo.updatedAt = anchor.addingTimeInterval(TimeInterval(-(index + 1) * 18 * 60))
            if seed.completed {
                memo.setCompleted(true, at: anchor.addingTimeInterval(-2 * 60 * 60))
            }
            return memo
        }
        for memo in memos {
            context.insert(memo)
        }

        let goals = [
            AchievementGoalRecord(
                title: "사이드 프로젝트 꾸준히 진행하기",
                emoji: "🚀",
                cadence: "주간",
                rule: "연결한 할 일 3개 완료",
                targetCount: 3,
                dueDate: calendar.date(byAdding: .day, value: 6, to: today),
                rewardText: "좋아하는 카페 가기",
                roleName: "메이커",
                vision: "작은 결과물을 꾸준히 완성한다",
                linkedMemoIDs: Array(memos.prefix(3).map(\.id))
            ),
            AchievementGoalRecord(
                title: "배운 내용을 매일 기록하기",
                emoji: "🌱",
                cadence: "주간",
                rule: "기록과 공부 할 일 3개 완료",
                targetCount: 3,
                dueDate: calendar.date(byAdding: .day, value: 5, to: today),
                rewardText: "저녁 산책하기",
                roleName: "학습자",
                vision: "배운 것을 내 언어로 남긴다",
                linkedMemoIDs: Array(memos.suffix(3).map(\.id))
            ),
        ]
        for (index, goal) in goals.enumerated() {
            goal.createdAt = today.addingTimeInterval(TimeInterval(-index * 24 * 60 * 60))
            goal.updatedAt = anchor.addingTimeInterval(TimeInterval(-index * 30 * 60))
            context.insert(goal)
        }

        let development = Constants.categoryName("개발")
        let studyCategory = Constants.categoryName("공부")
        let research = Constants.categoryName("조사")
        let records = Constants.categoryName("기록")
        let communication = Constants.categoryName("소통")
        let categories = [development, studyCategory, research, records, communication]
        let experiences: [PomodoroFocusExperience] = [
            .deeplyFocused,
            .mostlyFocused,
            .frequentlyDistracted,
            .difficultToFocus,
        ]
        let progressResults: [PomodoroProgressResult] = [
            .completedAsPlanned,
            .meaningfulProgress,
            .littleProgress,
            .goalChanged,
        ]
        let durationMinutes = [25, 50, 35, 25, 45]
        let inputRatios = [0.58, 0.71, 0.83, 0.92, 0.97]
        let recordedRatios = [0.68, 0.79, 0.88, 0.95, 1.0]
        let appsByCategory: [String: [(name: String, bundleIdentifier: String)]] = [
            development: [
                ("Xcode", "com.apple.dt.Xcode"),
                ("터미널", "com.apple.Terminal"),
                ("Safari", "com.apple.Safari"),
                ("미리보기", "com.apple.Preview"),
            ],
            studyCategory: [
                ("Safari", "com.apple.Safari"),
                ("도서", "com.apple.iBooksX"),
                ("메모", "com.apple.Notes"),
                ("미리보기", "com.apple.Preview"),
            ],
            research: [
                ("Safari", "com.apple.Safari"),
                ("미리보기", "com.apple.Preview"),
                ("메모", "com.apple.Notes"),
                ("Finder", "com.apple.finder"),
            ],
            records: [
                ("Obsidian", "md.obsidian"),
                ("메모", "com.apple.Notes"),
                ("Safari", "com.apple.Safari"),
                ("미리보기", "com.apple.Preview"),
            ],
            communication: [
                ("Mail", "com.apple.mail"),
                ("메시지", "com.apple.MobileSMS"),
                ("Safari", "com.apple.Safari"),
                ("메모", "com.apple.Notes"),
            ],
        ]

        var globalSessionIndex = 0
        for dayOffset in -13...0 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else {
                continue
            }
            let sessionCount = dayOffset == 0 ? 7 : 1 + abs(dayOffset) % 3
            for sessionIndex in 0..<sessionCount {
                let category = categories[globalSessionIndex % categories.count]
                let memo = memos[(globalSessionIndex + sessionIndex) % memos.count]
                let duration = durationMinutes[globalSessionIndex % durationMinutes.count]
                let startMinutes = 7 * 60 + 30 + sessionIndex * 100 + abs(dayOffset) % 3 * 10
                let start = day.addingTimeInterval(TimeInterval(startMinutes * 60))
                let endKind: FocusSessionEndKind = globalSessionIndex % 6 == 0
                    ? .recordedEarly
                    : .timerCompleted
                let session = makeSession(
                    start: start,
                    durationMinutes: duration,
                    category: category,
                    memo: memo,
                    inputRatio: inputRatios[globalSessionIndex % inputRatios.count],
                    endKind: endKind
                )
                context.insert(session)

                let experience = experiences[globalSessionIndex % experiences.count]
                let progress = progressResults[globalSessionIndex % progressResults.count]
                let skipsReflection = dayOffset == -1 && sessionIndex == 0
                if skipsReflection {
                    session.reflectionDeferredAt = start.addingTimeInterval(TimeInterval(duration * 60 + 60))
                } else {
                    let reason: PomodoroIncompleteReason?
                    switch progress {
                    case .completedAsPlanned:
                        reason = nil
                    case .meaningfulProgress:
                        reason = .continuedForQuality
                    case .littleProgress:
                        reason = .distracted
                    case .goalChanged:
                        reason = .switchedTask
                    }
                    context.insert(
                        PomodoroReflection(
                            focusSessionID: session.id,
                            focusExperience: experience,
                            progressResult: progress,
                            incompleteReason: reason,
                            answeredAt: start.addingTimeInterval(TimeInterval(duration * 60 + 90))
                        )
                    )
                }

                if progress == .completedAsPlanned && globalSessionIndex % 4 == 0 {
                    context.insert(
                        PomodoroTaskCompletion(
                            focusSessionID: session.id,
                            linkedMemoID: memo.id,
                            taskTitleSnapshot: memo.content,
                            completedAt: start.addingTimeInterval(TimeInterval(duration * 60 + 120)),
                            didMarkMemoCompleted: false,
                            memoWasPinnedBeforeCompletion: memo.isPinned
                        )
                    )
                }

                let appCount = 1 + globalSessionIndex % 4
                let recordedSeconds = Int(
                    Double(duration * 60)
                        * recordedRatios[globalSessionIndex % recordedRatios.count]
                )
                let gapSeconds = appCount > 1 ? 20 : 0
                let segmentSeconds = max(
                    1,
                    (recordedSeconds - gapSeconds * (appCount - 1)) / appCount
                )
                let apps = appsByCategory[category] ?? []
                var segmentStart = start
                for appIndex in 0..<appCount {
                    let isLast = appIndex == appCount - 1
                    let usedSeconds = segmentSeconds * appIndex + gapSeconds * appIndex
                    let remainingSeconds = max(1, recordedSeconds - usedSeconds)
                    let currentDuration = isLast ? remainingSeconds : min(segmentSeconds, remainingSeconds)
                    let showsDistraction = isLast && appCount > 1 && globalSessionIndex % 5 == 0
                    let app = showsDistraction
                        ? (name: "메시지", bundleIdentifier: "com.apple.MobileSMS")
                        : apps[appIndex % apps.count]
                    let segmentCategory = showsDistraction ? communication : category
                    let segmentEnd = segmentStart.addingTimeInterval(TimeInterval(currentDuration))
                    let segment = AppUsageSegment(
                        appName: app.name,
                        bundleIdentifier: app.bundleIdentifier,
                        category: segmentCategory,
                        startTime: segmentStart,
                        endTime: segmentEnd
                    )
                    context.insert(segment)

                    let record = AppUsageRecord(
                        appName: app.name,
                        bundleIdentifier: app.bundleIdentifier,
                        category: segmentCategory,
                        date: day
                    )
                    record.durationSeconds = currentDuration
                    context.insert(record)
                    segmentStart = segmentEnd.addingTimeInterval(TimeInterval(gapSeconds))
                }

                globalSessionIndex += 1
            }
        }

        try context.save()
    }

    private static func makeSession(
        start: Date,
        durationMinutes: Int,
        category: String,
        memo: Todo,
        inputRatio: Double,
        endKind: FocusSessionEndKind
    ) -> FocusSession {
        let plannedMinutes = endKind == .recordedEarly ? durationMinutes + 10 : durationMinutes
        let session = FocusSession(
            focusMinutes: plannedMinutes,
            breakMinutes: 5,
            category: category,
            linkedMemoID: memo.id,
            taskTitleSnapshot: memo.content
        )
        session.startedAt = start
        session.endedAt = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        session.completed = true
        session.inputActiveSeconds = Int(Double(durationMinutes * 60) * inputRatio)
        session.actualFocusSeconds = durationMinutes * 60
        session.endKind = endKind
        return session
    }
}
