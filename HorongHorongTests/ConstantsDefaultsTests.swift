import XCTest
@testable import 호롱호롱

final class ConstantsDefaultsTests: XCTestCase {
    func testTimerPresetDefaultsMatchDocumentedValues() {
        XCTAssertEqual(Constants.PomodoroPreset.pomodoro.focusMinutes, 50)
        XCTAssertEqual(Constants.PomodoroPreset.pomodoro.breakMinutes, 5)
        XCTAssertEqual(Constants.PomodoroPreset.longFocus.focusMinutes, 100)
        XCTAssertEqual(Constants.PomodoroPreset.longFocus.breakMinutes, 10)
        XCTAssertEqual(Constants.PomodoroPreset.custom.focusMinutes, 60)
        XCTAssertEqual(Constants.PomodoroPreset.custom.breakMinutes, 10)
    }

    func testDefaultCategoryDefinitionsDoNotIncludeRemovedDocumentCategory() {
        let defaultNames = Constants.defaultCategoryDefinitions.map(\.defaultName)

        XCTAssertFalse(defaultNames.contains("문서"))
        XCTAssertTrue(defaultNames.contains("기록"))
        XCTAssertTrue(defaultNames.contains("조사"))
        XCTAssertTrue(defaultNames.contains("기타"))
    }

    func testAgentDerivedDirectoriesUseSingleRoot() {
        let root = "/tmp/HorongHorongTests/experiments"

        XCTAssertEqual(Constants.agentIdeaDirectoryPath(for: root), "/tmp/HorongHorongTests/experiments/ideas")
        XCTAssertEqual(Constants.agentOutputDirectoryPath(for: root), "/tmp/HorongHorongTests/experiments/outputs")
        XCTAssertEqual(Constants.agentIdeaDirectoryPath(for: "   "), "")
        XCTAssertEqual(Constants.agentOutputDirectoryPath(for: ""), "")
    }

    func testPublicDefaultInterestKeywords() {
        XCTAssertEqual(Constants.defaultInterestKeywords, "생산성, 자동화, 학습")
        XCTAssertEqual(Constants.defaultNewsInterestKeywords, "AI, 개발, 생산성, 자동화")
    }
}
