import Foundation
import SwiftData
import SwiftUI

/// 구현체를 만들어 화면에 건네는 곳. **여기만 «누가 무엇으로 구현됐는지» 를 안다.**
///
/// ViewModel 이 자기 Repository 를 직접 만들면 저장 기술이 Presentation 으로 새고,
/// 테스트에서 가짜 구현으로 바꿔 끼울 수 없다(CLAUDE.md §4 App).
///
/// 기능을 옮길 때마다 여기에 한 줄씩 는다.
@MainActor
final class DependencyContainer {
    let referenceRepository: ReferenceRepository
    let quickNoteRepository: QuickNoteRepository
    let todoRepository: TodoRepository
    let diaryRepository: DiaryRepository
    let sleepGateway: SleepGateway
    let vaultRepository: VaultRepository
    let agentGateway: AgentGateway
    let newsRepository: NewsRepository
    let newsPipelineGateway: NewsPipelineGateway
    let rewardRepository: RewardRepository
    let achievementRepository: AchievementRepository
    let pomodoroTaskRepository: PomodoroTaskRepository
    let reminderImportRepository: ReminderImportRepository
    let reflectionRepository: PomodoroReflectionRepository
    let statsRecordRepository: StatsRecordRepository

    init(modelContainer: ModelContainer, newsPipelineService: NewsPipelineService) {
        let context = modelContainer.mainContext
        referenceRepository = SwiftDataReferenceRepository(context: context)
        quickNoteRepository = SwiftDataQuickNoteRepository(context: context)
        todoRepository = SwiftDataTodoRepository(context: context)
        diaryRepository = SwiftDataDiaryRepository(context: context)
        sleepGateway = HealthSleepGateway()
        vaultRepository = FileSystemVaultRepository()
        agentGateway = CLIAgentAdapter()
        newsRepository = SwiftDataNewsRepository(context: context)
        newsPipelineGateway = NewsPipelineAdapter(service: newsPipelineService, context: context)
        rewardRepository = SwiftDataRewardRepository(context: context)
        achievementRepository = SwiftDataAchievementRepository(context: context)
        pomodoroTaskRepository = SwiftDataPomodoroTaskRepository(context: context)
        reminderImportRepository = SwiftDataReminderImportRepository(context: context)
        reflectionRepository = SwiftDataPomodoroReflectionRepository(context: context)
        statsRecordRepository = SwiftDataStatsRecordRepository(context: context)
    }
}

private struct DependencyContainerKey: @preconcurrency EnvironmentKey {
    /// 앱은 시작할 때 반드시 주입한다. 미리보기·테스트가 주입을 잊으면 여기서 멈춘다 —
    /// 조용히 빈 화면이 되는 것보다 낫다.
    @MainActor
    static let defaultValue: DependencyContainer? = nil
}

extension EnvironmentValues {
    var dependencies: DependencyContainer? {
        get { self[DependencyContainerKey.self] }
        set { self[DependencyContainerKey.self] = newValue }
    }
}
