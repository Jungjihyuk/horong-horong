import XCTest
@testable import HorongAI

/// Ollama 세션에서 네트워크 없이 검증할 수 있는 부분 — **대화 문맥 관리**의 현재 동작.
///
/// Ollama 서버는 세션을 기억하지 않아 우리가 히스토리를 들고 다닌다.
/// 무한정 늘면 프롬프트가 터지므로 잘라내는데, 그 규칙이 여기 있다.
@MainActor
final class OllamaSessionTests: XCTestCase {

    private func history(userTurns: Int) -> [OllamaChatClient.Message] {
        var messages: [OllamaChatClient.Message] = [.init(role: "system", content: "너는 루미롱이다.")]
        for i in 0..<userTurns {
            messages.append(.init(role: "user", content: "메시지 \(i)"))
        }
        return messages
    }

    /// 세션은 system 한 줄로 시작한다.
    func testStartsWithSystemMessage() {
        let session = OllamaSession(
            client: OllamaChatClient(endpoint: "http://localhost:11434", model: "test"),
            instructions: "너는 루미롱이다."
        )
        XCTAssertEqual(session.messages.count, 1)
        XCTAssertEqual(session.messages.first?.role, "system")
        XCTAssertEqual(session.messages.first?.content, "너는 루미롱이다.")
    }

    /// **system 은 잘려 나가지 않는다.** 캐릭터 설정이 사라지면 말투가 통째로 바뀐다.
    func testSystemMessageSurvivesTrimming() {
        let trimmed = OllamaSession.trimmed(history(userTurns: 40))

        XCTAssertEqual(trimmed.first?.role, "system")
        XCTAssertEqual(trimmed.first?.content, "너는 루미롱이다.")
    }

    /// system 을 뺀 나머지는 `maxTurns` 개까지만 남는다.
    func testTrimsToMaxTurns() {
        let trimmed = OllamaSession.trimmed(history(userTurns: 40))

        XCTAssertEqual(trimmed.count, OllamaSession.maxTurns + 1)
    }

    /// 잘라낼 때 **오래된 것부터** 버린다 — 최근 대화가 남아야 문맥이 이어진다.
    func testKeepsMostRecentTurns() {
        let trimmed = OllamaSession.trimmed(history(userTurns: 40))

        XCTAssertEqual(trimmed.last?.content, "메시지 39")
        XCTAssertFalse(trimmed.contains { $0.content == "메시지 0" })
    }

    /// 한도 안이면 아무것도 버리지 않는다.
    func testKeepsEverythingWithinLimit() {
        let trimmed = OllamaSession.trimmed(history(userTurns: 1))

        XCTAssertEqual(trimmed.count, 2)
    }

    /// 빈 배열에도 터지지 않는다.
    func testEmptyHistoryIsSafe() {
        XCTAssertTrue(OllamaSession.trimmed([]).isEmpty)
    }
}
