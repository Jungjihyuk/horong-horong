import AppKit
import SwiftUI
import XCTest
import SwiftData
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

    func testCenteredSpriteOriginPlacesCompanionAtStageCenter() {
        let stage = CGRect(x: -1_920, y: 24, width: 1_920, height: 1_056)
        let spriteSize = CGSize(width: 96, height: 104)

        let origin = CompanionRoamingRegion.centeredSpriteOrigin(
            stage: stage,
            spriteSize: spriteSize
        )
        let spriteFrame = CGRect(origin: origin, size: spriteSize)

        XCTAssertEqual(spriteFrame.midX, stage.midX, accuracy: 0.001)
        XCTAssertEqual(spriteFrame.midY, stage.midY, accuracy: 0.001)
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

final class CompanionSpriteMetricsTests: XCTestCase {
    /// 캐릭터가 없는 칸은 클릭 영역에서 빠져야 한다.
    func testMaskMarksOnlyDrawnCells() {
        // 8x8 이미지를 4x4 격자로. 왼쪽 위 사분면만 그려져 있다.
        let mask = CompanionSpriteMetrics.mask(width: 8, height: 8, columns: 4, rows: 4) { x, y in
            x < 4 && y < 4
        }

        XCTAssertTrue(mask.isFilled(column: 0, row: 0))
        XCTAssertTrue(mask.isFilled(column: 1, row: 1))
        XCTAssertFalse(mask.isFilled(column: 2, row: 0))
        XCTAssertFalse(mask.isFilled(column: 0, row: 2))
        XCTAssertEqual(mask.filledCellCount, 4)
    }

    /// 실루엣 사이의 빈 공간(예: 몸통과 등불 사이)도 뚫려야 한다.
    func testMaskLeavesHolesInsideTheSilhouette() {
        let mask = CompanionSpriteMetrics.mask(width: 8, height: 8, columns: 4, rows: 4) { x, y in
            !(x >= 2 && x < 4 && y >= 2 && y < 4)
        }

        XCTAssertFalse(mask.isFilled(column: 1, row: 1))
        XCTAssertTrue(mask.isFilled(column: 0, row: 0))
        XCTAssertEqual(mask.filledCellCount, 15)
    }

    /// 전부 투명하면 클릭 영역이 사라지므로 전체를 덮는다.
    func testFullyTransparentImageFallsBackToFullMask() {
        let mask = CompanionSpriteMetrics.mask(width: 8, height: 8, columns: 4, rows: 4) { _, _ in false }

        XCTAssertEqual(mask.filledCellCount, 16)
    }

    func testZeroSizedImageFallsBackToFullMask() {
        let mask = CompanionSpriteMetrics.mask(width: 0, height: 0, columns: 4, rows: 4) { _, _ in true }

        XCTAssertEqual(mask.filledCellCount, 16)
    }

    func testOutOfRangeCellIsNotFilled() {
        let mask = CompanionSpriteMetrics.mask(width: 8, height: 8, columns: 4, rows: 4) { _, _ in true }

        XCTAssertFalse(mask.isFilled(column: -1, row: 0))
        XCTAssertFalse(mask.isFilled(column: 4, row: 0))
        XCTAssertFalse(mask.isFilled(column: 0, row: 9))
    }

    /// 프레임마다 판정 영역이 흔들리지 않도록 애니메이션 전체의 합집합을 쓴다.
    func testUnionCoversEveryFrame() {
        let left = CompanionSpriteMetrics.mask(width: 4, height: 4, columns: 2, rows: 2) { x, _ in x < 2 }
        let bottom = CompanionSpriteMetrics.mask(width: 4, height: 4, columns: 2, rows: 2) { _, y in y >= 2 }

        let union = CompanionSpriteMetrics.union([left, bottom])

        XCTAssertTrue(union.isFilled(column: 0, row: 0))
        XCTAssertTrue(union.isFilled(column: 1, row: 1))
        XCTAssertFalse(union.isFilled(column: 1, row: 0))
    }

    func testUnionOfNothingIsFullMask() {
        let mask = CompanionSpriteMetrics.union([])

        XCTAssertEqual(
            mask.filledCellCount,
            CompanionSpriteMetrics.maskColumns * CompanionSpriteMetrics.maskRows
        )
    }

    /// 격자 크기가 다른 마스크를 합치려 하면 원본을 그대로 둔다.
    func testUnionIgnoresMismatchedGrid() {
        let small = CompanionSpriteMetrics.mask(width: 4, height: 4, columns: 2, rows: 2) { _, _ in true }
        let large = CompanionSpriteMetrics.mask(width: 8, height: 8, columns: 4, rows: 4) { _, _ in true }

        XCTAssertEqual(small.union(large), small)
    }
}

final class CompanionDragTests: XCTestCase {
    private let bounds = CGRect(x: 100, y: 200, width: 600, height: 400)

    func testRepositionMovesCompanionAndStopsIt() {
        var engine = CompanionRoamingEngine(bounds: bounds, start: CGPoint(x: 150, y: 250), speed: 200)
        var generator = SeededGenerator(seed: 1)
        // 먼저 걷게 만든다
        while engine.motion == .resting {
            engine.advance(by: 0.05, using: &generator)
        }

        engine.reposition(to: CGPoint(x: 500, y: 500))

        XCTAssertEqual(engine.position, CGPoint(x: 500, y: 500))
        XCTAssertEqual(engine.motion, .resting)
    }

    /// 활동 영역 밖으로 끌어도 영역 안에 붙잡혀야 한다.
    func testRepositionClampsToBounds() {
        var engine = CompanionRoamingEngine(bounds: bounds, start: CGPoint(x: 200, y: 300))

        engine.reposition(to: CGPoint(x: -9_999, y: 9_999))

        XCTAssertEqual(engine.position, CGPoint(x: bounds.minX, y: bounds.maxY))
    }

    /// 놓자마자 다시 걸어가버리면 배치가 튄다. 잠깐 멈춰 있어야 한다.
    func testCompanionPausesBrieflyAfterBeingDropped() {
        var engine = CompanionRoamingEngine(bounds: bounds, start: CGPoint(x: 200, y: 300), speed: 200)
        var generator = SeededGenerator(seed: 2)

        engine.reposition(to: CGPoint(x: 400, y: 400))
        engine.advance(by: 0.3, using: &generator)

        XCTAssertEqual(engine.position, CGPoint(x: 400, y: 400))
        XCTAssertEqual(engine.motion, .resting)
    }
}

@MainActor
final class CompanionViewLayoutTests: XCTestCase {
    func testMenuReportsItsInteractiveFrame() {
        let state = CompanionPresentationState(character: .hororong)
        state.isMenuVisible = true
        var reportedFrame = CGRect.zero
        let hostingView = NSHostingView(
            rootView: CompanionView(state: state) { reportedFrame = $0 }
        )
        hostingView.sizingOptions = []
        hostingView.frame = CGRect(origin: .zero, size: Constants.companionExpandedOverlaySize)

        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        XCTAssertFalse(reportedFrame.isEmpty)
        XCTAssertEqual(reportedFrame.width, 168, accuracy: 1)
    }
}

final class CompanionOverlayMousePolicyTests: XCTestCase {
    private let spriteRect = CGRect(x: 120, y: 0, width: 96, height: 104)
    private let contentRect = CGRect(x: 84, y: 110, width: 168, height: 210)

    func testVisibleMenuKeepsPanelInteractiveOutsideMeasuredRects() {
        XCTAssertFalse(
            CompanionOverlayMousePolicy.shouldIgnoreMouseEvents(
                at: CGPoint(x: 10, y: 10),
                spriteRect: spriteRect,
                contentRect: contentRect,
                isMenuVisible: true
            )
        )
    }

    func testTransparentAreaPassesClicksThroughWhenMenuIsClosed() {
        XCTAssertTrue(
            CompanionOverlayMousePolicy.shouldIgnoreMouseEvents(
                at: CGPoint(x: 10, y: 10),
                spriteRect: spriteRect,
                contentRect: contentRect,
                isMenuVisible: false
            )
        )
    }

    func testCompanionContentRemainsInteractiveWhenMenuIsClosed() {
        for point in [CGPoint(x: 150, y: 50), CGPoint(x: 100, y: 200)] {
            XCTAssertFalse(
                CompanionOverlayMousePolicy.shouldIgnoreMouseEvents(
                    at: point,
                    spriteRect: spriteRect,
                    contentRect: contentRect,
                    isMenuVisible: false
                )
            )
        }
    }
}

final class CompanionChatComposerTests: XCTestCase {
    func testTaskQuestionsAreDetected() {
        for message in ["오늘 할일 뭐 있어?", "남은 일정 알려줘", "뭐부터 할까", "내 TODO 보여줘"] {
            XCTAssertTrue(CompanionTaskQuestion.matches(message), message)
        }
    }

    func testSmallTalkIsNotTreatedAsATaskQuestion() {
        for message in ["요즘 좀 지치네", "안녕", "날씨 어때?"] {
            XCTAssertFalse(CompanionTaskQuestion.matches(message), message)
        }
    }

    /// 시키는 말에는 오늘 일정 목록을 붙이지 않는다.
    func testSaveRequestsAreNotTreatedAsTaskQuestions() {
        let messages = [
            "내일 수진이랑 데이트 일정 있는데 메모에 추가해줘",
            "내일 일정 등록해 주세요",
            "회의 준비 메모해줘",
        ]
        for message in messages {
            XCTAssertFalse(CompanionTaskQuestion.matches(message), message)
        }
    }

    /// 할일 질문이 아니면 프롬프트를 건드리지 않아 짧은 컨텍스트를 아낀다.
    func testModelInputIsUntouchedWithoutADigest() {
        XCTAssertEqual(
            CompanionChatComposer.modelInput(userMessage: "안녕", taskDigest: nil),
            "안녕"
        )
        XCTAssertEqual(
            CompanionChatComposer.modelInput(userMessage: "안녕", taskDigest: ""),
            "안녕"
        )
    }

    func testDigestIsPrependedToTheModelInput() {
        let input = CompanionChatComposer.modelInput(
            userMessage: "오늘 할일 뭐 있어?",
            taskDigest: "오늘 등록된 할일:\n- 보고서"
        )

        XCTAssertTrue(input.hasPrefix("오늘 등록된 할일:"))
        XCTAssertTrue(input.contains("사용자: 오늘 할일 뭐 있어?"))
        XCTAssertTrue(input.contains("나열하지 말고"))
    }
}

final class CompanionMemoIntentTests: XCTestCase {
    func testStandaloneSaveCommandsTargetPreviousMessage() {
        for message in ["메모해줘", "메모해 줘!", "적어둬", "기록해 주세요."] {
            XCTAssertEqual(
                CompanionMemoIntent.parse(message),
                CompanionMemoIntent(target: .previousMessage),
                message
            )
        }
    }

    func testReferenceSaveCommandsTargetPreviousMessage() {
        for message in ["이거 메모해줘", "방금 답변 적어 둬", "메모해줘: 그 내용"] {
            XCTAssertEqual(
                CompanionMemoIntent.parse(message),
                CompanionMemoIntent(target: .previousMessage),
                message
            )
        }
    }

    func testTrailingSaveCommandKeepsUserTextUnchanged() {
        XCTAssertEqual(
            CompanionMemoIntent.parse("내일 우유 2개 사기! 메모해줘"),
            CompanionMemoIntent(target: .text("내일 우유 2개 사기!"))
        )
    }

    func testLeadingSaveCommandKeepsUserTextUnchanged() {
        XCTAssertEqual(
            CompanionMemoIntent.parse("적어둬: 회의에서 API 이름 다시 정하기."),
            CompanionMemoIntent(target: .text("회의에서 API 이름 다시 정하기."))
        )
    }

    func testSimilarSmallTalkIsNotTreatedAsSaveIntent() {
        for message in ["메모해줘서 고마워", "적어둔 내용 보여줘", "메모는 나중에 할게"] {
            XCTAssertNil(CompanionMemoIntent.parse(message), message)
        }
    }

    /// 지시 뒤에 시각을 덧붙이는 말투가 흔하다. 앞뒤 말을 모두 메모 내용으로 살린다.
    func testSaveCommandInTheMiddleKeepsBothSides() {
        XCTAssertEqual(
            CompanionMemoIntent.parse("내일 수진이랑 데이트 일정 메모로 남겨줘. 14시 30분으로"),
            CompanionMemoIntent(target: .text("내일 수진이랑 데이트 일정 14시 30분으로"))
        )
    }

    /// 대상 + 동사 조합이면 말투가 달라도 저장 지시로 읽는다.
    func testTransferPhrasesAreRecognized() {
        let messages = [
            "내일 수진이랑 데이트 일정 있는데 메모에 추가해줘",
            "회의 준비 메모로 저장해 주세요",
            "장보기 일정에 등록해줘",
        ]
        for message in messages {
            XCTAssertNotNil(CompanionMemoIntent.parse(message), message)
        }
    }
}

final class CompanionMemoScheduleTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    /// 2026-07-31 10:00
    private let now = Date(timeIntervalSince1970: 1_785_492_000)

    private func date(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(
            from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute)
        )!
    }

    func testSingleTimeUsesSameStartAndDeadline() {
        let schedule = CompanionMemoSchedule.parse(
            "내일 수진이랑 데이트 일정 14시 30분으로",
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(schedule.title, "수진이랑 데이트")
        XCTAssertEqual(schedule.startDate, date(8, 1, 14, 30))
        XCTAssertEqual(schedule.deadline, date(8, 1, 14, 30))
    }

    func testRangeSplitsStartAndDeadline() {
        let schedule = CompanionMemoSchedule.parse(
            "오늘 팀 회고 13:30 ~ 14:30",
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(schedule.title, "팀 회고")
        XCTAssertEqual(schedule.startDate, date(7, 31, 13, 30))
        XCTAssertEqual(schedule.deadline, date(7, 31, 14, 30))
    }

    /// 뒤 시각에 오전·오후가 없으면 앞 시각을 따라간다.
    func testSpokenRangeFollowsTheLeadingMeridiem() {
        let schedule = CompanionMemoSchedule.parse(
            "모레 워크숍 오후 2시부터 4시까지",
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(schedule.title, "워크숍")
        XCTAssertEqual(schedule.startDate, date(8, 2, 14))
        XCTAssertEqual(schedule.deadline, date(8, 2, 16))
    }

    func testDurationBecomesDeadline() {
        let schedule = CompanionMemoSchedule.parse(
            "내일 집중 작업 13시 30분에 3시간",
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(schedule.title, "집중 작업")
        XCTAssertEqual(schedule.startDate, date(8, 1, 13, 30))
        XCTAssertEqual(schedule.deadline, date(8, 1, 16, 30))
    }

    func testDateOnlyKeepsTheDayWithoutDeadline() {
        let schedule = CompanionMemoSchedule.parse("모레 우유 사기", now: now, calendar: calendar)

        XCTAssertEqual(schedule.title, "우유 사기")
        XCTAssertEqual(schedule.startDate, date(8, 2, 0))
        XCTAssertNil(schedule.deadline)
    }

    /// 낮에 쓴 메모의 "3시"는 오후로 읽는다.
    func testBareAfternoonHoursShiftWhenWrittenDuringTheDay() {
        let schedule = CompanionMemoSchedule.parse(
            "내일 미팅 3시에",
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(schedule.startDate, date(8, 1, 15))
        XCTAssertEqual(schedule.deadline, date(8, 1, 15))
    }

    /// 저녁·밤에 쓴 메모는 새벽 일정을 말하는 경우가 많아 말한 그대로 둔다.
    func testBareHoursStayLiteralWhenWrittenAtNight() {
        let night = date(7, 31, 20)

        let schedule = CompanionMemoSchedule.parse("내일 미팅 3시에", now: night, calendar: calendar)

        XCTAssertEqual(schedule.startDate, date(8, 1, 3))
    }

    /// 오전·오후를 말했으면 쓴 시각과 상관없이 그 말을 따른다.
    func testSpokenMeridiemWinsOverTheWritingTime() {
        let schedule = CompanionMemoSchedule.parse("내일 새벽 3시에 출발", now: now, calendar: calendar)

        XCTAssertEqual(schedule.startDate, date(8, 1, 3))
    }

    /// 7시부터는 헷갈릴 일이 적어 옮기지 않는다.
    func testHoursOutsideTheAmbiguousRangeAreKept() {
        let schedule = CompanionMemoSchedule.parse("내일 조깅 7시에", now: now, calendar: calendar)

        XCTAssertEqual(schedule.startDate, date(8, 1, 7))
    }

    /// "2시부터 그 다음날 오후 12시까지" 처럼 구간이 하루를 넘어가는 경우.
    func testRangeCanSpanIntoTheNextDay() {
        let schedule = CompanionMemoSchedule.parse(
            "수진이랑 데이트 일정 있는데 2시부터 그 다음날 오후 12시까지",
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(schedule.title, "수진이랑 데이트")
        XCTAssertEqual(schedule.startDate, date(7, 31, 14))
        XCTAssertEqual(schedule.deadline, date(8, 1, 12))
    }

    /// 말한 문장을 그대로 두지 않고 제목처럼 다듬는다.
    func testTitleIsTrimmedIntoANounPhrase() {
        let cases = [
            "수진이랑 데이트 일정 있는데": "수진이랑 데이트",
            "팀 회의 잡혔어": "팀 회의",
            "장 보러 가야 해": "장 보러",
            "운동 하려고": "운동",
        ]
        for (input, expected) in cases {
            let schedule = CompanionMemoSchedule.parse(input, now: now, calendar: calendar)
            XCTAssertEqual(schedule.title, expected, input)
        }
    }

    /// 낱말 일부를 자르면 안 된다. 남는 말이 너무 짧으면 손대지 않는다.
    func testShortWordsAreNotCutApart() {
        for input in ["맛있어", "일정", "회의 있음"] {
            let schedule = CompanionMemoSchedule.parse(input, now: now, calendar: calendar)
            XCTAssertEqual(schedule.title, input == "회의 있음" ? "회의" : input, input)
        }
    }

    func testSummaryReadsBackWhatWasSaved() {
        let single = CompanionMemoSchedule.parse("내일 데이트 14시 30분", now: now, calendar: calendar)
        let range = CompanionMemoSchedule.parse("오늘 회고 13:30 ~ 14:30", now: now, calendar: calendar)
        let dateOnly = CompanionMemoSchedule.parse("모레 우유 사기", now: now, calendar: calendar)

        XCTAssertEqual(single.summary(now: now, calendar: calendar), "내일 14:30")
        XCTAssertEqual(range.summary(now: now, calendar: calendar), "오늘 13:30 ~ 14:30")
        XCTAssertEqual(dateOnly.summary(now: now, calendar: calendar), "모레")
    }

    func testPlainMemoKeepsTextAndHasNoDates() {
        let schedule = CompanionMemoSchedule.parse("우유 2개 사기", now: now, calendar: calendar)

        XCTAssertEqual(schedule.title, "우유 2개 사기")
        XCTAssertNil(schedule.startDate)
        XCTAssertNil(schedule.deadline)
    }
}

final class CompanionMemoStoreTests: XCTestCase {
    @MainActor
    func testSaveKeepsOriginalTextAndSelectedOptions() throws {
        let schema = Schema([Memo.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let store = CompanionMemoStore()
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let original = "첫 줄 그대로\n둘째 줄도 **그대로**"

        _ = try store.save(
            CompanionMemoSaveRequest(
                messageID: UUID(),
                content: original,
                icon: "💡",
                isTodayTask: true
            ),
            in: context,
            now: now
        )

        let memo = try XCTUnwrap(context.fetch(FetchDescriptor<Memo>()).first)
        XCTAssertEqual(memo.content, original)
        XCTAssertEqual(memo.icon, "💡")
        XCTAssertEqual(memo.startDate, now)
    }

    @MainActor
    func testRegularMemoDoesNotReceiveStartDate() throws {
        let schema = Schema([Memo.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let store = CompanionMemoStore()

        _ = try store.save(
            CompanionMemoSaveRequest(
                messageID: UUID(),
                content: "일반 메모",
                icon: MemoIcon.defaultIcon,
                isTodayTask: false
            ),
            in: context
        )

        let memo = try XCTUnwrap(context.fetch(FetchDescriptor<Memo>()).first)
        XCTAssertNil(memo.startDate)
    }

    /// 말로 정해준 때는 메모의 시작·마감으로 그대로 들어간다.
    @MainActor
    func testSpokenScheduleIsStoredOnTheMemo() throws {
        let schema = Schema([Memo.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let store = CompanionMemoStore()
        let start = Date(timeIntervalSince1970: 1_785_578_400)
        let end = start.addingTimeInterval(3600)

        _ = try store.save(
            CompanionMemoSaveRequest(
                messageID: UUID(),
                content: "수진이랑 데이트 일정",
                icon: MemoIcon.defaultIcon,
                isTodayTask: false,
                startDate: start,
                deadline: end
            ),
            in: context
        )

        let memo = try XCTUnwrap(context.fetch(FetchDescriptor<Memo>()).first)
        XCTAssertEqual(memo.startDate, start)
        XCTAssertEqual(memo.deadline, end)
    }

    @MainActor
    func testSameMessageIsSavedOnlyOnce() throws {
        let schema = Schema([Memo.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let store = CompanionMemoStore()
        let messageID = UUID()
        let request = CompanionMemoSaveRequest(
            messageID: messageID,
            content: "한 번만 저장",
            icon: MemoIcon.defaultIcon,
            isTodayTask: false
        )

        let first = try store.save(request, in: context)
        let second = try store.save(request, in: context)

        guard case .saved(let firstID) = first else {
            return XCTFail("첫 저장은 saved 여야 합니다.")
        }
        XCTAssertEqual(second, .duplicate(firstID))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Memo>()), 1)
    }
}

final class CompanionReplyFormatterTests: XCTestCase {
    func testBoldMarkersAreRemoved() {
        XCTAssertEqual(
            CompanionReplyFormatter.clean("오늘은 **보고서 작성**이에요."),
            "오늘은 보고서 작성이에요."
        )
    }

    func testBulletListIsFlattenedIntoASentence() {
        let cleaned = CompanionReplyFormatter.clean("오늘 할일이에요.\n- 보고서\n- 운동")

        XCTAssertEqual(cleaned, "오늘 할일이에요.\n보고서\n운동")
    }

    func testNumberedListIsFlattened() {
        XCTAssertEqual(
            CompanionReplyFormatter.clean("1. 보고서\n2. 운동"),
            "보고서\n운동"
        )
    }

    /// 숫자로 시작하는 평범한 문장을 목록으로 오해하면 안 된다.
    func testSentenceStartingWithANumberIsKept() {
        XCTAssertEqual(
            CompanionReplyFormatter.clean("3시간 정도 걸려요."),
            "3시간 정도 걸려요."
        )
    }

    func testBlankLinesAreCollapsed() {
        XCTAssertEqual(
            CompanionReplyFormatter.clean("안녕하세요.\n\n\n오늘도 힘내요."),
            "안녕하세요.\n오늘도 힘내요."
        )
    }
}

final class CompanionBriefingSummaryTests: XCTestCase {
    private func entry(_ title: String, completed: Bool) -> CompanionScheduleEntry {
        CompanionScheduleEntry(time: nil, title: title, isCompleted: completed)
    }

    func testHeadlineCountsRemainingItems() {
        let headline = CompanionBriefingSummary.headline(for: [
            entry("a", completed: true), entry("b", completed: false), entry("c", completed: false),
        ])

        XCTAssertEqual(headline, "오늘 할 일 3개 · 2개 남음")
    }

    func testHeadlineSaysAllDoneWhenNothingRemains() {
        XCTAssertEqual(
            CompanionBriefingSummary.headline(for: [entry("a", completed: true)]),
            "오늘 할 일 1개 · 모두 완료"
        )
    }

    func testHeadlineForEmptyDay() {
        XCTAssertEqual(CompanionBriefingSummary.headline(for: []), "오늘 일정 없음")
    }
}

final class CompanionScheduleBuilderTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int = 9, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: day, hour: hour, minute: minute))!
    }

    func testEntriesAreSortedByTime() {
        let items = [
            CompanionBriefingItem(title: "저녁", isCompleted: false, startDate: nil, deadline: date(29, 19)),
            CompanionBriefingItem(title: "아침", isCompleted: false, startDate: nil, deadline: date(29, 10)),
        ]

        let entries = CompanionScheduleBuilder.entries(from: items, now: date(29, 9), calendar: calendar)

        XCTAssertEqual(entries.map(\.title), ["아침", "저녁"])
    }

    /// 시각이 없는 항목은 뒤로 보낸다.
    func testUntimedEntriesGoLast() {
        let items = [
            CompanionBriefingItem(title: "언젠가", isCompleted: false, startDate: date(29), deadline: nil),
            CompanionBriefingItem(title: "6시", isCompleted: false, startDate: nil, deadline: date(29, 18)),
        ]

        let entries = CompanionScheduleBuilder.entries(from: items, now: date(29, 9), calendar: calendar)

        XCTAssertEqual(entries.first?.title, "6시")
        XCTAssertNil(entries.last?.time)
    }

    /// 브리핑과 달리 완료된 항목도 상태를 유지한 채 보여준다.
    func testCompletedEntriesAreKeptWithTheirState() {
        let items = [
            CompanionBriefingItem(title: "운동", isCompleted: true, startDate: date(29), deadline: nil),
        ]

        let entries = CompanionScheduleBuilder.entries(from: items, now: date(29, 9), calendar: calendar)

        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries[0].isCompleted)
    }

    /// 메모 본문이 여러 줄이어도 타임라인 행은 한 줄이어야 간격이 균등하다.
    func testMultilineTitlesAreCollapsedToTheirFirstLine() {
        let items = [
            CompanionBriefingItem(
                title: "데일리 로그\n",
                isCompleted: false,
                startDate: nil,
                deadline: date(29, 9, 30)
            ),
            CompanionBriefingItem(
                title: "  회고 쓰기  \n1. 무엇을 배웠나\n2. 다음 주 계획",
                isCompleted: false,
                startDate: nil,
                deadline: date(29, 10)
            ),
        ]

        let entries = CompanionScheduleBuilder.entries(from: items, now: date(29, 9), calendar: calendar)

        XCTAssertEqual(entries.map(\.title), ["데일리 로그", "회고 쓰기"])
    }

    func testItemsFromOtherDaysAreExcluded() {
        let items = [
            CompanionBriefingItem(title: "내일", isCompleted: false, startDate: nil, deadline: date(30, 10)),
        ]

        XCTAssertTrue(
            CompanionScheduleBuilder.entries(from: items, now: date(29, 9), calendar: calendar).isEmpty
        )
    }
}

final class CompanionMoodTests: XCTestCase {
    /// 감정마다 보여줄 동작이 반드시 있어야 한다.
    func testEveryMoodMapsToAnAnimation() {
        for mood in CompanionMood.allCases {
            XCTAssertFalse(mood.animation.directoryName.isEmpty, "\(mood)")
        }
    }

    func testMoodAnimationsMatchTheAgreedMapping() {
        XCTAssertEqual(CompanionMood.cheerful.animation, .jumping)
        XCTAssertEqual(CompanionMood.playful.animation, .jumping)
        XCTAssertEqual(CompanionMood.calm.animation, .idle)
        XCTAssertEqual(CompanionMood.encouraging.animation, .waving)
        XCTAssertEqual(CompanionMood.concerned.animation, .failed)
    }

    /// 모델이 대소문자를 섞어 보내도 받아들인다.
    func testMoodParsingIsCaseInsensitive() {
        XCTAssertEqual(CompanionMood(modelValue: "CHEERFUL"), .cheerful)
        XCTAssertEqual(CompanionMood(modelValue: "Concerned"), .concerned)
    }

    /// 정의에 없는 값은 nil 로 떨어져 호출부가 기본 동작을 고를 수 있어야 한다.
    func testUnknownMoodIsRejected() {
        XCTAssertNil(CompanionMood(modelValue: "furious"))
        XCTAssertNil(CompanionMood(modelValue: ""))
    }

    func testEmptyReplyHasNoMood() {
        XCTAssertEqual(CompanionChatReply.empty.text, "")
        XCTAssertNil(CompanionChatReply.empty.mood)
    }
}

final class CompanionOnboardingScriptTests: XCTestCase {
    private let sample = """
    # 대본

    ## 이 파일을 고치는 법
    안내문이라 id 가 없다.
    > 이 줄은 대사가 아니다.

    ## 시나리오 1. 집중하기
    <!-- id: focus -->

    ### 1) 타이머를 연다
    <!-- screen: popover.timer -->
    > 타이머 탭이에요.
    > 여기서 시작해요.

    ### 2) 돌아본다
    > 끝나면 돌아봐요.

    ## 시나리오 2. 통계 보기
    <!-- id: stats -->

    ### 1) 통계 탭
    <!-- screen: popover.stats -->
    > 통계 탭이에요.
    """

    /// id 가 없는 안내문 문단은 시나리오로 잡히면 안 된다.
    func testSectionsWithoutIDAreNotScenarios() {
        let scenarios = CompanionOnboardingScript.parse(sample)

        XCTAssertEqual(scenarios.map(\.id), ["focus", "stats"])
    }

    func testStepsKeepOrderAndScreen() {
        let scenarios = CompanionOnboardingScript.parse(sample)
        let steps = scenarios[0].steps

        XCTAssertEqual(steps.count, 2)
        XCTAssertEqual(steps[0].screen, .popoverTimer)
        XCTAssertNil(steps[1].screen)
    }

    /// 여러 줄로 쓴 대사는 한 문장으로 합쳐진다.
    func testMultiLineQuoteBecomesOneLine() {
        let steps = CompanionOnboardingScript.parse(sample)[0].steps

        XCTAssertEqual(steps[0].line, "타이머 탭이에요. 여기서 시작해요.")
    }

    func testStepWithoutLineIsSkipped() {
        let scenarios = CompanionOnboardingScript.parse("""
        ## 시나리오
        <!-- id: x -->

        ### 대사 없는 단계
        <!-- screen: popover.memo -->

        ### 대사 있는 단계
        > 안녕하세요.
        """)

        XCTAssertEqual(scenarios.first?.steps.count, 1)
        XCTAssertEqual(scenarios.first?.steps.first?.title, "대사 있는 단계")
    }

    func testHighlightIsParsed() {
        let steps = CompanionOnboardingScript.parse("""
        ## 시나리오
        <!-- id: x -->

        ### 단계
        <!-- screen: popover.timer -->
        <!-- highlight: timer.startFocus -->
        > 눌러보세요.
        """).first?.steps

        XCTAssertEqual(steps?.first?.highlight, "timer.startFocus")
    }

    func testActionIsParsed() {
        let steps = CompanionOnboardingScript.parse("""
        ## 시나리오
        <!-- id: x -->

        ### 단계
        <!-- screen: popover.timer -->
        <!-- action: timer.openTaskPicker -->
        > 펼쳐볼게요.
        """).first?.steps

        XCTAssertEqual(steps?.first?.action, "timer.openTaskPicker")
    }

    func testStepWithoutActionHasNone() {
        let steps = CompanionOnboardingScript.parse("""
        ## 시나리오
        <!-- id: x -->

        ### 단계
        > 안녕하세요.
        """).first?.steps

        XCTAssertNil(steps?.first?.action)
    }

    func testStepWithoutHighlightHasNone() {
        let steps = CompanionOnboardingScript.parse("""
        ## 시나리오
        <!-- id: x -->

        ### 단계
        > 눌러보세요.
        """).first?.steps

        XCTAssertNil(steps?.first?.highlight)
    }

    func testUnknownScreenIsIgnored() {
        let steps = CompanionOnboardingScript.parse("""
        ## 시나리오
        <!-- id: x -->

        ### 단계
        <!-- screen: popover.nowhere -->
        > 안녕하세요.
        """).first?.steps

        XCTAssertNil(steps?.first?.screen)
    }

    func testSettingsMemoScreenIsParsed() {
        let steps = CompanionOnboardingScript.parse("""
        ## 시나리오
        <!-- id: x -->

        ### 단계
        <!-- screen: settings.memo -->
        > 단축키를 확인하세요.
        """).first?.steps

        XCTAssertEqual(steps?.first?.screen, .settingsMemo)
    }

    func testBundledGuideMatchesInteractiveOnboardingFlow() throws {
        let steps = CompanionOnboardingScript.loadFromBundle().flatMap(\.steps)

        func step(endingWith suffix: String) throws -> CompanionOnboardingStep {
            try XCTUnwrap(steps.first { $0.title.hasSuffix(suffix) })
        }

        XCTAssertEqual(steps.count, 18)

        let summon = try step(endingWith: "부르는 법")
        XCTAssertEqual(summon.screen, .settingsCompanion)
        XCTAssertEqual(summon.highlight, "settings.companionBasics")

        let newMemo = try step(endingWith: "새 메모를 만든다")
        XCTAssertEqual(newMemo.screen, .popoverMemo)
        XCTAssertEqual(newMemo.highlight, "memo.new")

        let quickMemo = try step(endingWith: "더 빠르게 적는 법")
        XCTAssertEqual(quickMemo.screen, .settingsMemo)
        XCTAssertEqual(quickMemo.highlight, "settings.memoShortcut")

        let taskPickerIndex = try XCTUnwrap(
            steps.firstIndex { $0.title.hasSuffix("등록한 할 일을 고른다") }
        )
        let memoTabIndex = try XCTUnwrap(
            steps.firstIndex { $0.title.hasSuffix("메모 탭을 연다") }
        )
        XCTAssertLessThan(taskPickerIndex, memoTabIndex)

        let statsDetail = try step(endingWith: "상세 보기로 들어간다")
        XCTAssertEqual(statsDetail.screen, .windowStats)
        XCTAssertEqual(statsDetail.action, "stats.showPeriod")

        let finalStep = try step(endingWith: "아무 때나 다시 본다")
        XCTAssertEqual(finalStep.highlight, "companion.menu.schedule")
    }

    func testEmptyDocumentProducesNoScenarios() {
        XCTAssertTrue(CompanionOnboardingScript.parse("").isEmpty)
    }
}

final class CompanionMarkdownTests: XCTestCase {
    /// 대본의 별표가 화면에 그대로 보이면 안 된다.
    func testAsterisksAreNotShown() {
        let styled = CompanionMarkdown.styled("**집중 시작**을 누르세요.")

        XCTAssertEqual(String(styled.characters), "집중 시작을 누르세요.")
    }

    func testEmphasisGetsTheAccentColor() {
        let styled = CompanionMarkdown.styled("**집중 시작**을 누르세요.")
        let tinted = styled.runs.contains { $0.foregroundColor == CompanionHighlightStyle.tint }

        XCTAssertTrue(tinted)
    }

    func testPlainTextIsUnchanged() {
        XCTAssertEqual(
            String(CompanionMarkdown.styled("그냥 문장이에요.").characters),
            "그냥 문장이에요."
        )
    }
}

final class CompanionOnboardingTriggerTests: XCTestCase {
    /// 처음 설치해 기록이 전혀 없을 때만 저절로 시작한다.
    func testStartsOnlyWhenUnseenAndEmpty() {
        XCTAssertTrue(
            CompanionOnboardingTrigger.shouldStartAutomatically(
                hasSeenOnboarding: false, memoCount: 0, focusSessionCount: 0
            )
        )
    }

    func testDoesNotStartWhenAlreadySeen() {
        XCTAssertFalse(
            CompanionOnboardingTrigger.shouldStartAutomatically(
                hasSeenOnboarding: true, memoCount: 0, focusSessionCount: 0
            )
        )
    }

    /// 기록이 있으면 기존 사용자이므로 방해하지 않는다.
    func testDoesNotStartWhenAnyDataExists() {
        XCTAssertFalse(
            CompanionOnboardingTrigger.shouldStartAutomatically(
                hasSeenOnboarding: false, memoCount: 1, focusSessionCount: 0
            )
        )
        XCTAssertFalse(
            CompanionOnboardingTrigger.shouldStartAutomatically(
                hasSeenOnboarding: false, memoCount: 0, focusSessionCount: 1
            )
        )
    }
}

final class CompanionOnboardingDemoStoreTests: XCTestCase {
    @MainActor
    func testDemoDataIsUsedOnlyWhenUserContentIsEmpty() {
        XCTAssertTrue(
            CompanionOnboardingDemoStore.shouldUseDemoData(
                memoCount: 0,
                focusSessionCount: 0,
                achievementGoalCount: 0
            )
        )
        XCTAssertFalse(
            CompanionOnboardingDemoStore.shouldUseDemoData(
                memoCount: 1,
                focusSessionCount: 0,
                achievementGoalCount: 0
            )
        )
        XCTAssertFalse(
            CompanionOnboardingDemoStore.shouldUseDemoData(
                memoCount: 0,
                focusSessionCount: 1,
                achievementGoalCount: 0
            )
        )
        XCTAssertFalse(
            CompanionOnboardingDemoStore.shouldUseDemoData(
                memoCount: 0,
                focusSessionCount: 0,
                achievementGoalCount: 1
            )
        )
    }

    @MainActor
    func testDemoDataLivesInAReplaceableInMemoryContainer() throws {
        let store = CompanionOnboardingDemoStore()
        let now = Date(timeIntervalSince1970: 1_786_000_000)

        XCTAssertTrue(
            store.startIfNeeded(
                memoCount: 0,
                focusSessionCount: 0,
                achievementGoalCount: 0,
                now: now
            )
        )

        let context = try XCTUnwrap(store.modelContainer).mainContext
        let memos = try context.fetch(FetchDescriptor<Memo>())
        let goalRecords = try context.fetch(FetchDescriptor<AchievementGoalRecord>())
        let sessions = try context.fetch(FetchDescriptor<FocusSession>())
        let reflections = try context.fetch(FetchDescriptor<PomodoroReflection>())
        let segments = try context.fetch(FetchDescriptor<AppUsageSegment>())
        XCTAssertEqual(memos.count, 6)
        XCTAssertEqual(sessions.count, 33)
        XCTAssertEqual(reflections.count, 32)
        XCTAssertEqual(goalRecords.count, 2)
        XCTAssertEqual(goalRecords.first?.linkedMemoIDs.count, 3)
        XCTAssertEqual(memos.filter(\.isCompletedValue).count, 1)
        XCTAssertGreaterThan(segments.count, 60)
        XCTAssertEqual(
            PomodoroTaskCandidateBuilder.candidates(
                memos: memos,
                goalRecords: goalRecords,
                now: now
            ).count,
            5
        )

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        let todaySessions = sessions.filter { $0.startedAt >= today && $0.startedAt < tomorrow }
        let todaySegments = segments
            .filter { $0.startTime < tomorrow && $0.endTime > today }
            .sorted { $0.startTime < $1.startTime }
        let breakdowns = PomodoroComparisonPeriodBuilder.build(
            sessions: todaySessions,
            segments: todaySegments,
            periodStart: today,
            periodEnd: tomorrow
        )
        let todaySessionIDs = Set(todaySessions.map(\.id))
        let todayReflections = reflections.filter { todaySessionIDs.contains($0.focusSessionID) }
        XCTAssertEqual(breakdowns.count, 7)
        XCTAssertEqual(todayReflections.count, 7)
        XCTAssertEqual(Set(todayReflections.map(\.focusExperienceRawValue)).count, 4)
        XCTAssertTrue(breakdowns.allSatisfy { $0.observation.recordedSeconds > 0 })
        XCTAssertGreaterThan(Set(breakdowns.map(\.observation.appSwitchCount)).count, 2)

        store.stop()
        XCTAssertFalse(store.isActive)
        XCTAssertNil(store.modelContainer)
    }

    @MainActor
    func testExistingContentDoesNotCreateDemoContainer() {
        let store = CompanionOnboardingDemoStore()

        XCTAssertFalse(
            store.startIfNeeded(
                memoCount: 1,
                focusSessionCount: 0,
                achievementGoalCount: 0
            )
        )
        XCTAssertNil(store.modelContainer)
    }
}

final class CompanionAppFactsTests: XCTestCase {
    /// 나열형 사실은 코드에서 만들어야 기능이 바뀌어도 답이 틀리지 않는다.
    func testThemeFactMatchesTheActualThemes() {
        let line = CompanionAppFacts.matching("무슨 테마가 있는데?")

        XCTAssertNotNil(line)
        for theme in Constants.PopoverTheme.allCases {
            XCTAssertTrue(line!.contains(theme.label), theme.label)
        }
    }

    func testTabFactListsEveryPopoverTab() {
        let line = CompanionAppFacts.matching("무슨 탭이 있어?")

        XCTAssertNotNil(line)
        for tab in PopoverTab.allCases {
            XCTAssertTrue(line!.contains(tab.rawValue), tab.rawValue)
        }
    }

    /// 경로가 있으면 근거에 함께 실려 모델이 그대로 말하게 된다.
    func testPathIsIncludedInEvidence() {
        let line = CompanionAppFacts.matching("테마 어떻게 바꿔?")

        XCTAssertNotNil(line)
        XCTAssertTrue(line!.contains("설정 → 외관 → 테마"))
    }

    func testDestinationIsResolvedForTheme() {
        let destination = CompanionAppFacts.destination(for: "테마 어떻게 바꿔?")

        XCTAssertEqual(destination?.tab, .appearance)
        XCTAssertEqual(destination?.highlight, "settings.theme")
    }

    func testNoDestinationForQuestionsWithoutOne() {
        XCTAssertNil(CompanionAppFacts.destination(for: "메모 아이콘 뭐 있어?"))
    }

    func testUnrelatedQuestionHasNoFacts() {
        XCTAssertNil(CompanionAppFacts.matching("오늘 기분이 어때?"))
    }

    /// 여러 주제가 걸리면 모두 넣는다.
    func testMultipleFactsAreJoined() {
        let line = CompanionAppFacts.matching("테마랑 탭 알려줘")

        XCTAssertNotNil(line)
        XCTAssertTrue(line!.contains("테마"))
        XCTAssertTrue(line!.contains("탭"))
    }

    func testMatchingIsCaseInsensitive() {
        XCTAssertNotNil(CompanionAppFacts.matching("AGENT 뭐 쓸 수 있어?"))
    }
}

final class CompanionGuideTests: XCTestCase {
    private let sample = """
    # 사용법

    ## 4. 타이머 탭

    기본 프리셋은 포모도로입니다.

    ## 5. 메모 탭

    퀵 메모 단축키는 ⌘⇧N 입니다.
    """

    func testSectionsAreSplitByHeading() {
        let sections = CompanionGuide.sections(from: sample)

        XCTAssertEqual(sections.map(\.title), ["4. 타이머 탭", "5. 메모 탭"])
    }

    func testEmptySectionIsDropped() {
        let sections = CompanionGuide.sections(from: "## 빈 섹션\n\n## 내용 있음\n본문")

        XCTAssertEqual(sections.map(\.title), ["내용 있음"])
    }

    func testBestMatchPrefersTitleHit() {
        let sections = CompanionGuide.sections(from: sample)
        let match = CompanionGuide.bestMatch(for: "메모 탭이 뭐야?", in: sections)

        XCTAssertEqual(match?.title, "5. 메모 탭")
    }

    /// 조사가 붙어도 걸려야 한다.
    func testKoreanParticlesAreStripped() {
        let tokens = CompanionGuide.searchTokens(in: "테마를 바꾸려면?")

        XCTAssertTrue(tokens.contains("테마"))
    }

    /// 근거가 없으면 아무것도 주지 않아 모델이 지어내지 않게 한다.
    func testNoMatchReturnsNil() {
        let sections = CompanionGuide.sections(from: sample)

        XCTAssertNil(CompanionGuide.bestMatch(for: "김치찌개 끓이는 법", in: sections))
    }

    func testLongSectionIsClipped() {
        let clipped = CompanionGuide.clipped(String(repeating: "가", count: 900), limit: 100)

        XCTAssertTrue(clipped.count < 200)
        XCTAssertTrue(clipped.hasSuffix("(이하 생략)"))
    }

    func testUsageQuestionsAreDetected() {
        for message in ["테마 어떻게 바꿔?", "단축키 뭐가 있어?", "통계 어디서 봐?"] {
            XCTAssertTrue(CompanionGuideQuestion.matches(message), message)
        }
    }

    func testSmallTalkIsNotAUsageQuestion() {
        XCTAssertFalse(CompanionGuideQuestion.matches("오늘 날씨 좋네"))
    }
}

final class CompanionEvidencePromptTests: XCTestCase {
    /// 근거를 넣으면 "이 안에서만 답하라" 는 지시가 함께 들어가야 한다.
    func testEvidencePromptForbidsInvention() {
        let input = CompanionChatComposer.modelInput(
            userMessage: "무슨 테마가 있어?",
            appFacts: "팝오버 테마: 따뜻한 등불"
        )

        XCTAssertTrue(input.contains("따뜻한 등불"))
        XCTAssertTrue(input.contains("절대 말하지 마"))
    }

    func testFactsAndGuideAreBothIncluded() {
        let input = CompanionChatComposer.modelInput(
            userMessage: "테마 바꾸는 법",
            appFacts: "팝오버 테마: 게임 픽셀",
            guideSection: "7. 설정 창\n외관에서 바꿉니다."
        )

        XCTAssertTrue(input.contains("게임 픽셀"))
        XCTAssertTrue(input.contains("외관에서 바꿉니다"))
    }

    /// 근거가 없으면 사용자 말을 그대로 보낸다.
    func testNoEvidenceLeavesMessageUntouched() {
        XCTAssertEqual(
            CompanionChatComposer.modelInput(userMessage: "안녕"),
            "안녕"
        )
    }

    /// 할일 질문은 기존 경로를 그대로 쓴다.
    func testTaskDigestTakesPrecedence() {
        let input = CompanionChatComposer.modelInput(
            userMessage: "오늘 할일 뭐야?",
            taskDigest: "오늘 등록된 할일: 없음",
            appFacts: "팝오버 테마: 게임 픽셀"
        )

        XCTAssertTrue(input.contains("오늘 등록된 할일"))
        XCTAssertFalse(input.contains("게임 픽셀"))
    }
}

final class CompanionSettingsIndexTests: XCTestCase {
    /// 주제마다 규칙을 손으로 쓰지 않고, 앱이 이미 가진 검색 색인으로 찾아야 한다.
    func testFindsPageFromRowKeyword() {
        XCTAssertEqual(
            CompanionSettingsIndex.bestMatch(for: "미리알림 연동할 수 있어?")?.tab,
            .memo
        )
    }

    func testFindsPageFromPageName() {
        XCTAssertEqual(
            CompanionSettingsIndex.bestMatch(for: "단축키 어디서 바꿔?")?.tab,
            .hotkey
        )
    }

    func testUnrelatedQuestionFindsNothing() {
        XCTAssertNil(CompanionSettingsIndex.bestMatch(for: "김치찌개 끓이는 법"))
    }

    /// 근거는 실제 경로를 담되 짧아야 한다.
    /// 길게 늘어놓으면 그 안의 다른 이름을 골라 엉뚱한 경로를 만든다(실측).
    func testEvidenceIsShortAndCarriesRealPath() {
        let evidence = CompanionSettingsIndex.bestMatch(for: "미리알림 연동")?.evidence

        XCTAssertNotNil(evidence)
        XCTAssertTrue(evidence!.contains("설정 → 메모"))
        XCTAssertLessThan(evidence!.count, 60)
    }
}

/// 색인이 낡으면 앱 검색과 호로롱 답변이 함께 틀린다.
final class SettingsSearchIndexTests: XCTestCase {
    func testAppearanceKeywordsMatchActualThemes() {
        for theme in Constants.PopoverTheme.allCases {
            XCTAssertTrue(
                SettingsTab.appearance.searchKeywords.contains(theme.label),
                "테마 \(theme.label) 가 검색 색인에 없다"
            )
        }
    }

    func testMemoKeywordsCoverRemindersImport() {
        XCTAssertTrue(
            SettingsTab.memo.searchKeywords.contains { $0.contains("미리알림") }
        )
    }
}

@MainActor
final class CompanionCardHighlightTests: XCTestCase {
    /// 카드마다 식별자를 손으로 달지 않고, 제목이 가장 잘 맞는 카드가 스스로 강조돼야 한다.
    func testBestMatchingCardWins() {
        let center = CompanionHighlightCenter.shared
        center.beginCardSearch(tokens: CompanionGuide.searchTokens(in: "휴가 때 기록 안 남기려면?"))

        center.registerCard("타임라인 표시")
        center.registerCard("보관")
        center.registerCard("휴가 기간")

        XCTAssertTrue(center.isHighlighted(CompanionHighlightCenter.cardID("휴가 기간")))
        center.endCardSearch()
        center.highlight(nil)
    }

    /// 등록 순서와 무관하게 같은 카드가 뽑혀야 한다.
    func testOrderDoesNotChangeTheWinner() {
        let center = CompanionHighlightCenter.shared
        center.beginCardSearch(tokens: CompanionGuide.searchTokens(in: "미리알림 연동"))

        center.registerCard("미리알림 가져오기")
        center.registerCard("퀵 메모")

        XCTAssertTrue(center.isHighlighted(CompanionHighlightCenter.cardID("미리알림 가져오기")))
        center.endCardSearch()
        center.highlight(nil)
    }

    /// 맞는 카드가 없으면 아무것도 강조하지 않는다.
    func testNoMatchLeavesNothingHighlighted() {
        let center = CompanionHighlightCenter.shared
        center.beginCardSearch(tokens: CompanionGuide.searchTokens(in: "김치찌개 끓이는 법"))

        center.registerCard("타임라인 표시")
        center.registerCard("보관")

        XCTAssertNil(center.target)
        center.endCardSearch()
    }

    /// 검색을 시작하지 않았으면 카드 등록이 아무 영향도 주면 안 된다.
    func testRegisteringWithoutSearchDoesNothing() {
        let center = CompanionHighlightCenter.shared
        center.endCardSearch()
        center.highlight(nil)

        center.registerCard("휴가 기간")

        XCTAssertNil(center.target)
    }
}

final class CompanionUserProfileTests: XCTestCase {
    func testEmptyProfileAddsNothingToThePrompt() {
        XCTAssertTrue(CompanionUserProfile.empty.promptSection.isEmpty)
        XCTAssertTrue(CompanionUserProfile.empty.isEmpty)
    }

    func testNicknameAloneProducesACallingInstruction() {
        let profile = CompanionUserProfile.normalized(nickname: "지혁님", note: "")

        XCTAssertTrue(profile.promptSection.contains("지혁님"))
        XCTAssertFalse(profile.promptSection.contains("참고 사항"))
    }

    func testNoteAloneIsCarriedIntoThePrompt() {
        let profile = CompanionUserProfile.normalized(nickname: "", note: "야근이 잦아요")

        XCTAssertTrue(profile.promptSection.contains("야근이 잦아요"))
    }

    /// 호칭을 따옴표로 감싸 "이렇게 부르라"고 지시하면 안전 필터가 역할 조작으로 오탐해
    /// 응답 자체가 막힌다. 사실을 나열하는 형태를 유지해야 한다.
    func testPromptSectionAvoidsQuotedNamingInstruction() {
        let section = CompanionUserProfile
            .normalized(nickname: "지혁", note: "야근이 잦아요")
            .promptSection

        XCTAssertFalse(section.contains("\""), "호칭을 따옴표로 감싸면 안 된다")
        XCTAssertFalse(section.contains("부릅니다"), "호칭을 지시문으로 쓰면 안 된다")
        XCTAssertTrue(section.contains("사용자 호칭: 지혁"))
    }

    func testWhitespaceOnlyInputIsTreatedAsEmpty() {
        let profile = CompanionUserProfile.normalized(nickname: "   ", note: "\n\t ")

        XCTAssertTrue(profile.isEmpty)
        XCTAssertTrue(profile.promptSection.isEmpty)
    }

    /// 온디바이스 모델의 컨텍스트가 짧아 길이 상한을 지켜야 한다.
    func testOverlongInputIsClipped() {
        let profile = CompanionUserProfile.normalized(
            nickname: String(repeating: "가", count: 100),
            note: String(repeating: "나", count: 1_000)
        )

        XCTAssertEqual(profile.nickname.count, Constants.companionUserNicknameMaxLength)
        XCTAssertEqual(profile.note.count, Constants.companionUserNoteMaxLength)
    }

    func testProfileRoundTripsThroughDefaults() {
        let defaults = UserDefaults(suiteName: "companion.profile.tests")!
        defaults.removePersistentDomain(forName: "companion.profile.tests")
        defaults.set("지혁님", forKey: Constants.AppStorageKey.companionUserNickname)
        defaults.set("야근이 잦아요", forKey: Constants.AppStorageKey.companionUserNote)

        let profile = CompanionUserProfile.load(from: defaults)

        XCTAssertEqual(profile.nickname, "지혁님")
        XCTAssertEqual(profile.note, "야근이 잦아요")
        defaults.removePersistentDomain(forName: "companion.profile.tests")
    }

    func testMissingDefaultsProduceAnEmptyProfile() {
        let defaults = UserDefaults(suiteName: "companion.profile.empty.tests")!
        defaults.removePersistentDomain(forName: "companion.profile.empty.tests")

        XCTAssertTrue(CompanionUserProfile.load(from: defaults).isEmpty)
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

    /// 도구 결과에 없는 할일은 모델이 지어낸 것이다. 요약문은 사실만 담아야 한다.
    func testDigestListsOnlyTodayTasks() {
        let now = date(29, 10)
        let items = [
            CompanionBriefingItem(title: "보고서 작성", isCompleted: false, startDate: nil, deadline: date(29, 18)),
            CompanionBriefingItem(title: "내일 회의", isCompleted: false, startDate: nil, deadline: date(30, 10)),
        ]

        let digest = CompanionTaskDigest.format(items: items, now: now, calendar: calendar)

        XCTAssertTrue(digest.contains("보고서 작성"))
        XCTAssertFalse(digest.contains("내일 회의"))
    }

    /// 할일이 없을 때 "없다"고 못 박아야 모델이 예시를 채우지 않는다.
    func testDigestSaysNothingIsRegisteredWhenEmpty() {
        let digest = CompanionTaskDigest.format(items: [], now: date(29), calendar: calendar)

        XCTAssertEqual(digest, "오늘 등록된 할일: 없음")
    }

    /// 브리핑과 달리 도구는 완료된 할일도 상태를 붙여 보여준다.
    func testDigestIncludesCompletedTasksWithMarker() {
        let now = date(29, 10)
        let items = [
            CompanionBriefingItem(title: "운동", isCompleted: true, startDate: date(29), deadline: nil),
        ]

        let digest = CompanionTaskDigest.format(items: items, now: now, calendar: calendar)

        XCTAssertTrue(digest.contains("운동"))
        XCTAssertTrue(digest.contains("완료됨"))
    }

    func testDigestShowsDeadlineTime() {
        let now = date(29, 10)
        let items = [
            CompanionBriefingItem(title: "보고서", isCompleted: false, startDate: nil, deadline: date(29, 18)),
        ]

        let digest = CompanionTaskDigest.format(items: items, now: now, calendar: calendar)

        XCTAssertTrue(digest.contains("마감"))
    }

    /// 브리핑은 완료된 항목을 계속 제외해야 한다(도구와 정책이 다르다).
    func testBriefingStillExcludesCompletedTasks() {
        let now = date(29, 10)
        let items = [
            CompanionBriefingItem(title: "운동", isCompleted: true, startDate: date(29), deadline: nil),
        ]

        XCTAssertTrue(
            CompanionBriefingComposer.todayItems(from: items, now: now, calendar: calendar).isEmpty
        )
        XCTAssertEqual(
            CompanionBriefingComposer.todayItems(
                from: items, now: now, calendar: calendar, includingCompleted: true
            ).count,
            1
        )
    }

    func testNextFireDateStaysTodayWhenTimeIsAhead() {
        XCTAssertEqual(
            CompanionBriefingSchedule.nextFireDate(
                after: date(29, 8, 0), hour: 9, minute: 30, calendar: calendar
            ),
            date(29, 9, 30)
        )
    }

    func testNextFireDateMovesToTomorrowWhenTimeHasPassed() {
        XCTAssertEqual(
            CompanionBriefingSchedule.nextFireDate(
                after: date(29, 10, 0), hour: 9, minute: 30, calendar: calendar
            ),
            date(30, 9, 30)
        )
    }

    /// 예약 시각과 정확히 같은 순간이면 이미 지난 것으로 보고 내일로 넘긴다(중복 발화 방지).
    func testNextFireDateAtTheExactMomentMovesToTomorrow() {
        XCTAssertEqual(
            CompanionBriefingSchedule.nextFireDate(
                after: date(29, 9, 30), hour: 9, minute: 30, calendar: calendar
            ),
            date(30, 9, 30)
        )
    }

    func testNextFireDateNormalizesOutOfRangeInput() {
        XCTAssertEqual(
            CompanionBriefingSchedule.nextFireDate(
                after: date(29, 8, 0), hour: 99, minute: 99, calendar: calendar
            ),
            date(29, 23, 59)
        )
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
