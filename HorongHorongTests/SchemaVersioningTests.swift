import XCTest
import SwiftData
@testable import 호롱호롱

/// `VersionedSchema` 를 도입하면서 **기존 저장소를 못 열게 되는 것**이 유일한 위험이다.
/// 인메모리로는 검증되지 않는다 — 디스크에 남아 있는 옛 저장소를 여는 상황이라야 한다.
@MainActor
final class SchemaVersioningTests: XCTestCase {
    nonisolated(unsafe) private var storeURL: URL!

    override func setUpWithError() throws {
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("schema-v1-\(UUID().uuidString).store")
    }

    override func tearDownWithError() throws {
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(
                at: storeURL.deletingPathExtension().appendingPathExtension("store" + suffix)
            )
        }
    }

    /// 마이그레이션 계획 **없이** 만든 저장소를, 계획을 **붙인** 컨테이너로 다시 연다.
    /// 이게 실제 사용자에게 일어나는 일이다.
    func testStoreCreatedWithoutPlanOpensWithPlan() throws {
        let schema = HorongHorongModelSchema.make()
        let configuration = ModelConfiguration(schema: schema, url: storeURL)

        // ① 예전 방식 — 계획 없이 만들고 데이터를 넣는다.
        do {
            let legacy = try ModelContainer(for: schema, configurations: [configuration])
            let context = legacy.mainContext
            context.insert(Memo(content: "이전 버전에서 쓴 기록", section: .todo))
            context.insert(Memo(content: "빠른 메모", section: .quickNote))
            context.insert(DiaryEntry(day: Calendar.current.startOfDay(for: Date())))
            try context.save()
        }

        // ② 새 방식 — 마이그레이션 계획을 붙여 같은 파일을 연다.
        let migrated = try ModelContainer(
            for: schema,
            migrationPlan: HorongHorongMigrationPlan.self,
            configurations: [configuration]
        )
        let context = migrated.mainContext

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Memo>()), 2, "기록이 그대로 읽혀야 한다")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DiaryEntry>()), 1)

        let todos = try context.fetch(
            FetchDescriptor<Memo>(predicate: #Predicate { $0.sectionRaw == "todo" })
        )
        XCTAssertEqual(todos.first?.content, "이전 버전에서 쓴 기록", "내용까지 온전해야 한다")
    }

    /// V1 이 실제 스키마와 같은 것을 가리키는지. 어긋나면 기존 저장소를 못 연다.
    func testV1DeclaresEveryRegisteredModel() {
        let names = Set(HorongHorongSchemaV1.models.map { String(describing: $0) })

        // 앱이 실제로 저장하는 모델들. 하나라도 빠지면 그 데이터가 사라진 것처럼 보인다.
        for expected in ["Memo", "DiaryEntry", "AchievementGoalRecord", "FocusSession",
                         "AppUsageRecord", "AppUsageSegment", "AttentionEvent",
                         "RewardLedgerEntry", "NewsJob", "NewsReportIndex"] {
            XCTAssertTrue(names.contains(expected), "\(expected) 가 V1 에 없다")
        }
        XCTAssertEqual(HorongHorongSchemaV1.models.count, 19)
    }

    /// V2 가 실제 스키마와 같은 것을 가리키는지. 어긋나면 기존 저장소를 못 연다.
    func testV2DeclaresEveryRegisteredModel() {
        let names = Set(HorongHorongSchemaV2.models.map { String(describing: $0) })

        for expected in ["SecondBrainRecord", "Memo", "DiaryEntry", "AchievementGoalRecord", "FocusSession",
                         "AppUsageRecord", "AppUsageSegment", "AttentionEvent",
                         "RewardLedgerEntry", "NewsJob", "NewsReportIndex"] {
            XCTAssertTrue(names.contains(expected), "\(expected) 가 V2 에 없다")
        }
        XCTAssertEqual(HorongHorongSchemaV2.models.count, 20)
    }

    /// V3 가 실제 스키마와 같은 것을 가리키는지. 어긋나면 기존 저장소를 못 연다.
    func testV3DeclaresEveryRegisteredModel() {
        let names = Set(HorongHorongSchemaV3.models.map { String(describing: $0) })

        for expected in ["Todo", "QuickNote", "Reference", "Diary",
                         "SecondBrainRecord", "Memo", "DiaryEntry", "AchievementGoalRecord", "FocusSession",
                         "AppUsageRecord", "AppUsageSegment", "AttentionEvent",
                         "RewardLedgerEntry", "NewsJob", "NewsReportIndex"] {
            XCTAssertTrue(names.contains(expected), "\(expected) 가 V3 에 없다")
        }
        XCTAssertEqual(HorongHorongSchemaV3.models.count, 24)
    }

    /// V3 도입에 따른 마이그레이션 계획 검증.
    func testMigrationPlanHasThreeVersionsAndStages() {
        XCTAssertEqual(HorongHorongMigrationPlan.schemas.count, 3)
        XCTAssertEqual(HorongHorongMigrationPlan.stages.count, 2)
        XCTAssertEqual(HorongHorongSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(HorongHorongSchemaV2.versionIdentifier, Schema.Version(2, 0, 0))
        XCTAssertEqual(HorongHorongSchemaV3.versionIdentifier, Schema.Version(3, 0, 0))
    }

    /// V1 저장소(Memo)를 V2 스키마(SecondBrainRecord)로 마이그레이션하고 데이터가 무손실 이전되는지 검증한다.
    func testV1StoreMigratesToV2AndCopiesMemoToSecondBrainRecord() throws {
        let v1Schema = Schema(versionedSchema: HorongHorongSchemaV1.self)
        let configuration = ModelConfiguration(schema: v1Schema, url: storeURL)

        var testMemoID = UUID()
        let now = Date()

        // ① V1 스키마 컨테이너에서 Memo 데이터 저장
        do {
            let v1Container = try ModelContainer(for: v1Schema, configurations: [configuration])
            let v1Context = v1Container.mainContext
            let memo1 = Memo(content: "할 일 1", section: .todo)
            testMemoID = memo1.id
            memo1.startDate = now
            memo1.deadline = now.addingTimeInterval(3600)
            memo1.isPinned = true
            let memo2 = Memo(content: "참고자료 2", section: .reference)
            v1Context.insert(memo1)
            v1Context.insert(memo2)
            try v1Context.save()
        }

        // ② V2 스키마 + 마이그레이션 플랜으로 컨테이너 열기
        let v2Schema = HorongHorongModelSchema.make()
        let v2Configuration = ModelConfiguration(schema: v2Schema, url: storeURL)
        let v2Container = try ModelContainer(
            for: v2Schema,
            migrationPlan: HorongHorongMigrationPlan.self,
            configurations: [v2Configuration]
        )
        let v2Context = v2Container.mainContext

        // ③ Memo -> SecondBrainRecord 데이터 복사 마이그레이션 실행
        let testDefaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        AppDelegate.migrateMemoToSecondBrainRecords(in: v2Context, defaults: testDefaults)

        // ④ 검증: SecondBrainRecord로 데이터가 온전히 복사되었는가
        let records = try v2Context.fetch(FetchDescriptor<SecondBrainRecord>(sortBy: [SortDescriptor(\.createdAt)]))
        XCTAssertEqual(records.count, 2, "2건의 기록이 SecondBrainRecord로 이전되어야 한다")

        let migratedMemo1 = try XCTUnwrap(records.first { $0.id == testMemoID })
        XCTAssertEqual(migratedMemo1.content, "할 일 1")
        XCTAssertEqual(migratedMemo1.resolvedSection, .todo)
        XCTAssertTrue(migratedMemo1.isPinned)
        XCTAssertEqual(migratedMemo1.startDate, now)

        // ⑤ 검증: 구 Memo 테이블은 비워졌는가
        let remainingMemos = try v2Context.fetchCount(FetchDescriptor<Memo>())
        XCTAssertEqual(remainingMemos, 0, "기존 Memo 테이블의 데이터는 이전 완료 후 정리되어야 한다")
    }

    /// V2 저장소(SecondBrainRecord + DiaryEntry)를 V3 스키마(Todo, QuickNote, Reference, Diary)로 마이그레이션하고 무손실 분산 이전되는지 검증한다.
    func testV2StoreMigratesToV3AndCopiesToDividedModels() throws {
        let v2Schema = Schema(versionedSchema: HorongHorongSchemaV2.self)
        let configuration = ModelConfiguration(schema: v2Schema, url: storeURL)

        let todoID = UUID()
        let quickNoteID = UUID()
        let referenceID = UUID()
        let diaryDate = Calendar.current.startOfDay(for: Date())
        let now = Date()

        // ① V2 스키마 컨테이너에서 SecondBrainRecord 및 DiaryEntry 저장
        do {
            let v2Container = try ModelContainer(for: v2Schema, configurations: [configuration])
            let v2Context = v2Container.mainContext

            let todo = SecondBrainRecord(content: "할 일 테스트", section: .todo)
            todo.id = todoID
            todo.startDate = now
            todo.isPinned = true

            let note = SecondBrainRecord(content: "빠른 메모 테스트", section: .quickNote)
            note.id = quickNoteID
            note.icon = "📝"

            let reference = SecondBrainRecord(content: "https://example.com/ref", section: .reference)
            reference.id = referenceID

            let diary = DiaryEntry(day: diaryDate)
            diary.body = "오늘의 일기"
            diary.mood = .good

            v2Context.insert(todo)
            v2Context.insert(note)
            v2Context.insert(reference)
            v2Context.insert(diary)
            try v2Context.save()
        }

        // ② V3 스키마 + 마이그레이션 플랜으로 컨테이너 열기
        let v3Schema = HorongHorongModelSchema.make()
        let v3Configuration = ModelConfiguration(schema: v3Schema, url: storeURL)
        let v3Container = try ModelContainer(
            for: v3Schema,
            migrationPlan: HorongHorongMigrationPlan.self,
            configurations: [v3Configuration]
        )
        let v3Context = v3Container.mainContext

        // ③ SecondBrainRecord + DiaryEntry -> Todo / QuickNote / Reference / Diary 분산 이전 실행
        AppDelegate.migrateSecondBrainToDividedModels(in: v3Context)

        // ④ 검증: Todo로 데이터가 온전히 복사되었는가
        let todos = try v3Context.fetch(FetchDescriptor<Todo>())
        XCTAssertEqual(todos.count, 1)
        let migratedTodo = try XCTUnwrap(todos.first { $0.id == todoID })
        XCTAssertEqual(migratedTodo.content, "할 일 테스트")
        XCTAssertTrue(migratedTodo.isPinned)
        XCTAssertEqual(migratedTodo.startDate, now)

        // ⑤ 검증: QuickNote로 데이터가 온전히 복사되었는가
        let notes = try v3Context.fetch(FetchDescriptor<QuickNote>())
        XCTAssertEqual(notes.count, 1)
        let migratedNote = try XCTUnwrap(notes.first { $0.id == quickNoteID })
        XCTAssertEqual(migratedNote.content, "빠른 메모 테스트")
        XCTAssertEqual(migratedNote.icon, "📝")

        // ⑥ 검증: Reference로 데이터가 온전히 복사되었는가
        let references = try v3Context.fetch(FetchDescriptor<Reference>())
        XCTAssertEqual(references.count, 1)
        let migratedRef = try XCTUnwrap(references.first { $0.id == referenceID })
        XCTAssertEqual(migratedRef.content, "https://example.com/ref")

        // ⑦ 검증: Diary로 데이터가 온전히 복사되었는가
        let diaries = try v3Context.fetch(FetchDescriptor<Diary>())
        XCTAssertEqual(diaries.count, 1)
        let migratedDiary = try XCTUnwrap(diaries.first)
        XCTAssertEqual(migratedDiary.day, diaryDate)
        XCTAssertEqual(migratedDiary.body, "오늘의 일기")
        XCTAssertEqual(migratedDiary.mood, .good)

        // ⑧ 검증: 구 SecondBrainRecord 및 DiaryEntry 테이블은 비워졌는가
        let remainingRecords = try v3Context.fetchCount(FetchDescriptor<SecondBrainRecord>())
        XCTAssertEqual(remainingRecords, 0, "기존 SecondBrainRecord 테이블의 데이터는 이전 완료 후 정리되어야 한다")
        let remainingDiaryEntries = try v3Context.fetchCount(FetchDescriptor<DiaryEntry>())
        XCTAssertEqual(remainingDiaryEntries, 0, "기존 DiaryEntry 테이블의 데이터는 이전 완료 후 정리되어야 한다")
    }
}
