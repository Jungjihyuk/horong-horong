import XCTest
@testable import 호롱호롱

/// 테스트를 재현 가능하게 만들기 위한 결정적 난수 생성기.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

final class CompanionRegistryTests: XCTestCase {
    func testDefaultCompanionIsRegistered() {
        XCTAssertEqual(
            CompanionRegistry.character(for: Constants.defaultCompanionIdentifier).id,
            CompanionCharacter.hororong.id
        )
    }

    func testUnknownIdentifierFallsBackToDefaultCompanion() {
        XCTAssertEqual(
            CompanionRegistry.character(for: "not-a-companion").id,
            CompanionCharacter.hororong.id
        )
    }
}

final class CompanionRoamingRegionTests: XCTestCase {
    private let spriteSize = Constants.companionSpriteSize
    private let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let secondary = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

    func testStorageValueRoundTrips() {
        let rect = CGRect(x: -320.5, y: 120, width: 640, height: 480)
        let restored = CompanionRoamingRegion.rect(
            fromStorageValue: CompanionRoamingRegion.storageValue(for: rect)
        )

        XCTAssertEqual(restored, rect)
    }

    func testMalformedStorageValueIsRejected() {
        XCTAssertNil(CompanionRoamingRegion.rect(fromStorageValue: ""))
        XCTAssertNil(CompanionRoamingRegion.rect(fromStorageValue: "1,2,3"))
        XCTAssertNil(CompanionRoamingRegion.rect(fromStorageValue: "0,0,0,300"))
        XCTAssertNil(CompanionRoamingRegion.rect(fromStorageValue: "a,b,c,d"))
    }

    func testStagePicksScreenWithLargestOverlap() {
        // 두 화면에 걸쳐 그렸어도 더 많이 겹치는 쪽 하나를 무대로 삼는다.
        let region = CGRect(x: 1340, y: 100, width: 600, height: 400)

        XCTAssertEqual(
            CompanionRoamingRegion.stage(
                for: region,
                fallbackPoint: .zero,
                screens: [main, secondary],
                mainScreen: main
            ),
            secondary
        )
    }

    /// 영역을 그렸던 디스플레이를 뽑으면 남아있는 화면으로 떨어져야 한다.
    func testStageFallsBackWhenRegionDisplayIsGone() {
        let region = CGRect(x: 1500, y: 100, width: 400, height: 300)

        XCTAssertEqual(
            CompanionRoamingRegion.stage(
                for: region,
                fallbackPoint: CGPoint(x: 700, y: 400),
                screens: [main],
                mainScreen: main
            ),
            main
        )
    }

    func testStageUsesFallbackPointWhenNoRegionIsSet() {
        XCTAssertEqual(
            CompanionRoamingRegion.stage(
                for: nil,
                fallbackPoint: CGPoint(x: 2000, y: 500),
                screens: [main, secondary],
                mainScreen: main
            ),
            secondary
        )
    }

    func testBoundsWithoutRegionCoverWholeScreenInsetBySprite() {
        let bounds = CompanionRoamingRegion.bounds(region: nil, stage: main, spriteSize: spriteSize)

        XCTAssertEqual(bounds.minX, main.minX)
        XCTAssertEqual(bounds.minY, main.minY)
        XCTAssertEqual(bounds.maxX, main.maxX - spriteSize.width)
        XCTAssertEqual(bounds.maxY, main.maxY - spriteSize.height)
    }

    func testBoundsAreClippedToTheScreen() {
        // 화면 밖으로 삐져나가게 그려도 화면 안으로 잘린다.
        let region = CGRect(x: 1200, y: 700, width: 800, height: 600)
        let bounds = CompanionRoamingRegion.bounds(region: region, stage: main, spriteSize: spriteSize)

        XCTAssertEqual(bounds.minX, 1200)
        XCTAssertEqual(bounds.minY, 700)
        XCTAssertEqual(bounds.maxX, main.maxX - spriteSize.width)
        XCTAssertEqual(bounds.maxY, main.maxY - spriteSize.height)
    }

    func testBoundsCollapseWhenRegionIsSmallerThanSprite() {
        let region = CGRect(x: 300, y: 300, width: 40, height: 40)
        let bounds = CompanionRoamingRegion.bounds(region: region, stage: main, spriteSize: spriteSize)

        XCTAssertEqual(bounds.width, 0)
        XCTAssertEqual(bounds.height, 0)
        XCTAssertEqual(bounds.origin, CGPoint(x: 300, y: 300))
    }

    func testBoundsIgnoreRegionThatDoesNotTouchTheStage() {
        let region = CGRect(x: 5000, y: 5000, width: 200, height: 200)
        let bounds = CompanionRoamingRegion.bounds(region: region, stage: main, spriteSize: spriteSize)

        XCTAssertEqual(bounds.minX, main.minX)
        XCTAssertEqual(bounds.maxY, main.maxY - spriteSize.height)
    }

    func testDescriptionReadsBackTheRegionSize() {
        XCTAssertEqual(CompanionRoamingRegion.description(for: nil), "화면 전체")
        XCTAssertEqual(
            CompanionRoamingRegion.description(for: CGRect(x: 0, y: 0, width: 640, height: 480)),
            "640×480 영역"
        )
    }
}

final class CompanionRoamingEngineTests: XCTestCase {
    private let bounds = CGRect(x: 100, y: 200, width: 600, height: 400)

    func testStartPositionIsClampedIntoBounds() {
        let engine = CompanionRoamingEngine(
            bounds: bounds,
            start: CGPoint(x: -900, y: 9_000)
        )

        XCTAssertEqual(engine.position, CGPoint(x: bounds.minX, y: bounds.maxY))
    }

    func testPositionNeverLeavesBoundsInEitherAxis() {
        var engine = CompanionRoamingEngine(
            bounds: bounds,
            start: CGPoint(x: 400, y: 400),
            speed: 400
        )
        var generator = SeededGenerator(seed: 42)

        for _ in 0..<5_000 {
            engine.advance(by: 0.05, using: &generator)
            XCTAssertGreaterThanOrEqual(engine.position.x, bounds.minX)
            XCTAssertLessThanOrEqual(engine.position.x, bounds.maxX)
            XCTAssertGreaterThanOrEqual(engine.position.y, bounds.minY)
            XCTAssertLessThanOrEqual(engine.position.y, bounds.maxY)
        }
    }

    /// 세로로도 실제로 움직여야 한다 (예전처럼 바닥에 붙어 있으면 안 된다).
    func testCompanionMovesVerticallyAsWellAsHorizontally() {
        var engine = CompanionRoamingEngine(
            bounds: bounds,
            start: CGPoint(x: bounds.midX, y: bounds.midY),
            speed: 200
        )
        var generator = SeededGenerator(seed: 11)

        var seenX: Set<Int> = []
        var seenY: Set<Int> = []
        for _ in 0..<2_000 {
            engine.advance(by: 0.05, using: &generator)
            seenX.insert(Int(engine.position.x))
            seenY.insert(Int(engine.position.y))
        }

        XCTAssertGreaterThan(seenX.count, 1)
        XCTAssertGreaterThan(seenY.count, 1)
    }

    func testFacingFollowsHorizontalDirectionOfTravel() {
        var engine = CompanionRoamingEngine(
            bounds: bounds,
            start: CGPoint(x: bounds.maxX, y: bounds.midY),
            speed: 200
        )
        var generator = SeededGenerator(seed: 5)

        // 오른쪽 끝에서 출발하면 첫 목표는 왼쪽일 수밖에 없다.
        while engine.motion == .resting {
            engine.advance(by: 0.05, using: &generator)
        }

        XCTAssertTrue(engine.facesLeft)
        XCTAssertEqual(engine.animation, .runningLeft)
    }

    func testRestingUsesIdleAnimation() {
        let engine = CompanionRoamingEngine(bounds: bounds, start: .zero)

        XCTAssertEqual(engine.motion, .resting)
        XCTAssertEqual(engine.animation, .idle)
    }

    func testCollapsedBoundsKeepCompanionInPlace() {
        let pinned = CGRect(x: 500, y: 500, width: 0, height: 0)
        var engine = CompanionRoamingEngine(bounds: pinned, start: CGPoint(x: 9, y: 9), speed: 300)
        var generator = SeededGenerator(seed: 3)

        for _ in 0..<200 {
            engine.advance(by: 0.05, using: &generator)
        }

        XCTAssertEqual(engine.position, CGPoint(x: 500, y: 500))
        XCTAssertEqual(engine.motion, .resting)
    }

    func testEngineEventuallyReachesItsTargetAndRests() {
        var engine = CompanionRoamingEngine(
            bounds: bounds,
            start: CGPoint(x: bounds.midX, y: bounds.midY),
            speed: 600
        )
        var generator = SeededGenerator(seed: 99)

        var restedAfterMoving = false
        var hasMoved = false
        for _ in 0..<1_000 {
            engine.advance(by: 0.05, using: &generator)
            if engine.motion == .moving { hasMoved = true }
            if hasMoved, engine.motion == .resting { restedAfterMoving = true; break }
        }

        XCTAssertTrue(restedAfterMoving)
    }
}

final class CompanionBriefingTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int = 9, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: day, hour: hour, minute: minute))!
    }

    func testTodayItemsKeepsTodayStartOrTodayDeadlineOnly() {
        let now = date(29, 10)
        let items = [
            CompanionBriefingItem(title: "오늘 시작", isCompleted: false, startDate: date(29, 8), deadline: nil),
            CompanionBriefingItem(title: "오늘 마감", isCompleted: false, startDate: nil, deadline: date(29, 18)),
            CompanionBriefingItem(title: "내일 마감", isCompleted: false, startDate: nil, deadline: date(30, 18)),
            CompanionBriefingItem(title: "일정 없음", isCompleted: false, startDate: nil, deadline: nil),
        ]

        let todays = CompanionBriefingComposer.todayItems(from: items, now: now, calendar: calendar)

        XCTAssertEqual(todays.map(\.title), ["오늘 마감", "오늘 시작"])
    }

    func testCompletedItemsAreExcluded() {
        let now = date(29, 10)
        let items = [
            CompanionBriefingItem(title: "끝난 일", isCompleted: true, startDate: date(29), deadline: nil),
        ]

        XCTAssertTrue(
            CompanionBriefingComposer.todayItems(from: items, now: now, calendar: calendar).isEmpty
        )
    }

    func testComposeLimitsLinesAndReportsRemainder() {
        let now = date(29, 10)
        let items = (1...5).map { index in
            CompanionBriefingItem(
                title: "할일 \(index)",
                isCompleted: false,
                startDate: date(29),
                deadline: nil
            )
        }

        let briefing = CompanionBriefingComposer.compose(
            items: items,
            now: now,
            calendar: calendar,
            maxLineCount: 3
        )

        XCTAssertEqual(briefing.headline, "오늘 할 일 5개")
        XCTAssertEqual(briefing.lines.count, 4)
        XCTAssertEqual(briefing.lines.last, "… 그리고 2개 더")
    }

    func testComposeReportsEmptyWhenNothingIsScheduledToday() {
        let briefing = CompanionBriefingComposer.compose(
            items: [],
            now: date(29),
            calendar: calendar
        )

        XCTAssertTrue(briefing.isEmpty)
    }

    func testNextFireDateMovesToTomorrowWhenTimeHasPassed() {
        let now = date(29, 10, 0)
        let next = CompanionBriefingSchedule.nextFireDate(
            after: now,
            hour: 9,
            minute: 30,
            calendar: calendar
        )

        XCTAssertEqual(next, date(30, 9, 30))
    }

    func testNextFireDateStaysTodayWhenTimeIsAhead() {
        let now = date(29, 8, 0)
        let next = CompanionBriefingSchedule.nextFireDate(
            after: now,
            hour: 9,
            minute: 30,
            calendar: calendar
        )

        XCTAssertEqual(next, date(29, 9, 30))
    }

    func testShouldDeliverOnlyOncePerDay() {
        let now = date(29, 10, 0)

        XCTAssertTrue(
            CompanionBriefingSchedule.shouldDeliver(
                now: now, hour: 9, minute: 30, lastDeliveredAt: nil, calendar: calendar
            )
        )
        XCTAssertFalse(
            CompanionBriefingSchedule.shouldDeliver(
                now: now, hour: 9, minute: 30, lastDeliveredAt: date(29, 9, 31), calendar: calendar
            )
        )
        XCTAssertTrue(
            CompanionBriefingSchedule.shouldDeliver(
                now: now, hour: 9, minute: 30, lastDeliveredAt: date(28, 9, 31), calendar: calendar
            )
        )
    }

    func testShouldNotDeliverBeforeConfiguredTime() {
        XCTAssertFalse(
            CompanionBriefingSchedule.shouldDeliver(
                now: date(29, 8, 0),
                hour: 9,
                minute: 30,
                lastDeliveredAt: nil,
                calendar: calendar
            )
        )
    }

    func testOutOfRangeBriefingTimeIsNormalized() {
        XCTAssertEqual(CompanionBriefingSchedule.normalizedHour(-3), 0)
        XCTAssertEqual(CompanionBriefingSchedule.normalizedHour(48), 23)
        XCTAssertEqual(CompanionBriefingSchedule.normalizedMinute(-1), 0)
        XCTAssertEqual(CompanionBriefingSchedule.normalizedMinute(120), 59)
    }
}
