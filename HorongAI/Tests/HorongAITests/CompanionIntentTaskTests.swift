import XCTest
@testable import HorongAI

/// 평가기 `validate()`·`answer_context()` 와 같은 규칙인지 본다 (`Evals/companion_eval.py`).
final class CompanionIntentTaskTests: XCTestCase {
    private typealias Task = CompanionIntentTask

    private func json(
        _ action: String, date: String = "", after: String = "", title: String = "", nextOnly: String = "false",
        until: String = ""
    ) -> String {
        #"{"action":"\#(action)","date":"\#(date)","after":"\#(after)","title":"\#(title)","next_only":\#(nextOnly),"until":"\#(until)"}"#
    }

    // MARK: - 판단 읽기

    func testParsesLookupWithDateAndTime() throws {
        XCTAssertEqual(
            try Task.parseDecision(json("schedule_lookup", date: "2026-09-18", after: "14:00")),
            Task.Decision(action: .scheduleLookup, date: "2026-09-18", after: "14:00")
        )
    }

    func testParsesNextOnlyLookupWithoutDate() throws {
        XCTAssertEqual(
            try Task.parseDecision(json("schedule_lookup", nextOnly: "true")),
            Task.Decision(action: .scheduleLookup, nextOnly: true)
        )
    }

    func testRejectsMissingOrExtraFields() {
        XCTAssertThrowsError(try Task.parseDecision(#"{"action":"conversation"}"#)) {
            XCTAssertEqual($0 as? Task.DecisionError, .invalidFields)
        }
        let extra = #"{"action":"conversation","date":"","after":"","title":"","next_only":false,"until":"","x":1}"#
        XCTAssertThrowsError(try Task.parseDecision(extra)) {
            XCTAssertEqual($0 as? Task.DecisionError, .invalidFields)
        }
    }

    func testRejectsUnknownActionAndNumericBoolean() {
        XCTAssertThrowsError(try Task.parseDecision(json("delete_all"))) {
            XCTAssertEqual($0 as? Task.DecisionError, .invalidAction)
        }
        XCTAssertThrowsError(try Task.parseDecision(json("conversation", nextOnly: "0"))) {
            XCTAssertEqual($0 as? Task.DecisionError, .invalidValueType)
        }
    }

    /// 모양은 맞지만 뜻이 틀린 값은 문법으로 못 막는다. 저장소를 건드리기 전에 걸러야 한다.
    func testRejectsImpossibleDateAndTime() {
        XCTAssertThrowsError(try Task.parseDecision(json("schedule_lookup", date: "2026-13-01"))) {
            XCTAssertEqual($0 as? Task.DecisionError, .invalidDate)
        }
        XCTAssertThrowsError(try Task.parseDecision(json("schedule_lookup", date: "2026-09-18T10:00"))) {
            XCTAssertEqual($0 as? Task.DecisionError, .invalidDate)
        }
        XCTAssertThrowsError(try Task.parseDecision(json("schedule_lookup", date: "2026-09-18", after: "25:00"))) {
            XCTAssertEqual($0 as? Task.DecisionError, .invalidTime)
        }
    }

    func testCreateNeedsDateAndTitleAndLookupNeedsDateOrNext() {
        XCTAssertThrowsError(try Task.parseDecision(json("schedule_create", date: "2026-09-18", title: "  "))) {
            XCTAssertEqual($0 as? Task.DecisionError, .missingCreateArgument)
        }
        XCTAssertThrowsError(try Task.parseDecision(json("schedule_lookup"))) {
            XCTAssertEqual($0 as? Task.DecisionError, .missingLookupDate)
        }
    }

    // MARK: - v5: 기간 조회·옮기기

    func testParsesRangeLookupAndMove() throws {
        XCTAssertEqual(
            try Task.parseDecision(json("schedule_lookup", date: "2026-09-19", until: "2026-09-25")),
            Task.Decision(action: .scheduleLookup, date: "2026-09-19", until: "2026-09-25")
        )
        XCTAssertEqual(
            try Task.parseDecision(json("schedule_move", date: "2026-09-21", title: "면접 준비")),
            Task.Decision(action: .scheduleMove, date: "2026-09-21", title: "면접 준비")
        )
    }

    func testRejectsBackwardOrMisplacedRange() {
        XCTAssertThrowsError(try Task.parseDecision(json("schedule_lookup", date: "2026-09-25", until: "2026-09-19"))) {
            XCTAssertEqual($0 as? Task.DecisionError, .invalidRange)
        }
        XCTAssertThrowsError(try Task.parseDecision(json("schedule_create", date: "2026-09-25", title: "x", until: "2026-09-26"))) {
            XCTAssertEqual($0 as? Task.DecisionError, .invalidRange)
        }
    }

    func testMoveNeedsTargetAndDate() {
        XCTAssertThrowsError(try Task.parseDecision(json("schedule_move", date: "2026-09-21"))) {
            XCTAssertEqual($0 as? Task.DecisionError, .missingMoveArgument)
        }
    }

    /// 옮기기 결과는 평가기 `FakeTools` 의 모양 그대로 넘긴다. 대상이 없으면 '조회했지만 없음'과 같은 상태다.
    func testMoveContextShapes() {
        let moved = Task.AnswerContext(
            action: .scheduleMove,
            result: .moved(title: "면접 준비",
                           from: .init(title: "면접 준비", date: "2026-09-19", time: "11:00"),
                           to: .init(title: "면접 준비", date: "2026-09-21", time: "11:00")),
            now: now, timeZone: seoul
        )
        XCTAssertTrue(moved.jsonText.hasSuffix(
            #""source": "schedule_repository", "tool_status": "success", "result": {"status": "moved", "title": "면접 준비", "from": {"date": "2026-09-19", "time": "11:00"}, "to": {"date": "2026-09-21", "time": "11:00"}}}"#
        ), moved.jsonText)
        XCTAssertEqual(Task.AnswerContext(action: .scheduleMove, result: .moveNotFound, now: now, timeZone: seoul).toolStatus,
                       "success_empty")
    }

    func testDateTableStartsTodayAndSpansTwoWeeks() {
        let lines = Task.dateTable(now: now, timeZone: seoul).split(separator: "\n")
        XCTAssertEqual(lines.count, 14)
        XCTAssertEqual(lines.first, "2026-09-18 금요일 (오늘)")
        XCTAssertEqual(lines[1], "2026-09-19 토요일 (내일)")
        XCTAssertEqual(lines.last, "2026-10-01 목요일")
    }

    // MARK: - 답변 참고 데이터

    private let now = ISO8601DateFormatter().date(from: "2026-09-18T01:00:00Z")!
    private let seoul = TimeZone(identifier: "Asia/Seoul")!

    func testToolStatusSeparatesNotCalledFromEmpty() {
        XCTAssertEqual(Task.AnswerContext(action: .historyRecall, result: nil, now: now, timeZone: seoul).toolStatus,
                       "not_requested")
        XCTAssertEqual(Task.AnswerContext(action: .scheduleLookup, result: .schedules([]), now: now, timeZone: seoul).toolStatus,
                       "success_empty")
        XCTAssertEqual(
            Task.AnswerContext(action: .scheduleLookup,
                               result: .schedules([.init(title: "배포 점검", date: "2026-09-18", time: "15:00")]),
                               now: now, timeZone: seoul).toolStatus,
            "success"
        )
    }

    /// 키 순서와 값 모양이 평가기의 `answer_context` 와 같아야 한다.
    func testContextJSONMatchesEvaluatorShape() {
        let context = Task.AnswerContext(
            action: .scheduleLookup,
            result: .schedules([.init(title: "배포 점검", date: "2026-09-18", time: "15:00")]),
            now: now, timeZone: seoul
        )
        XCTAssertEqual(
            context.jsonText,
            #"{"current_time": "2026-09-18T10:00:00+09:00", "timezone": "Asia/Seoul", "current_weekday": "금요일", "action": "schedule_lookup", "source": "schedule_repository", "tool_status": "success", "result": [{"title": "배포 점검", "date": "2026-09-18", "time": "15:00"}]}"#
        )
    }

    func testAnswerInputCarriesRulesContextAndMessage() {
        let context = Task.AnswerContext(action: .conversation, result: nil, now: now, timeZone: seoul)
        let input = Task.answerInput(userMessage: "오늘 좀 지치네", context: context)
        XCTAssertTrue(input.hasPrefix(Task.answerRules))
        XCTAssertTrue(input.contains("앱 참고 데이터:\n" + context.jsonText))
        XCTAssertTrue(input.hasSuffix("사용자: 오늘 좀 지치네"))
    }
}
