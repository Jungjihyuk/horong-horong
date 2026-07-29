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
