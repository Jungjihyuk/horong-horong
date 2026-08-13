import XCTest
@testable import HorongAI

/// `OllamaChatClient` 에서 네트워크 없이 검증할 수 있는 유일한 부분 —
/// 엔드포인트 문자열을 URL 로 만드는 규칙의 **현재 동작**을 못 박는다.
///
/// 사용자가 설정 화면에 주소를 직접 입력하므로 공백·슬래시가 섞여 들어온다.
final class OllamaChatClientTests: XCTestCase {

    func testJoinsEndpointAndPath() {
        XCTAssertEqual(
            OllamaChatClient.url(endpoint: "http://localhost:11434", path: "/api/chat")?.absoluteString,
            "http://localhost:11434/api/chat"
        )
    }

    /// 사용자가 끝에 슬래시를 붙여 넣어도 `//api/chat` 가 되지 않는다.
    func testTrimsTrailingSlash() {
        XCTAssertEqual(
            OllamaChatClient.url(endpoint: "http://localhost:11434/", path: "/api/chat")?.absoluteString,
            "http://localhost:11434/api/chat"
        )
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(
            OllamaChatClient.url(endpoint: "  http://localhost:11434  ", path: "/api/tags")?.absoluteString,
            "http://localhost:11434/api/tags"
        )
    }

    func testEmptyEndpointIsNil() {
        XCTAssertNil(OllamaChatClient.url(endpoint: "", path: "/api/chat"))
        XCTAssertNil(OllamaChatClient.url(endpoint: "   ", path: "/api/chat"))
        XCTAssertNil(OllamaChatClient.url(endpoint: "///", path: "/api/chat"))
    }

    /// **양쪽 슬래시를 다 떼는 현재 동작.** 스킴 없이 주소만 넣으면 상대 URL 이 만들어져
    /// `nil` 이 아니다 — 즉 이 함수만으로는 "올바른 주소"를 보장하지 않는다.
    func testSchemelessEndpointStillProducesURL() {
        let url = OllamaChatClient.url(endpoint: "//localhost:11434", path: "/api/chat")
        XCTAssertEqual(url?.absoluteString, "localhost:11434/api/chat")
    }
}
