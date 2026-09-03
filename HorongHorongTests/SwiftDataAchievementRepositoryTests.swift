import SwiftData
import XCTest
@testable import 호롱호롱

/// 목표 저장소를 **진짜 SwiftData 로** 검사한다.
///
/// 특히 부모·자식이 **제목 문자열로** 이어져 있다는 점이 위험하다 — 제목을 고치면
/// 그것을 가리키던 자식들이 함께 바뀌어야 하는데, 안 그러면 조용히 연결이 끊긴다.
@MainActor
final class SwiftDataAchievementRepositoryTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = HorongHorongModelSchema.make()
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func draft(
        _ title: String,
        cadence: String = "주간",
        yearGoal: String? = nil,
        monthGoal: String? = nil,
        linkedMemoIDs: [UUID] = []
    ) -> AchievementGoalDraft {
        AchievementGoalDraft(
            title: title,
            emoji: "🎯",
            cadence: cadence,
            rule: "",
            targetCount: 1,
            targetValueText: nil,
            periodText: nil,
            dueDate: nil,
            colorHex: "#E87333",
            roleName: "나",
            vision: "",
            yearGoal: yearGoal,
            monthGoal: monthGoal,
            linkedMemoIDs: linkedMemoIDs,
            sourceRunID: nil,
            sourceSuggestionID: nil
        )
    }

    private func edit(title: String, dueDate: Date? = nil) -> AchievementGoalEditDraft {
        AchievementGoalEditDraft(
            title: title,
            emoji: "🎯",
            rule: "",
            targetCount: 1,
            rewardText: "",
            linkedMemoIDs: nil,
            dueDate: dueDate,
            additionalChildGoalIDs: nil
        )
    }

    // MARK: - 목표 CRUD

    func testCreateAndReadGoal() throws {
        let container = try makeContainer()
        let repository = SwiftDataAchievementRepository(context: container.mainContext)

        let created = try repository.createGoal(draft("주간 목표"), childGoalIDs: [], newChildTitles: [])

        XCTAssertEqual(created.title, "주간 목표")
        XCTAssertEqual(repository.goals().map(\.title), ["주간 목표"])
    }

    /// 제목만 적어둔 하위 목표는 저장할 때 실제 목표로 만들어진다.
    func testCreateGoalMakesNamedChildren() throws {
        let container = try makeContainer()
        let repository = SwiftDataAchievementRepository(context: container.mainContext)

        try repository.createGoal(
            draft("이번 달", cadence: "월간"),
            childGoalIDs: [],
            newChildTitles: ["첫째 주", "둘째 주"]
        )

        let weekly = repository.goals().filter { $0.cadence == "주간" }
        XCTAssertEqual(Set(weekly.map(\.title)), ["첫째 주", "둘째 주"])
        XCTAssertEqual(Set(weekly.compactMap(\.monthGoal)), ["이번 달"], "부모를 가리켜야 한다")
    }

    /// **제목이 곧 참조다.** 부모 제목을 고치면 자식의 `monthGoal` 도 따라 바뀌어야 한다.
    func testRenamingParentUpdatesChildReferences() throws {
        let container = try makeContainer()
        let repository = SwiftDataAchievementRepository(context: container.mainContext)
        let parent = try repository.createGoal(draft("9월 목표", cadence: "월간"), childGoalIDs: [], newChildTitles: [])
        try repository.createGoal(
            draft("주간 하나", monthGoal: "9월 목표"),
            childGoalIDs: [], newChildTitles: []
        )

        repository.updateGoal(id: parent.id, with: edit(title: "구월 목표"))

        let child = try XCTUnwrap(repository.goals().first { $0.cadence == "주간" })
        XCTAssertEqual(child.monthGoal, "구월 목표", "이름만 바꿨는데 연결이 끊기면 안 된다")
    }

    /// 연간 목표 제목을 고치면 하위 **월간** 목표의 `yearGoal` 이 따라와야 한다.
    func testRenamingYearlyGoalUpdatesMonthlyChildren() throws {
        let container = try makeContainer()
        let repository = SwiftDataAchievementRepository(context: container.mainContext)
        let yearly = try repository.createGoal(draft("2026년", cadence: "연간"), childGoalIDs: [], newChildTitles: [])
        try repository.createGoal(
            draft("9월", cadence: "월간", yearGoal: "2026년"),
            childGoalIDs: [], newChildTitles: []
        )

        repository.updateGoal(id: yearly.id, with: edit(title: "이천이십육년"))

        let monthly = try XCTUnwrap(repository.goals().first { $0.cadence == "월간" })
        XCTAssertEqual(monthly.yearGoal, "이천이십육년")
    }

    /// 역할 이름을 고치면 그 역할에 속한 **모든** 목표의 `roleName` 이 따라와야 한다.
    /// 안 그러면 여정 화면에서 목표들이 사라진 역할 아래에 남는다.
    func testRenamingPersonaUpdatesEveryGoalUnderIt() throws {
        let container = try makeContainer()
        let repository = SwiftDataAchievementRepository(context: container.mainContext)
        try repository.savePersonaVision(AchievementPersonaVisionDraft(
            personaName: "개발자",
            personaEmoji: "🧑‍💻",
            visionTitle: "더 나은 도구",
            visionText: "",
            visionEmoji: "🔭"
        ))
        var underPersona = draft("주간 하나")
        underPersona.roleName = "개발자"
        try repository.createGoal(underPersona, childGoalIDs: [], newChildTitles: [])

        let persona = try XCTUnwrap(repository.goals().first { $0.cadence == "역할" })
        repository.updateGoal(id: persona.id, with: edit(title: "엔지니어"))

        let underNewName = repository.goals().filter { $0.roleName == "엔지니어" }
        XCTAssertEqual(underNewName.count, 3, "역할 자신 · 비전 · 주간 목표가 모두 따라온다")
        XCTAssertTrue(repository.goals().allSatisfy { $0.roleName != "개발자" })
    }

    /// 비전 제목을 고치면 그 비전을 가리키던 목표들의 `vision` 이 따라와야 한다.
    func testRenamingVisionUpdatesGoalsPointingToIt() throws {
        let container = try makeContainer()
        let repository = SwiftDataAchievementRepository(context: container.mainContext)
        var withVision = draft("주간 하나")
        withVision.vision = "더 나은 도구"
        try repository.createGoal(withVision, childGoalIDs: [], newChildTitles: [])
        let vision = try repository.createGoal(
            draft("더 나은 도구", cadence: "비전"),
            childGoalIDs: [], newChildTitles: []
        )

        repository.updateGoal(id: vision.id, with: edit(title: "쓸모 있는 도구"))

        let weekly = try XCTUnwrap(repository.goals().first { $0.cadence == "주간" })
        XCTAssertEqual(weekly.vision, "쓸모 있는 도구")
    }

    /// 주간 목표에는 하위가 없다. 이름을 바꿔도 **다른 목표를 건드리면 안 된다.**
    func testRenamingWeeklyGoalTouchesNothingElse() throws {
        let container = try makeContainer()
        let repository = SwiftDataAchievementRepository(context: container.mainContext)
        let parent = try repository.createGoal(draft("9월", cadence: "월간"), childGoalIDs: [], newChildTitles: [])
        let weekly = try repository.createGoal(
            draft("주간 하나", monthGoal: "9월"),
            childGoalIDs: [], newChildTitles: []
        )

        repository.updateGoal(id: weekly.id, with: edit(title: "주간 첫째"))

        let after = try XCTUnwrap(repository.goals().first { $0.id == weekly.id })
        XCTAssertEqual(after.title, "주간 첫째")
        XCTAssertEqual(after.monthGoal, "9월", "부모와의 연결은 그대로")
        XCTAssertEqual(repository.goals().first { $0.id == parent.id }?.title, "9월", "부모는 안 바뀐다")
    }

    /// 기존 목표를 하위로 이어붙이면 부모의 역할·비전까지 물려받는다.
    func testConnectingChildInheritsParentContext() throws {
        let container = try makeContainer()
        let repository = SwiftDataAchievementRepository(context: container.mainContext)
        let orphan = try repository.createGoal(draft("떠 있는 주간"), childGoalIDs: [], newChildTitles: [])

        var monthly = draft("10월 목표", cadence: "월간")
        monthly.roleName = "개발자"
        monthly.vision = "더 나은 도구"
        try repository.createGoal(monthly, childGoalIDs: [orphan.id], newChildTitles: [])

        let child = try XCTUnwrap(repository.goals().first { $0.id == orphan.id })
        XCTAssertEqual(child.monthGoal, "10월 목표")
        XCTAssertEqual(child.roleName, "개발자")
        XCTAssertEqual(child.vision, "더 나은 도구")
    }

    func testDetachChildKeepsTheGoal() throws {
        let container = try makeContainer()
        let repository = SwiftDataAchievementRepository(context: container.mainContext)
        let parent = try repository.createGoal(draft("11월", cadence: "월간"), childGoalIDs: [], newChildTitles: ["주간"])
        let child = try XCTUnwrap(repository.goals().first { $0.cadence == "주간" })

        repository.detachChild(id: child.id, fromParentID: parent.id)

        let after = try XCTUnwrap(repository.goals().first { $0.id == child.id })
        XCTAssertNil(after.monthGoal, "부모와의 연결만 끊긴다")
        XCTAssertEqual(repository.goals().count, 2, "목표 자체는 남는다")
    }

    func testDeleteGoal() throws {
        let container = try makeContainer()
        let repository = SwiftDataAchievementRepository(context: container.mainContext)
        let goal = try repository.createGoal(draft("지울 목표"), childGoalIDs: [], newChildTitles: [])

        repository.deleteGoal(id: goal.id)

        XCTAssertTrue(repository.goals().isEmpty)
    }

    // MARK: - 달성 도장

    /// **한 번 찍은 값은 되돌리지 않는다.** 달성이 풀려도 «그때 달성했었다» 는 사실은 남는다.
    func testMarkCompletedIsWriteOnce() throws {
        let container = try makeContainer()
        let repository = SwiftDataAchievementRepository(context: container.mainContext)
        let goal = try repository.createGoal(draft("달성할 목표"), childGoalIDs: [], newChildTitles: [])
        let first = Date(timeIntervalSince1970: 1_000_000)

        repository.markCompleted(ids: [goal.id], at: first)
        repository.markCompleted(ids: [goal.id], at: Date())

        XCTAssertEqual(repository.goals().first?.completedAt, first)
    }

    // MARK: - 할일 일정

    /// **요일만 바꾸고 시각은 유지한다.** 오전 9시에 하던 일이 옮긴다고 자정이 되면 안 된다.
    func testRescheduleKeepsTimeOfDay() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataAchievementRepository(context: context)
        let calendar = Calendar.current

        let memo = Memo(content: "할 일", section: .todo)
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 9, minute: 30))!
        memo.startDate = start
        context.insert(memo)
        try context.save()

        let target = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5))!
        try repository.rescheduleMemos(ids: [memo.id], targetDays: [target])

        let moved = try XCTUnwrap(repository.memos().first { $0.id == memo.id })
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: try XCTUnwrap(moved.startDate))
        XCTAssertEqual(parts.day, 5)
        XCTAssertEqual(parts.hour, 9)
        XCTAssertEqual(parts.minute, 30)
    }

    /// 여러 건을 여러 날에 **돌아가며** 배치한다.
    func testRescheduleDistributesAcrossDays() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataAchievementRepository(context: context)
        let calendar = Calendar.current
        let base = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 9))!

        let memos = (0..<3).map { index -> Memo in
            let memo = Memo(content: "할 일 \(index)", section: .todo)
            memo.startDate = base
            context.insert(memo)
            return memo
        }
        try context.save()

        let days = [
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 4))!,
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 5))!
        ]
        try repository.rescheduleMemos(ids: memos.map(\.id), targetDays: days)

        let stored = repository.memos()
        let placedDays = memos.compactMap { memo in
            stored.first { $0.id == memo.id }?.startDate.map { calendar.component(.day, from: $0) }
        }
        XCTAssertEqual(placedDays, [4, 5, 4], "날짜 수보다 많으면 처음으로 돌아간다")
    }

    func testToggleMemoCompletion() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataAchievementRepository(context: context)
        let memo = Memo(content: "할 일", section: .todo)
        memo.isPinned = true
        context.insert(memo)
        try context.save()

        XCTAssertTrue(try repository.toggleMemoCompletion(id: memo.id))
        XCTAssertFalse(memo.isPinned, "끝낸 일은 고정을 푼다")
        XCTAssertFalse(try repository.toggleMemoCompletion(id: memo.id))
    }

    /// 묶을 수 있는 할일은 Todo 섹션이면서 아직 안 끝낸 것뿐이다.
    func testLinkableMemosFiltering() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataAchievementRepository(context: context)

        context.insert(Memo(content: "할 일", section: .todo))
        let done = Memo(content: "끝낸 일", section: .todo)
        done.isCompletedValue = true
        context.insert(done)
        context.insert(Memo(content: "쪽지", section: .quickNote))
        let archived = Memo(content: "보관", section: .todo)
        archived.isArchivedValue = true
        context.insert(archived)
        try context.save()

        XCTAssertEqual(repository.linkableMemos().map(\.content), ["할 일"])
        XCTAssertEqual(repository.memos().count, 3, "보관한 것은 전체 조회에서도 빠진다")
    }

    // MARK: - 역할·비전

    func testSavePersonaVisionCreatesBoth() throws {
        let container = try makeContainer()
        let repository = SwiftDataAchievementRepository(context: container.mainContext)

        try repository.savePersonaVision(AchievementPersonaVisionDraft(
            personaName: "개발자",
            personaEmoji: "🧑‍💻",
            visionTitle: "더 나은 도구",
            visionText: "매일 조금씩",
            visionEmoji: "🔭"
        ))

        let goals = repository.goals()
        XCTAssertEqual(goals.filter { $0.cadence == "역할" }.map(\.title), ["개발자"])
        XCTAssertEqual(goals.filter { $0.cadence == "비전" }.map(\.title), ["더 나은 도구"])
    }

    /// 같은 이름의 역할을 다시 만들지 않는다 — 비전만 하나 더 붙는다.
    func testSavePersonaVisionReusesExistingPersona() throws {
        let container = try makeContainer()
        let repository = SwiftDataAchievementRepository(context: container.mainContext)
        let draft = AchievementPersonaVisionDraft(
            personaName: "개발자",
            personaEmoji: "🧑‍💻",
            visionTitle: "비전 하나",
            visionText: "",
            visionEmoji: "🔭"
        )
        try repository.savePersonaVision(draft)

        try repository.savePersonaVision(AchievementPersonaVisionDraft(
            personaName: "개발자",
            personaEmoji: "🧑‍💻",
            visionTitle: "비전 둘",
            visionText: "",
            visionEmoji: "🔭"
        ))

        let goals = repository.goals()
        XCTAssertEqual(goals.filter { $0.cadence == "역할" }.count, 1)
        XCTAssertEqual(goals.filter { $0.cadence == "비전" }.count, 2)
    }
}
