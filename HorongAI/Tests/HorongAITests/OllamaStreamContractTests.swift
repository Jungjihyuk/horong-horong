import XCTest
@testable import HorongAI

/// `stream` 이 **조각이 아니라 매번 지금까지의 전문**을 준다는 약속을 못 박는다.
///
/// 이 약속을 문서(`stream` 의 주석)에만 적어 뒀더니 소비자 둘이 서로 다르게 읽었다 —
/// 대화는 `text = partial`(맞음), 목표 추천은 `text += piece`(틀림)로 접어서
/// Ollama 추천이 항상 깨진 JSON 을 만들고 조용히 AFM 으로 폴백했다.
///
/// 이름이 `piece`/`partial` 이라 어느 유파(델타 vs 스냅샷)인지 호출부에서 알 수 없다.
/// 그래서 주석이 아니라 테스트로 고정한다.
final class OllamaStreamContractTests: XCTestCase {

    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(StubOllamaProtocol.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(StubOllamaProtocol.self)
        StubOllamaProtocol.body = Data()
        super.tearDown()
    }

    private func client() -> OllamaChatClient {
        OllamaChatClient(endpoint: "http://stub.invalid", model: "test-model")
    }

    private func collect() async throws -> [String] {
        var received: [String] = []
        for try await partial in client().stream(
            messages: [.init(role: "user", content: "안녕")],
            temperature: 0.2,
            maxTokens: 100
        ) {
            received.append(partial)
        }
        return received
    }

    /// 세 조각 `{"a"` · `:1` · `}` 이 오면 받는 쪽은 **누적본 세 개**를 본다.
    /// 마지막 값 하나가 곧 완성본이므로, 소비자는 더하지 말고 덮어써야 한다.
    func testStreamYieldsCumulativeSnapshotsNotDeltas() async throws {
        StubOllamaProtocol.body = Self.ndjson(contents: ["{\"a\"", ":1", "}"])

        let received = try await collect()

        XCTAssertEqual(received, ["{\"a\"", "{\"a\":1", "{\"a\":1}"])
        XCTAssertEqual(received.last, "{\"a\":1}", "마지막 값이 완성본이다")
    }

    /// 빈 조각은 흘려보내지 않는다 — 안 그러면 같은 값이 두 번 와 소비자가 중복으로 센다.
    func testSkipsEmptyContentChunks() async throws {
        StubOllamaProtocol.body = Self.ndjson(contents: ["가", "", "나"])

        let received = try await collect()

        XCTAssertEqual(received, ["가", "가나"])
    }

    // MARK: - NDJSON 만들기

    /// Ollama 는 줄마다 JSON 하나를 보내고 마지막 줄에 `done: true` 를 담는다.
    private static func ndjson(contents: [String]) -> Data {
        let lines = contents.map { content -> String in
            let escaped = content.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "{\"message\":{\"role\":\"assistant\",\"content\":\"\(escaped)\"},\"done\":false}"
        } + ["{\"done\":true}"]
        return Data(lines.joined(separator: "\n").utf8)
    }
}

/// `URLSession.shared` 를 가로채 정해둔 NDJSON 을 돌려준다.
/// 서버 없이 스트림 접는 법만 검증하려는 장치다.
private final class StubOllamaProtocol: URLProtocol {
    nonisolated(unsafe) static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "stub.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: 200,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "application/x-ndjson"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
