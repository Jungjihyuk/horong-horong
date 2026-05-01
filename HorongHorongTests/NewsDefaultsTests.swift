import XCTest
@testable import 호롱호롱

final class NewsDefaultsTests: XCTestCase {
    func testDefaultNewsSourcesUsePublicFriendlyValues() {
        let sources = NewsSource.defaultSources

        let youtube = sources.first { $0.type == "youtube" }
        XCTAssertEqual(youtube?.enabled, true)
        XCTAssertEqual(youtube?.channelId, "UC_x5XG1OV2P6uZZ5FSM9Ttw")
        XCTAssertNil(youtube?.playlists)

        let googleNews = sources.first { $0.type == "google_news" }
        XCTAssertEqual(googleNews?.enabled, true)
        XCTAssertEqual(googleNews?.keywords, ["AI", "개발", "생산성", "자동화"])

        let yozm = sources.first { $0.type == "yozm_it" }
        XCTAssertEqual(yozm?.enabled, true)
        XCTAssertEqual(yozm?.keywords, ["개발", "생산성", "AI", "자동화"])

        let linkedIn = sources.first { $0.type == "linkedin" }
        XCTAssertEqual(linkedIn?.enabled, false)
    }
}
