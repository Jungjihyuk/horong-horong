import XCTest
@testable import 호롱호롱

final class ReferenceURLPolicyTests: XCTestCase {
    func testNormalizesSupportedWebAddresses() {
        XCTAssertEqual(ReferenceURLPolicy.normalize("example.com/path"), "https://example.com/path")
        XCTAssertEqual(ReferenceURLPolicy.normalize("www.example.com"), "https://www.example.com")
        XCTAssertEqual(ReferenceURLPolicy.normalize("http://example.com"), "http://example.com")
    }

    func testRejectsNonWebAndMalformedValues() {
        XCTAssertNil(ReferenceURLPolicy.normalize(""))
        XCTAssertNil(ReferenceURLPolicy.normalize("hello world"))
        XCTAssertNil(ReferenceURLPolicy.normalize("file:///tmp/a"))
        XCTAssertNil(ReferenceURLPolicy.normalize("localhost"))
    }

    func testFallbackTitleUsesHostWithoutWWW() {
        XCTAssertEqual(ReferenceURLPolicy.fallbackTitle(for: "https://www.example.com/a"), "example.com")
    }
}
