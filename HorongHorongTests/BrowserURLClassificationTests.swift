import XCTest
@testable import 호롱호롱

final class BrowserURLClassificationTests: XCTestCase {
    func testEntertainmentURLClassification() {
        XCTAssertEqual(AppTracker.entertainmentLabel(for: "https://www.youtube.com/watch?v=abc"), "YouTube")
        XCTAssertEqual(AppTracker.entertainmentLabel(for: "https://youtu.be/abc"), "YouTube")
        XCTAssertEqual(AppTracker.entertainmentLabel(for: "https://www.netflix.com/watch/123"), "Netflix")
        XCTAssertNil(AppTracker.entertainmentLabel(for: "https://developer.apple.com/documentation"))
    }

    func testResearchURLClassification() {
        XCTAssertEqual(AppTracker.researchLabel(for: "https://www.google.com/search?q=swiftdata"), "Google Search")
        XCTAssertEqual(AppTracker.researchLabel(for: "https://developer.mozilla.org/en-US/docs/Web"), "MDN")
        XCTAssertEqual(AppTracker.researchLabel(for: "https://some-team.github.io/project-docs"), "GitHub Pages")
        XCTAssertEqual(AppTracker.researchLabel(for: "https://example.tistory.com/entry/swift"), "Tistory")
        XCTAssertNil(AppTracker.researchLabel(for: "https://www.google.com/maps"))
    }
}
