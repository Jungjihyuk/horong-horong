import XCTest
@testable import HorongAI

/// `TraceRecorder` 의 현재 동작을 못 박는다.
///
/// 특히 **꺼져 있을 때 아무것도 안 남기는 것**이 중요하다 — 원문에는 사용자의 할일이
/// 그대로 들어가므로, 기본이 꺼짐이라는 사실이 무너지면 조용히 새어 나간다.
final class TraceRecorderTests: XCTestCase {

    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("traces-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func makeTrace(
        runId: String = "R-1",
        task: String = "weekly_goal",
        provider: String = "ollama",
        attempt: Int = 1
    ) -> RunTrace {
        var trace = RunTrace(
            runId: runId, task: task, provider: provider, model: "qwen3:8b", attempt: attempt
        )
        trace.append(.init(.prompt, text: "너는 …", facts: ["characters": 5]))
        trace.append(.init(.rawResponse, text: "<think>음…</think>\n{\"suggestions\": []}"))
        return trace
    }

    // MARK: - 꺼짐이 기본

    /// **꺼져 있으면 파일 자체가 생기지 않는다.** 빈 파일도 남기지 않는다.
    func testDisabledWritesNothing() {
        let recorder = TraceRecorder(directory: directory, isEnabled: false)
        recorder.record(makeTrace())
        recorder.flush()

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    // MARK: - 켜졌을 때

    func testEnabledWritesOneFilePerRun() throws {
        let recorder = TraceRecorder(directory: directory, isEnabled: true)
        recorder.record(makeTrace(runId: "R-1"))
        recorder.record(makeTrace(runId: "R-2"))
        recorder.flush()

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(Set(files), ["R-1_weekly_goal_1.json", "R-2_weekly_goal_1.json"])
    }

    // MARK: - 한 실행이 여러 trace 를 낳는다

    /// **주간·월간은 설계상 같은 `runId` 를 공유한다.** 한 번 누른 실행으로 묶기 위해서다.
    /// 파일 이름이 `runId` 뿐이면 나중에 쓴 쪽이 앞을 덮는다.
    func testWeeklyAndMonthlyOfSameRunDoNotCollide() throws {
        let recorder = TraceRecorder(directory: directory, isEnabled: true)
        recorder.record(makeTrace(runId: "R-1", task: "weekly_goal"))
        recorder.record(makeTrace(runId: "R-1", task: "monthly_goal"))
        recorder.flush()

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(Set(files), ["R-1_weekly_goal_1.json", "R-1_monthly_goal_1.json"])
    }

    /// 폴백이 일어나면 한 태스크가 시도를 여러 번 한다.
    ///
    /// 이걸 못 가르면 **성공한 폴백이 실패한 시도를 덮는다** — 실측(2026-08-19)에서 실제로
    /// 그렇게 잃었다. 원문을 남기는 목적이 실패를 쫓는 것인데 실패만 골라 지우는 꼴이었다.
    func testFallbackAttemptDoesNotOverwriteFailedAttempt() throws {
        let recorder = TraceRecorder(directory: directory, isEnabled: true)
        recorder.record(makeTrace(runId: "R-1", provider: "mlx", attempt: 1))
        recorder.record(makeTrace(runId: "R-1", provider: "appleFoundation", attempt: 2))
        recorder.flush()

        let failed = try XCTUnwrap(recorder.trace(runId: "R-1", task: "weekly_goal", attempt: 1))
        let fallback = try XCTUnwrap(recorder.trace(runId: "R-1", task: "weekly_goal", attempt: 2))
        XCTAssertEqual(failed.provider, "mlx")
        XCTAssertEqual(fallback.provider, "appleFoundation")
    }

    /// 원문이 손실 없이 돌아온다 — `<think>` 블록이 실제로 있었는지 보려면 그대로여야 한다.
    func testRoundTripsSpansVerbatim() throws {
        let recorder = TraceRecorder(directory: directory, isEnabled: true)
        recorder.record(makeTrace())
        recorder.flush()

        let loaded = try XCTUnwrap(recorder.trace(runId: "R-1", task: "weekly_goal", attempt: 1))
        XCTAssertEqual(loaded.runId, "R-1")
        XCTAssertEqual(loaded.task, "weekly_goal")
        XCTAssertEqual(loaded.attempt, 1)
        XCTAssertEqual(loaded.spans.count, 2)
        XCTAssertEqual(loaded.spans[0].name, .prompt)
        XCTAssertEqual(loaded.spans[0].facts?["characters"], 5)
        XCTAssertEqual(loaded.spans[1].text, "<think>음…</think>\n{\"suggestions\": []}")
    }

    /// 사람이 직접 열어 읽는 파일이라 여러 줄로 남긴다. 한 줄이면 원문 확인이 불가능하다.
    func testFileIsHumanReadable() throws {
        let recorder = TraceRecorder(directory: directory, isEnabled: true)
        recorder.record(makeTrace())
        recorder.flush()

        let text = try String(contentsOf: recorder.fileURL(runId: "R-1", task: "weekly_goal", attempt: 1), encoding: .utf8)
        XCTAssertTrue(text.contains("\n"))
        // 경로·태그가 \/ 로 깨져 나오면 읽기 어렵다.
        XCTAssertFalse(text.contains("\\/"))
    }

    func testMissingTraceReturnsNil() {
        let recorder = TraceRecorder(directory: directory, isEnabled: true)
        XCTAssertNil(recorder.trace(runId: "없는-런"))
    }

    // MARK: - 보존 기한

    /// 켜 둔 것을 잊어도 무한정 쌓이지 않는다.
    func testPurgeRemovesExpiredOnly() throws {
        let recorder = TraceRecorder(directory: directory, isEnabled: true, retentionDays: 7)
        recorder.record(makeTrace(runId: "old"))
        recorder.record(makeTrace(runId: "fresh"))
        recorder.flush()

        // 하나만 8일 전 것으로 돌려놓는다.
        let old = recorder.fileURL(runId: "old", task: "weekly_goal", attempt: 1)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-8 * 24 * 60 * 60)],
            ofItemAtPath: old.path
        )

        recorder.purgeExpired()
        recorder.flush()

        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recorder.fileURL(runId: "fresh", task: "weekly_goal", attempt: 1).path))
    }

    /// 폴더가 없어도 터지지 않는다 — 한 번도 기록하지 않은 상태에서 앱이 시작하는 경우.
    func testPurgeOnMissingDirectoryIsSafe() {
        let recorder = TraceRecorder(directory: directory, isEnabled: true)
        recorder.purgeExpired()
        recorder.flush()
    }
}
