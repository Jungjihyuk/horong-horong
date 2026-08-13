import XCTest
@testable import HorongAI

/// `EvalResult` 와 `EvalRunner` 의 **현재 동작**을 못 박는 특성화 테스트.
///
/// 이 둘이 JSONL 스키마의 유일한 출처다. 필드 이름이 바뀌면 지금까지 쌓인 결과와
/// 비교가 끊기므로, 스키마를 문자열로 고정해 둔다.
final class EvalRecordingTests: XCTestCase {

    private func makeResult() -> EvalResult {
        EvalResult(
            caseId: "case-1",
            input: "질문",
            level: "L0",
            model: "appleFoundation",
            output: "- 주간 보고서 마무리",
            scores: ["pairF1": 0.5],
            latencyMs: 1234
        )
    }

    /// JSONL 은 나중에 리포트 도구(`Evals/eval-report.py`)가 읽는다.
    /// **키 이름이 계약이다** — snake_case 로 나가야 한다.
    func testResultEncodesSnakeCaseKeys() throws {
        let data = try JSONEncoder().encode(makeResult())
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"case_id\""), json)
        XCTAssertTrue(json.contains("\"latency_ms\""), json)
        XCTAssertFalse(json.contains("\"caseId\""), json)
        XCTAssertFalse(json.contains("\"latencyMs\""), json)
    }

    func testResultRoundTrips() throws {
        let data = try JSONEncoder().encode(makeResult())
        let decoded = try JSONDecoder().decode(EvalResult.self, from: data)

        XCTAssertEqual(decoded.caseId, "case-1")
        XCTAssertEqual(decoded.level, "L0")
        XCTAssertEqual(decoded.latencyMs, 1234)
        XCTAssertEqual(decoded.scores["pairF1"], 0.5)
    }

    /// 한 줄에 한 결과. 줄이 나뉘면 JSONL 이 깨진다.
    func testRunnerWritesOneLinePerResult() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("eval-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }

        let runner = EvalRunner(outputURL: url)
        runner.record(makeResult())
        runner.record(makeResult())
        runner.flush()

        let lines = try readLines(at: url)
        XCTAssertEqual(lines.count, 2)
        XCTAssertNoThrow(try JSONDecoder().decode(EvalResult.self, from: Data(lines[0].utf8)))
    }

    /// 새 런은 이전 결과를 지우고 시작한다 — 한 파일에 두 실행이 섞이지 않게.
    func testRunnerTruncatesExistingFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("eval-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try "이전 내용\n".write(to: url, atomically: true, encoding: .utf8)

        let runner = EvalRunner(outputURL: url)
        runner.record(makeResult())
        runner.flush()

        let lines = try readLines(at: url)
        XCTAssertEqual(lines.count, 1)
        XCTAssertFalse(lines[0].contains("이전 내용"))
    }

    /// `flush()` 를 부른 뒤에는 기다릴 필요가 없다 — 그게 flush 의 계약이다.
    private func readLines(at url: URL) throws -> [String] {
        try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
    }
}
