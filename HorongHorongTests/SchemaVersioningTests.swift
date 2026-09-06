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

    /// V8 도입에 따른 마이그레이션 계획 검증.
    func testMigrationPlanHasEightVersionsAndStages() {
        XCTAssertEqual(HorongHorongMigrationPlan.schemas.count, 8)
        XCTAssertEqual(HorongHorongMigrationPlan.stages.count, 7)
        XCTAssertEqual(HorongHorongSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(HorongHorongSchemaV2.versionIdentifier, Schema.Version(2, 0, 0))
        XCTAssertEqual(HorongHorongSchemaV3.versionIdentifier, Schema.Version(3, 0, 0))
        XCTAssertEqual(HorongHorongSchemaV4.versionIdentifier, Schema.Version(4, 0, 0))
        XCTAssertEqual(HorongHorongSchemaV5.versionIdentifier, Schema.Version(5, 0, 0))
        XCTAssertEqual(HorongHorongSchemaV6.versionIdentifier, Schema.Version(6, 0, 0))
        XCTAssertEqual(HorongHorongSchemaV7.versionIdentifier, Schema.Version(7, 0, 0))
        XCTAssertEqual(HorongHorongSchemaV8.versionIdentifier, Schema.Version(8, 0, 0))
    }

    /// 앱이 실제로 여는 스키마는 최신 버전이어야 한다.
    /// 여기가 어긋나면 새 필드가 저장되지 않는데도 빌드는 통과한다.
    func testAppSchemaPointsAtLatestVersion() {
        let names = Set(HorongHorongModelSchema.make().entities.map(\.name))
        XCTAssertEqual(names, Set(HorongHorongSchemaV8.models.map { String(describing: $0) }))
    }

    /// **옛 버전은 얼려 둔 모양을 가리켜야 한다.**
    ///
    /// V1~V3 이 살아 있는 타입을 참조하면 그 타입에 필드를 더하는 순간 선언된 모든 버전의
    /// 모양이 함께 바뀌어, 디스크의 저장소가 어느 버전과도 맞지 않게 된다
    /// (`Cannot use staged migration with an unknown model version`).
    /// 이 테스트가 그 회귀를 막는다 — 엔티티 이름은 같아야 이어지므로 이름도 함께 확인한다.
    func testOldVersionsUseFrozenAchievementGoalRecord() {
        for models in [HorongHorongSchemaV1.models, HorongHorongSchemaV2.models, HorongHorongSchemaV3.models] {
            XCTAssertTrue(
                models.contains { $0 == LegacyAchievementSchema.AchievementGoalRecord.self },
                "옛 버전이 얼려 둔 사본 대신 살아 있는 타입을 가리키고 있다"
            )
            XCTAssertFalse(models.contains { $0 == AchievementGoalRecord.self })
        }
        XCTAssertTrue(HorongHorongSchemaV4.models.contains { $0 == AchievementGoalRecord.self })
        XCTAssertEqual(String(describing: LegacyAchievementSchema.AchievementGoalRecord.self), "AchievementGoalRecord")
    }

    /// 일기도 같은 규칙을 따른다.
    ///
    /// V5 에서 `Diary` 에 `causeRaw`·`sleepStart`·`sleepEnd` 가 늘었다. V3·V4 가 살아 있는 타입을
    /// 계속 가리키면 네 버전의 모양이 함께 바뀌어 V4 와 V5 의 checksum 이 같아지고,
    /// SwiftData 가 `Duplicate version checksums detected` 로 저장소 열기를 거부한다.
    func testOldVersionsUseFrozenDiary() {
        for models in [HorongHorongSchemaV3.models, HorongHorongSchemaV4.models] {
            XCTAssertTrue(
                models.contains { $0 == LegacyDiarySchema.Diary.self },
                "옛 버전이 얼려 둔 사본 대신 살아 있는 Diary 를 가리키고 있다"
            )
            XCTAssertFalse(models.contains { $0 == Diary.self })
        }
        XCTAssertTrue(HorongHorongSchemaV5.models.contains { $0 == Diary.self })
        XCTAssertEqual(String(describing: LegacyDiarySchema.Diary.self), "Diary")
    }

    /// 참고 자료도 같은 규칙을 따른다.
    ///
    /// V6 에서 `Reference` 에 갈래·제목·주소·색·위젯 상태가 늘었다. V3·V4·V5 가 살아 있는 타입을
    /// 계속 가리키면 네 버전의 모양이 함께 바뀌어 V5 와 V6 의 checksum 이 같아진다.
    func testOldVersionsUseFrozenReference() {
        for models in [HorongHorongSchemaV3.models, HorongHorongSchemaV4.models, HorongHorongSchemaV5.models] {
            XCTAssertTrue(
                models.contains { $0 == LegacyReferenceSchema.Reference.self },
                "옛 버전이 얼려 둔 사본 대신 살아 있는 Reference 를 가리키고 있다"
            )
            XCTAssertFalse(models.contains { $0 == Reference.self })
        }
        // 살아 있는 타입을 가리키는 것은 **가장 최신 버전 하나뿐**이어야 한다.
        XCTAssertTrue(HorongHorongSchemaV6.models.contains { $0 == LegacyReferenceV6Schema.Reference.self })
        XCTAssertTrue(HorongHorongSchemaV7.models.contains { $0 == LegacyReferenceV7Schema.Reference.self })
        for models in [HorongHorongSchemaV6.models, HorongHorongSchemaV7.models] {
            XCTAssertFalse(models.contains { $0 == Reference.self })
        }
        XCTAssertTrue(HorongHorongSchemaV8.models.contains { $0 == Reference.self })
        // 엔티티가 이어지려면 사본들의 타입 이름이 모두 같아야 한다.
        for name in [
            String(describing: LegacyReferenceSchema.Reference.self),
            String(describing: LegacyReferenceV6Schema.Reference.self),
            String(describing: LegacyReferenceV7Schema.Reference.self)
        ] {
            XCTAssertEqual(name, "Reference")
        }
    }

    /// V7 저장소를 V8 로 열어 위젯 창 기하가 살아 있고 앞뒤 상태는 비어 있는지 확인한다.
    func testV7StoreMigratesToV8AndKeepsWidgetGeometry() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("v7-to-v8-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        let v7Schema = Schema(versionedSchema: HorongHorongSchemaV7.self)
        let v7Container = try ModelContainer(
            for: v7Schema,
            configurations: [ModelConfiguration(schema: v7Schema, url: url)]
        )
        let v7Context = ModelContext(v7Container)
        v7Context.insert(LegacyReferenceV7Schema.Reference(
            content: "", kindRaw: "note", title: "쪽지", isWidget: true,
            widgetWidth: 320, widgetHeight: 280, widgetCollapsed: true
        ))
        try v7Context.save()
        withExtendedLifetime(v7Container) {}

        let v8Schema = Schema(versionedSchema: HorongHorongSchemaV8.self)
        let migrated = try ModelContainer(
            for: v8Schema,
            migrationPlan: HorongHorongMigrationPlan.self,
            configurations: [ModelConfiguration(schema: v8Schema, url: url)]
        )
        let rows = try ModelContext(migrated).fetch(FetchDescriptor<Reference>())

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.widgetSize, CGSize(width: 320, height: 280))
        XCTAssertEqual(rows.first?.widgetCollapsed, true)
        XCTAssertNil(rows.first?.widgetBehind, "앞뒤는 아직 정해지지 않았다 — 맨 앞으로 읽힌다")
    }

    /// V6 저장소를 V7 로 열어 기존 위젯 상태가 살아 있고 새 창 기하는 비어 있는지 확인한다.
    func testV6StoreMigratesToV7AndKeepsWidgetState() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("v6-to-v7-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        let v6Schema = Schema(versionedSchema: HorongHorongSchemaV6.self)
        let v6Container = try ModelContainer(
            for: v6Schema,
            configurations: [ModelConfiguration(schema: v6Schema, url: url)]
        )
        let v6Context = ModelContext(v6Container)
        v6Context.insert(LegacyReferenceV6Schema.Reference(
            content: "", kindRaw: "note", title: "깃허브 순서", body: "1. status",
            colorRaw: "blue", isWidget: true, widgetX: 812, widgetY: 344
        ))
        try v6Context.save()
        withExtendedLifetime(v6Container) {}

        let currentSchema = HorongHorongModelSchema.make()
        let migrated = try ModelContainer(
            for: currentSchema,
            migrationPlan: HorongHorongMigrationPlan.self,
            configurations: [ModelConfiguration(schema: currentSchema, url: url)]
        )
        let rows = try ModelContext(migrated).fetch(FetchDescriptor<Reference>())

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.title, "깃허브 순서")
        XCTAssertEqual(rows.first?.isWidget, true)
        XCTAssertEqual(rows.first?.widgetPosition, CGPoint(x: 812, y: 344))
        XCTAssertNil(rows.first?.widgetSize, "크기는 아직 모른다 — 기본 크기로 뜬다")
        XCTAssertNil(rows.first?.widgetCollapsed)
    }

    /// V5 저장소를 **현재 스키마(V7)** 까지 끌어올려 기존 참고 자료가 살아 있는지 확인한다.
    ///
    /// 중간 버전(V6)으로 여는 것이 아니라 끝까지 가는 이유: V6 은 이제 얼려 둔 사본을 가리키므로
    /// 그 컨테이너에는 살아 있는 `Reference` 가 없다. 사용자가 실제로 겪는 경로도 «옛 저장소를
    /// 지금 앱으로 여는 것» 이라 여기가 맞다.
    func testV5StoreMigratesThroughToTheCurrentSchema() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("v5-to-v6-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        let v5Schema = Schema(versionedSchema: HorongHorongSchemaV5.self)
        let v5Container = try ModelContainer(
            for: v5Schema,
            configurations: [ModelConfiguration(schema: v5Schema, url: url)]
        )
        let v5Context = ModelContext(v5Container)
        v5Context.insert(LegacyReferenceSchema.Reference(content: "https://arxiv.org/abs/1"))
        try v5Context.save()
        withExtendedLifetime(v5Container) {}

        let currentSchema = HorongHorongModelSchema.make()
        let migrated = try ModelContainer(
            for: currentSchema,
            migrationPlan: HorongHorongMigrationPlan.self,
            configurations: [ModelConfiguration(schema: currentSchema, url: url)]
        )
        let context = ModelContext(migrated)
        let rows = try context.fetch(FetchDescriptor<Reference>())

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.content, "https://arxiv.org/abs/1", "원본은 그대로 남는다")
        XCTAssertNil(rows.first?.kindRaw, "백필 전에는 비어 있다")
        // 갈래가 저장되기 전에도 화면이 링크와 쪽지를 갈라 볼 수 있어야 한다.
        XCTAssertEqual(rows.first?.kind, .link)

        // 백필을 돌리면 구조가 채워지고 원본은 보존된다.
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        AppDelegate.backfillReferenceStructure(in: context, defaults: defaults)

        let backfilled = try XCTUnwrap(try context.fetch(FetchDescriptor<Reference>()).first)
        XCTAssertEqual(backfilled.kindRaw, "link")
        XCTAssertEqual(backfilled.url, "https://arxiv.org/abs/1")
        XCTAssertEqual(backfilled.content, "https://arxiv.org/abs/1")
        XCTAssertEqual(backfilled.isWidget, false)
    }

    /// V4 저장소를 V5 로 열어 기존 일기가 살아 있고 새 시각 필드는 비어 있는지 확인한다.
    /// 여기가 깨지면 사용자의 일기가 통째로 사라진다.
    func testV4StoreMigratesToV5AndKeepsExistingDiaries() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("v4-to-v5-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        let day = Calendar(identifier: .gregorian).startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let v4Schema = Schema(versionedSchema: HorongHorongSchemaV4.self)
        let v4Container = try ModelContainer(
            for: v4Schema,
            configurations: [ModelConfiguration(schema: v4Schema, url: url)]
        )
        let v4Context = ModelContext(v4Container)
        v4Context.insert(LegacyDiarySchema.Diary(day: day, moodRaw: "행복", sleepHours: 7.5, sleepSourceRaw: "manual", body: "옛 일기"))
        try v4Context.save()

        let v5Schema = Schema(versionedSchema: HorongHorongSchemaV5.self)
        let migrated = try ModelContainer(
            for: v5Schema,
            migrationPlan: HorongHorongMigrationPlan.self,
            configurations: [ModelConfiguration(schema: v5Schema, url: url)]
        )
        let diaries = try ModelContext(migrated).fetch(FetchDescriptor<Diary>())

        XCTAssertEqual(diaries.count, 1)
        XCTAssertEqual(diaries.first?.body, "옛 일기")
        XCTAssertEqual(diaries.first?.sleepHours ?? 0, 7.5, accuracy: 0.001)
        XCTAssertEqual(diaries.first?.mood(.wholeDay), .happy, "슬롯이 없던 옛 기록은 «하루» 칸이 된다")
        XCTAssertNil(diaries.first?.sleepStart, "옛 기록은 시각을 모른다")
        XCTAssertNil(diaries.first?.sleepEnd)
        XCTAssertNil(diaries.first?.cause(.wholeDay))
        XCTAssertTrue(diaries.first?.moodRecords.count == 1, "칸 하나만 채워진다")
    }

    /// V3 저장소를 V4 로 열어 새 필드가 비어 있는 채로 붙는지 확인한다.
    /// 기존 사용자의 목표가 «닫힌» 상태로 되살아나면 이번 주 목록에서 통째로 사라진다.
    func testV3StoreMigratesToV4AndKeepsGoalsOpen() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("v3-to-v4-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        let v3Schema = Schema(versionedSchema: HorongHorongSchemaV3.self)
        let v3Container = try ModelContainer(
            for: v3Schema,
            configurations: [ModelConfiguration(schema: v3Schema, url: url)]
        )
        let v3Context = ModelContext(v3Container)
        let goal = LegacyAchievementSchema.AchievementGoalRecord(title: "이월된 주간 목표")
        v3Context.insert(goal)
        try v3Context.save()

        let v4Schema = Schema(versionedSchema: HorongHorongSchemaV4.self)
        let migrated = try ModelContainer(
            for: v4Schema,
            migrationPlan: HorongHorongMigrationPlan.self,
            configurations: [ModelConfiguration(schema: v4Schema, url: url)]
        )
        let records = try ModelContext(migrated).fetch(FetchDescriptor<AchievementGoalRecord>())

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.title, "이월된 주간 목표")
        XCTAssertNil(records.first?.closedAt)
        XCTAssertNil(records.first?.closedReason)
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
            diary.cause = .work

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
        XCTAssertEqual(migratedDiary.mood(.wholeDay), .good)
        // 예전에는 이관 코드가 `causeRaw` 를 빠뜨려 원인이 조용히 사라졌다.
        XCTAssertEqual(migratedDiary.cause(.wholeDay), .work, "원인도 함께 이관된다")

        // ⑧ 검증: 구 SecondBrainRecord 및 DiaryEntry 테이블은 비워졌는가
        let remainingRecords = try v3Context.fetchCount(FetchDescriptor<SecondBrainRecord>())
        XCTAssertEqual(remainingRecords, 0, "기존 SecondBrainRecord 테이블의 데이터는 이전 완료 후 정리되어야 한다")
        let remainingDiaryEntries = try v3Context.fetchCount(FetchDescriptor<DiaryEntry>())
        XCTAssertEqual(remainingDiaryEntries, 0, "기존 DiaryEntry 테이블의 데이터는 이전 완료 후 정리되어야 한다")
    }
}
