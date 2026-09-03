import XCTest
@testable import 호롱호롱

/// 뽀모도로 후보를 고르는 규칙. **순수 함수라 저장소도 화면도 없이 검사한다.**
///
/// 예전에는 입력이 `@Model` 이라 이 규칙을 확인하려면 앱을 띄워야 했다.
final class PomodoroTaskCandidateTests: XCTestCase {
    private let calendar = Calendar.current

    private func memo(
        _ content: String,
        start: Date? = nil,
        deadline: Date? = nil,
        id: UUID = UUID()
    ) -> AchievementMemoDetail {
        AchievementMemoDetail(
            id: id,
            content: content,
            icon: nil,
            startDate: start,
            deadline: deadline,
            updatedAt: Date(),
            isCompleted: false
        )
    }

    private func day(_ offset: Int, hour: Int = 9, from now: Date) -> Date {
        let shifted = calendar.date(byAdding: .day, value: offset, to: now) ?? now
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: shifted) ?? shifted
    }

    /// 오늘 시작하는 일이면 후보다.
    func testTodayTaskIsCandidate() {
        let now = Date()
        let candidates = PomodoroTaskCandidateBuilder.candidates(
            memos: [memo("오늘 할 일", start: day(0, from: now))],
            goalLinkedMemoIDs: [],
            now: now
        )

        XCTAssertEqual(candidates.map(\.title), ["오늘 할 일"])
        XCTAssertTrue(candidates[0].isToday)
        XCTAssertFalse(candidates[0].isGoalLinked)
    }

    /// 오늘이 아니어도 **목표에 묶여 있으면** 후보다.
    func testGoalLinkedTaskIsCandidateEvenIfNotToday() {
        let now = Date()
        let id = UUID()
        let candidates = PomodoroTaskCandidateBuilder.candidates(
            memos: [memo("다음 주 할 일", start: day(7, from: now), id: id)],
            goalLinkedMemoIDs: [id],
            now: now
        )

        XCTAssertEqual(candidates.count, 1)
        XCTAssertFalse(candidates[0].isToday)
        XCTAssertTrue(candidates[0].isGoalLinked)
    }

    /// 오늘도 아니고 목표에도 안 묶였으면 후보가 아니다.
    func testUnrelatedTaskIsExcluded() {
        let now = Date()
        let candidates = PomodoroTaskCandidateBuilder.candidates(
            memos: [memo("다음 주 할 일", start: day(7, from: now))],
            goalLinkedMemoIDs: [],
            now: now
        )

        XCTAssertTrue(candidates.isEmpty)
    }

    /// 날짜가 없는 일은 «오늘» 이 아니다. 목표에 묶였을 때만 올라온다.
    func testUndatedTaskNeedsGoalLink() {
        let now = Date()
        let id = UUID()
        XCTAssertTrue(
            PomodoroTaskCandidateBuilder
                .candidates(memos: [memo("날짜 없음")], goalLinkedMemoIDs: [], now: now)
                .isEmpty
        )
        XCTAssertEqual(
            PomodoroTaskCandidateBuilder
                .candidates(memos: [memo("날짜 없음", id: id)], goalLinkedMemoIDs: [id], now: now)
                .count,
            1
        )
    }

    /// 시작과 마감이 둘 다 있으면 그 사이를 예상 소요 시간으로 준다.
    func testDurationComesFromStartAndDeadline() throws {
        let now = Date()
        let candidate = try XCTUnwrap(
            PomodoroTaskCandidateBuilder.candidates(
                memos: [memo("두 시간짜리", start: day(0, hour: 9, from: now), deadline: day(0, hour: 11, from: now))],
                goalLinkedMemoIDs: [],
                now: now
            ).first
        )

        XCTAssertEqual(candidate.durationMinutes, 120)
    }

    /// 마감이 시작보다 앞서면 소요 시간을 만들지 않는다 — 음수 시간이 보이면 안 된다.
    func testInvertedDatesHaveNoDuration() throws {
        let now = Date()
        let candidate = try XCTUnwrap(
            PomodoroTaskCandidateBuilder.candidates(
                memos: [memo("뒤집힘", start: day(0, hour: 11, from: now), deadline: day(0, hour: 9, from: now))],
                goalLinkedMemoIDs: [],
                now: now
            ).first
        )

        XCTAssertNil(candidate.durationMinutes)
    }

    /// 제목은 첫 줄만. 비어 있으면 대체 문구를 쓴다.
    func testTitleUsesFirstNonEmptyLine() throws {
        let now = Date()
        let candidates = PomodoroTaskCandidateBuilder.candidates(
            memos: [
                memo("\n\n진짜 제목\n본문", start: day(0, from: now)),
                memo("   \n  ", start: day(0, from: now))
            ],
            goalLinkedMemoIDs: [],
            now: now
        )

        XCTAssertEqual(candidates.map(\.title), ["진짜 제목", "제목 없는 할 일"])
    }

    /// 저장소가 준 순서를 **재정렬하지 않는다.** 사용자가 보는 순서가 그 순서다.
    func testOrderIsPreserved() {
        let now = Date()
        let memos = (0..<3).map { memo("할 일 \($0)", start: day(0, from: now)) }

        let candidates = PomodoroTaskCandidateBuilder.candidates(
            memos: memos,
            goalLinkedMemoIDs: [],
            now: now
        )

        XCTAssertEqual(candidates.map(\.id), memos.map(\.id))
    }
}
