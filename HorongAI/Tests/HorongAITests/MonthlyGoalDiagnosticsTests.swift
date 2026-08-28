import XCTest
@testable import HorongAI

/// 월간 «초안 0개» 의 **이유가 갈리는지** 못 박는다.
///
/// 예전에는 `parse` 가 후보 목록만 돌려주고 실패 이유를 버려서, 서로 다른 세 원인이
/// 기록에서 똑같이 `parsedEmpty/emptyList` 로 보였다. 실측(2026-08-19/20) 8건을 가르려고
/// trace 파일을 하나씩 열어 JSON 을 직접 파싱해야 했다.
///
/// 여기 세 테스트가 그 세 원인이다.
final class MonthlyGoalDiagnosticsTests: XCTestCase {

    private func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "%08X-0000-0000-0000-000000000000", n))!
    }

    private func goal(_ n: Int, title: String) -> MonthlyGoalTask.Goal {
        MonthlyGoalTask.Goal(
            id: uuid(n), title: title, emoji: "🎯", rule: "연결한 할일 3개 완료",
            done: 1, total: 3, sourceMemoIDs: [uuid(100 + n)], roleName: "", vision: ""
        )
    }

    private lazy var goals = (1...4).map { goal($0, title: "주간 목표 \($0)") }

    private func parse(_ text: String) -> WeeklyGoalTask.ParseOutcome {
        MonthlyGoalTask.parse(
            text,
            allowedIDs: Set(goals.map(\.id)),
            sourceGoals: goals,
            suggestionCount: 3
        )
    }

    private func json(_ suggestions: String) -> String {
        "{\"suggestions\": [\(suggestions)]}"
    }

    // MARK: - 정상

    func testKeepsSuggestionWithTwoGoals() {
        let outcome = parse(json("""
        {"title": "취업 준비", "reason": "함께", "goalIDs": ["\(uuid(1))", "\(uuid(2))"]}
        """))
        XCTAssertEqual(outcome.drafts.count, 1)
        guard case .decoded(let returned, let kept, _, _, _, _, let tooFew) = outcome.diagnostics else {
            return XCTFail("decoded 여야 한다")
        }
        XCTAssertEqual(returned, 1)
        XCTAssertEqual(kept, 1)
        XCTAssertEqual(tooFew, 0)
    }

    func testRunWritesGuidanceToParsedTrace() async {
        let trace = TraceCollector(runId: "monthly-guidance", task: nil, provider: nil, model: nil, attempt: nil)

        _ = await MonthlyGoalTask.run(
            goals: goals,
            suggestionCount: 3,
            inputLimit: 10,
            trace: trace,
            generate: { _, _ in
                """
                {"resultType":"guidance","guidance":[
                  {"items":["\(self.uuid(1))"],"missing":["measurable"],"suggestion":"완료 기준을 정해보세요."}
                ]}
                """
            }
        )

        let parsed = trace.finish().spans.first { $0.name == .parsed }
        XCTAssertEqual(
            parsed?.text,
            "- inputID=\(uuid(1).uuidString) missing=[measurable] suggestion=완료 기준을 정해보세요."
        )
        XCTAssertEqual(parsed?.facts?["kept"], 1)
    }

    // MARK: - «초안 0개» 의 세 가지 이유

    /// ① **모델이 1개씩만 묶었다.** 실측에서 AFM 이 3번 그랬다.
    /// 응답은 멀쩡한데 «2개 이상» 규칙에 걸려 전부 버려진다.
    func testTooFewIDsIsCountedSeparately() {
        let outcome = parse(json("""
        {"title": "취업 준비", "reason": "하나", "goalIDs": ["\(uuid(1))"]},
        {"title": "일정 관리", "reason": "하나", "goalIDs": ["\(uuid(2))"]}
        """))
        XCTAssertTrue(outcome.drafts.isEmpty)
        guard case .decoded(let returned, let kept, let requested, _, _, _, let tooFew) = outcome.diagnostics else {
            return XCTFail("decoded 여야 한다")
        }
        XCTAssertEqual(returned, 2, "모델은 2개를 냈다 — «아무것도 안 냈다» 와 구분되어야 한다")
        XCTAssertEqual(kept, 0)
        XCTAssertEqual(requested, 2)
        XCTAssertEqual(tooFew, 2, "두 묶음 모두 id 가 2개 미만이라 버려졌다")
    }

    /// ② **응답이 잘렸다.** AFM 이 `max_tokens` 900 에 걸려 2,016자에서 끊긴 사례.
    func testTruncatedResponseIsReportedAsDecodeFailure() {
        let outcome = parse("""
        {"suggestions": [{"title": "취업 준비", "reason": "함께", "criterion": "연결한
        """)
        XCTAssertTrue(outcome.drafts.isEmpty)
        guard case .decodeFailed(_, let reason) = outcome.diagnostics else {
            return XCTFail("decodeFailed 여야 한다 — 예전에는 이게 «빈 목록» 으로 보였다")
        }
        XCTAssertEqual(reason, "truncated")
    }

    /// ③ **JSON 을 아예 안 냈다.** `qwen3:4b` 가 영어로 생각만 늘어놓은 사례.
    func testProseOnlyResponseIsReportedAsNoJSON() {
        let outcome = parse("Okay, let's tackle this problem step by step. The user wants me to")
        XCTAssertTrue(outcome.drafts.isEmpty)
        guard case .decodeFailed(_, let reason) = outcome.diagnostics else {
            return XCTFail("decodeFailed 여야 한다")
        }
        XCTAssertEqual(reason, "noJSON")
    }

    /// 진짜로 빈 목록을 낸 경우. 위 셋과 또 다르다 — 모델이 «묶을 게 없다» 고 답한 것이다.
    func testGenuinelyEmptyListIsNotADecodeFailure() {
        let outcome = parse("{\"suggestions\": []}")
        guard case .decoded(let returned, let kept, _, _, _, _, _) = outcome.diagnostics else {
            return XCTFail("decoded 여야 한다")
        }
        XCTAssertEqual(returned, 0)
        XCTAssertEqual(kept, 0)
    }

    // MARK: - 나머지 카운터

    /// 없는 id 를 지어내면 센다.
    func testCountsHallucinatedIDs() {
        let outcome = parse(json("""
        {"title": "취업 준비", "reason": "함께",
         "goalIDs": ["\(uuid(1))", "DEADBEEF-0000-0000-0000-000000000000", "없는값"]}
        """))
        guard case .decoded(_, _, let requested, let badID, _, _, _) = outcome.diagnostics else {
            return XCTFail("decoded 여야 한다")
        }
        XCTAssertEqual(requested, 3)
        XCTAssertEqual(badID, 2)
    }

    /// 같은 주간 목표를 두 묶음에 넣으면 뒤엣것에서 뺀다.
    func testCountsAlreadyUsedIDs() {
        let outcome = parse(json("""
        {"title": "묶음 1", "reason": "함께", "goalIDs": ["\(uuid(1))", "\(uuid(2))"]},
        {"title": "묶음 2", "reason": "함께", "goalIDs": ["\(uuid(1))", "\(uuid(3))"]}
        """))
        guard case .decoded(_, let kept, _, _, let alreadyUsed, _, let tooFew) = outcome.diagnostics else {
            return XCTFail("decoded 여야 한다")
        }
        XCTAssertEqual(kept, 1, "두 번째는 쓸 수 있는 id 가 1개뿐이라 버려진다")
        XCTAssertEqual(alreadyUsed, 1)
        XCTAssertEqual(tooFew, 1)
    }
}
