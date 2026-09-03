import SwiftData
import XCTest
@testable import 호롱호롱

@MainActor
final class SwiftDataStatsRecordEditorRepositoryTests: XCTestCase {
    private let calendar = Calendar.current

    private func makeContainer() throws -> ModelContainer {
        let schema = HorongHorongModelSchema.make()
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func day(_ offset: Int = 0) -> Date {
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    private func time(_ hour: Int, minute: Int = 0, on day: Date? = nil) -> Date {
        calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: day ?? self.day()
        ) ?? (day ?? self.day())
    }

    func testSnapshotRunsOverlapPredicatesAndReturnsValuesOnly() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(AppUsageSegment(
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            category: "개발",
            startTime: time(9),
            endTime: time(9, minute: 30)
        ))
        let completed = FocusSession(focusMinutes: 25, breakMinutes: 5, category: "집중")
        completed.startedAt = time(10)
        completed.endedAt = time(10, minute: 25)
        completed.completed = true
        context.insert(completed)
        let running = FocusSession(focusMinutes: 25, breakMinutes: 5, category: "제외")
        running.startedAt = time(11)
        context.insert(running)
        try context.save()

        let repository = SwiftDataStatsRecordEditorRepository(context: context, calendar: calendar)
        let snapshot = try repository.snapshot(on: day())

        XCTAssertEqual(snapshot.segments.map(\.category), ["개발"])
        XCTAssertEqual(snapshot.focusSessions.map(\.category), ["집중"])
        XCTAssertEqual(snapshot.focusSessions.first?.durationSeconds, 1_500)
    }

    func testSegmentMutationsKeepDailyRecordInSync() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataStatsRecordEditorRepository(context: context, calendar: calendar)

        try repository.addSegment(StatsSegmentDraft(
            appName: "회의 메모",
            category: "업무",
            start: time(9),
            end: time(9, minute: 20)
        ))
        var snapshot = try repository.snapshot(on: day())
        let segmentID = try XCTUnwrap(snapshot.segments.first?.id)
        XCTAssertEqual(try records(context), ["업무": 1_200])

        try repository.updateSegment(
            id: segmentID,
            draft: StatsSegmentDraft(
                appName: "코드 리뷰",
                category: "개발",
                start: time(10),
                end: time(10, minute: 30)
            )
        )
        snapshot = try repository.snapshot(on: day())
        XCTAssertEqual(snapshot.segments.first?.appName, "코드 리뷰")
        XCTAssertEqual(snapshot.segments.first?.category, "개발")
        XCTAssertEqual(try records(context), ["개발": 1_800])

        try repository.deleteSegment(id: segmentID)
        XCTAssertTrue(try repository.snapshot(on: day()).segments.isEmpty)
        XCTAssertTrue(try records(context).isEmpty)
    }

    func testFocusSessionEditMovesFocusRecordToNewCategory() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let session = FocusSession(focusMinutes: 25, breakMinutes: 5, category: "업무")
        session.startedAt = time(9)
        session.endedAt = time(9, minute: 25)
        session.actualFocusSeconds = 1_500
        session.completed = true
        context.insert(session)
        let oldRecord = AppUsageRecord(
            appName: Constants.focusSessionAppName,
            bundleIdentifier: Constants.focusSessionBundleId(for: "업무"),
            category: "업무",
            date: day()
        )
        oldRecord.durationSeconds = 1_500
        context.insert(oldRecord)
        try context.save()
        let repository = SwiftDataStatsRecordEditorRepository(context: context, calendar: calendar)

        try repository.updateFocusSession(
            id: session.id,
            draft: StatsFocusSessionDraft(
                category: "개발",
                start: time(10),
                end: time(10, minute: 30)
            )
        )

        let snapshot = try repository.snapshot(on: day())
        XCTAssertEqual(snapshot.focusSessions.first?.category, "개발")
        XCTAssertEqual(snapshot.focusSessions.first?.durationSeconds, 1_800)
        XCTAssertEqual(try records(context), ["개발": 1_800])
    }

    func testDeletingFocusSessionRemovesOnlyItsOverlapFromAppSegments() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let session = FocusSession(focusMinutes: 30, breakMinutes: 5, category: "집중")
        session.startedAt = time(10)
        session.endedAt = time(10, minute: 30)
        session.actualFocusSeconds = 1_800
        session.completed = true
        context.insert(session)
        let segment = AppUsageSegment(
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            category: "개발",
            startTime: time(9, minute: 50),
            endTime: time(10, minute: 40)
        )
        context.insert(segment)
        let appRecord = AppUsageRecord(
            appName: segment.appName,
            bundleIdentifier: segment.bundleIdentifier,
            category: segment.category,
            date: day()
        )
        appRecord.durationSeconds = 3_000
        context.insert(appRecord)
        let focusRecord = AppUsageRecord(
            appName: Constants.focusSessionAppName,
            bundleIdentifier: Constants.focusSessionBundleId(for: "집중"),
            category: "집중",
            date: day()
        )
        focusRecord.durationSeconds = 1_800
        context.insert(focusRecord)
        try context.save()
        let repository = SwiftDataStatsRecordEditorRepository(context: context, calendar: calendar)

        try repository.deleteFocusSession(id: session.id)

        let snapshot = try repository.snapshot(on: day())
        XCTAssertTrue(snapshot.focusSessions.isEmpty)
        XCTAssertEqual(snapshot.segments.count, 2)
        XCTAssertEqual(snapshot.segments.map(\.durationSeconds).reduce(0, +), 1_200)
        XCTAssertEqual(try records(context), ["개발": 1_200])
    }

    private func records(_ context: ModelContext) throws -> [String: Int] {
        try context.fetch(FetchDescriptor<AppUsageRecord>()).reduce(into: [:]) {
            $0[$1.category, default: 0] += $1.durationSeconds
        }
    }
}

@MainActor
final class StatsRecordEditorViewModelTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    func testValidSegmentAddMapsDraftAndReloads() {
        let repository = FakeStatsRecordEditorRepository(snapshot: StatsRecordEditorSnapshot(
            segments: [],
            focusSessions: []
        ))
        let viewModel = StatsRecordEditorViewModel(repository: repository)
        viewModel.load(date: date)
        let draft = SegmentDraft(
            appName: "회의 메모",
            category: "업무",
            start: date,
            end: date.addingTimeInterval(600)
        )

        XCTAssertTrue(viewModel.addSegment(draft, date: date))
        XCTAssertEqual(repository.addCount, 1)
        XCTAssertEqual(repository.lastSegmentDraft, StatsSegmentDraft(
            appName: draft.appName,
            category: draft.category,
            start: draft.start,
            end: draft.end
        ))
        XCTAssertEqual(repository.snapshotCount, 2)
    }

    func testRejectsSegmentWhenPomodoroChildTotalWouldOverflow() {
        let session = focusSession(start: 0, end: 1_800)
        let repository = FakeStatsRecordEditorRepository(snapshot: StatsRecordEditorSnapshot(
            segments: [segment(start: 0, end: 1_200)],
            focusSessions: [session]
        ))
        let viewModel = StatsRecordEditorViewModel(repository: repository)
        viewModel.load(date: date)

        let saved = viewModel.addSegment(
            SegmentDraft(
                appName: "추가",
                category: "개발",
                start: date.addingTimeInterval(900),
                end: date.addingTimeInterval(1_800)
            ),
            date: date
        )

        XCTAssertFalse(saved)
        XCTAssertEqual(repository.addCount, 0)
        XCTAssertTrue(viewModel.editError?.contains("넘을 수 없습니다") == true)
    }

    func testRejectsFocusEditThatOverlapsAnotherSession() {
        let first = focusSession(start: 0, end: 1_800)
        let second = focusSession(start: 3_600, end: 5_400)
        let repository = FakeStatsRecordEditorRepository(snapshot: StatsRecordEditorSnapshot(
            segments: [],
            focusSessions: [first, second]
        ))
        let viewModel = StatsRecordEditorViewModel(repository: repository)
        viewModel.load(date: date)

        let saved = viewModel.updateFocusSession(
            id: first.id,
            draft: PomodoroDraft(
                category: "집중",
                start: date.addingTimeInterval(3_000),
                end: date.addingTimeInterval(4_000)
            ),
            date: date
        )

        XCTAssertFalse(saved)
        XCTAssertEqual(repository.focusUpdateCount, 0)
        XCTAssertTrue(viewModel.editError?.contains("시간이 겹칩니다") == true)
    }

    private func segment(start: TimeInterval, end: TimeInterval) -> StatsEditableSegment {
        StatsEditableSegment(
            id: UUID(),
            appName: "Xcode",
            category: "개발",
            start: date.addingTimeInterval(start),
            end: date.addingTimeInterval(end),
            isManual: false,
            isUserModified: false
        )
    }

    private func focusSession(start: TimeInterval, end: TimeInterval) -> StatsEditableFocusSession {
        StatsEditableFocusSession(
            id: UUID(),
            category: "집중",
            start: date.addingTimeInterval(start),
            end: date.addingTimeInterval(end),
            durationSeconds: Int(end - start)
        )
    }
}

@MainActor
private final class FakeStatsRecordEditorRepository: StatsRecordEditorRepository {
    var currentSnapshot: StatsRecordEditorSnapshot
    private(set) var addCount = 0
    private(set) var focusUpdateCount = 0
    private(set) var snapshotCount = 0
    private(set) var lastSegmentDraft: StatsSegmentDraft?

    init(snapshot: StatsRecordEditorSnapshot) {
        currentSnapshot = snapshot
    }

    func snapshot(on date: Date) throws -> StatsRecordEditorSnapshot {
        snapshotCount += 1
        return currentSnapshot
    }

    func addSegment(_ draft: StatsSegmentDraft) throws {
        addCount += 1
        lastSegmentDraft = draft
    }

    func updateSegment(id: UUID, draft: StatsSegmentDraft) throws {}
    func deleteSegment(id: UUID) throws {}

    func updateFocusSession(id: UUID, draft: StatsFocusSessionDraft) throws {
        focusUpdateCount += 1
    }

    func deleteFocusSession(id: UUID) throws {}
}
