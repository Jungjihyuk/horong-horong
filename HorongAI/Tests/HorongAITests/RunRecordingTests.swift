import XCTest
@testable import HorongAI

/// `RunRecord` 와 `RunLogger` 의 **현재 동작**을 못 박는 특성화 테스트.
///
/// 이 둘이 JSONL 스키마의 유일한 출처다. 필드 이름이 바뀌면 지금까지 쌓인 결과와
/// 비교가 끊기므로, 스키마를 문자열로 고정해 둔다.
final class RunRecordingTests: XCTestCase {

    private func makeResult() -> RunRecord {
        RunRecord(
            caseId: "case-1",
            model: "appleFoundation",
            output: "- 주간 보고서 마무리",
            scores: ["pairF1": 0.5],
            totalMs: 1234
        )
    }

    /// JSONL 은 나중에 리포트 도구(`Evals/report/eval-report.py`)가 읽는다.
    /// **키 이름이 계약이다** — snake_case 로 나가야 한다.
    func testResultEncodesSnakeCaseKeys() throws {
        let data = try JSONEncoder().encode(makeResult())
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"case_id\""), json)
        XCTAssertTrue(json.contains("\"total_ms\""), json)
        XCTAssertFalse(json.contains("\"caseId\""), json)
        XCTAssertFalse(json.contains("\"totalMs\""), json)
    }

    func testResultRoundTrips() throws {
        let data = try JSONEncoder().encode(makeResult())
        let decoded = try JSONDecoder().decode(RunRecord.self, from: data)

        XCTAssertEqual(decoded.caseId, "case-1")
        XCTAssertEqual(decoded.totalMs, 1234)
        XCTAssertEqual(decoded.scores["pairF1"], 0.5)
    }

    // MARK: - 최소 줄

    /// 실사용 줄에는 `case_id` 가 없다 — 정답이 있는 시험 문제가 아니기 때문이다.
    /// 그래도 읽히고 써져야 한다.
    func testDecodesRecordWithoutCaseId() throws {
        let line = """
        {"model":"qwen3:8b","output":"- 주간 보고서 마무리","scores":{},"total_ms":9721,\
        "run_id":"R-7f3a","task":"weekly_goal","source":"live","attempt":2}
        """

        let decoded = try JSONDecoder().decode(RunRecord.self, from: Data(line.utf8))

        XCTAssertNil(decoded.caseId)
        XCTAssertEqual(decoded.runId, "R-7f3a")
        XCTAssertEqual(decoded.attempt, 2)
        XCTAssertTrue(decoded.scores.isEmpty)
        XCTAssertNil(decoded.parse, "안 채운 필드는 nil 이다")
    }

    /// 새 필드도 snake_case 로 나가야 리포트 도구가 같은 규칙으로 읽는다.
    func testNewFieldsEncodeSnakeCase() throws {
        let record = RunRecord(
            output: "- 목표",
            totalMs: 10,
            runId: "run-1",
            task: "weekly_goal",
            source: "live",
            recipe: "promptOnly",
            provider: "ollama",
            attempt: 1,
            inputSummary: RunRecord.InputSummary(
                candidateCount: 123, itemCount: 60, itemIDs: ["m1"], promptCharacters: 11_862
            ),
            outcome: "decodeFailed",
            parse: RunRecord.ParseSummary(
                modelReturned: 3, kept: 1, requestedIDs: 6,
                badID: 0, alreadyUsed: 1, overMaxMemo: 0, tooFewIDs: 2
            ),
            usage: RunRecord.UsageSummary(tokensIn: 2_000, tokensOut: 300),
            timings: ["generate": 58_000]
        )

        let json = try XCTUnwrap(String(data: try JSONEncoder().encode(record), encoding: .utf8))

        for key in [
            "run_id", "attempt", "input_summary", "candidate_count", "item_ids",
            "prompt_characters", "model_returned", "too_few_ids", "tokens_in", "timings",
        ] {
            XCTAssertTrue(json.contains("\"\(key)\""), "\(key) 가 없다: \(json)")
        }
    }

    /// 실사용 기록에는 `scores` 가 비어 있는 것이 정상이다 —
    /// `pairF1` 은 정답 묶음이 있어야 매길 수 있고 사용자의 할일에는 정답이 없다.
    func testLiveRecordHasNoScores() throws {
        let record = RunRecord(output: "- 목표", totalMs: 10, source: "live")

        XCTAssertTrue(record.scores.isEmpty)
        XCTAssertNil(record.caseId)
    }

    /// 한 줄에 한 결과. 줄이 나뉘면 JSONL 이 깨진다.
    func testRunnerWritesOneLinePerResult() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("eval-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }

        let runner = RunLogger(outputURL: url)
        runner.record(makeResult())
        runner.record(makeResult())
        runner.flush()

        let lines = try readLines(at: url)
        XCTAssertEqual(lines.count, 2)
        XCTAssertNoThrow(try JSONDecoder().decode(RunRecord.self, from: Data(lines[0].utf8)))
    }

    /// 새 런은 이전 결과를 지우고 시작한다 — 한 파일에 두 실행이 섞이지 않게.
    func testRunnerTruncatesExistingFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("eval-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try "이전 내용\n".write(to: url, atomically: true, encoding: .utf8)

        let runner = RunLogger(outputURL: url)
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
