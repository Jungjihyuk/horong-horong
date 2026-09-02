import XCTest
import SwiftData
@testable import 호롱호롱

/// `VersionedSchema` 를 도입하면서 **기존 저장소를 못 열게 되는 것**이 유일한 위험이다.
/// 인메모리로는 검증되지 않는다 — 디스크에 남아 있는 옛 저장소를 여는 상황이라야 한다.
@MainActor
final class SchemaVersioningTests: XCTestCase {
    private var storeURL: URL!

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

    /// 실사용 저장소 복사본으로도 확인했다 (2026-09-03, 190건 그대로 읽힘).
    /// 그 검사는 로컬 파일 경로에 의존해 저장소에 남기지 않았다 — 합성 데이터로는
    /// «옛 앱이 실제로 남긴 파일»(나중에 추가된 필드가 NULL 인 행 등)을 재현할 수 없으므로,
    /// 스키마를 손댈 때는 매번 실제 복사본으로 한 번 열어 보는 편이 좋다.
    ///
    /// 아직 옮길 단계가 없다. V2 를 추가할 때 이 기대값도 함께 바꾼다.
    func testMigrationPlanHasSingleVersionAndNoStages() {
        XCTAssertEqual(HorongHorongMigrationPlan.schemas.count, 1)
        XCTAssertTrue(HorongHorongMigrationPlan.stages.isEmpty)
        XCTAssertEqual(HorongHorongSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
    }
}
