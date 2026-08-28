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

    // MARK: - 설치 여부를 가릴 때 쓰는 태그 해석

    /// 태그를 적었으면 그대로 쓴다. `/api/tags` 가 돌려주는 이름과 같은 모양이다.
    func testKeepsExplicitTag() {
        XCTAssertEqual(OllamaChatClient.resolvedTag(for: "qwen3:8b"), "qwen3:8b")
        XCTAssertEqual(OllamaChatClient.resolvedTag(for: "qwen3.6:27b-q4_K_M"), "qwen3.6:27b-q4_K_M")
    }

    /// **태그를 생략하면 `:latest` 를 붙인다.** 이게 없으면 태그 없이 적은 모델이 전부
    /// «안 받아 둠» 으로 읽혀 조용히 Apple 모델로 내려간다 — 실패가 아니라 **다른 모델로
    /// 답이 나오므로** 사용자는 눈치채기 어렵다.
    func testAppendsLatestWhenTagOmitted() {
        XCTAssertEqual(OllamaChatClient.resolvedTag(for: "qwen3"), "qwen3:latest")
        XCTAssertEqual(OllamaChatClient.resolvedTag(for: "gemma4"), "gemma4:latest")
    }

    /// 이미 `:latest` 면 두 번 붙이지 않는다.
    func testDoesNotDoubleAppendLatest() {
        XCTAssertEqual(OllamaChatClient.resolvedTag(for: "qwen3:latest"), "qwen3:latest")
    }
}
