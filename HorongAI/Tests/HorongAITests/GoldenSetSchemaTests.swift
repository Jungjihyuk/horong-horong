import XCTest
@testable import HorongAI

/// 골든셋 **파일 자체**를 검사한다. 모델은 안 부른다.
///
/// 정답지가 틀려 있으면 모델 점수는 아무 뜻이 없다. 실제로 그런 일이 있었다 —
/// `traps` 에 `expectedGroups` 의 분리를 그대로 베껴 적어 두고 «모델이 함정을 밟았다» 고
/// 집계한 케이스가 3건 있었다(2026-08-21).
///
/// 사람이 손으로 쓰는 파일이라 **규칙은 기계가 지켜야 한다.**
final class GoldenSetSchemaTests: XCTestCase {

    private func goldenCases() throws -> [GoldenSet.Case] {
        guard let goldenDirectory = TestRepository.goldenDirectory() else {
            throw XCTSkip("골든셋 폴더를 찾지 못했다")
        }
        let cases = try GoldenSet.load(goldenDirectory: goldenDirectory)
        try XCTSkipIf(cases.isEmpty, "골든셋 케이스가 없다")
        return cases
    }

    // MARK: - 주 경계

    /// **주간 목표는 한 주를 넘지 않는다.**
    ///
    /// 서로 다른 주에 걸린 할일을 한 주간 목표로 묶으면, 이번 주에 끝낼 수 없는 것을
    /// 이번 주 목표라고 부르는 셈이 된다.
    ///
    /// 날짜가 하나도 없는 할일은 **면제**다 — 언제든 할 수 있으니 주를 넘길 수가 없다.
    func testWeeklyGroupsStayWithinOneWeek() throws {
        for goldenCase in try goldenCases() {
            let byID = Dictionary(uniqueKeysWithValues: goldenCase.memos.map { ($0.id, $0) })

            for group in goldenCase.expectedGroups where group.type == .weekly {
                let weeks = Set(
                    group.memos
                        .compactMap { byID[$0]?.scheduledDate }
                        .map { GoldenSet.weekStart(of: $0) }
                )
                XCTAssertLessThanOrEqual(
                    weeks.count, 1,
                    """
                    \(goldenCase.caseName) / «\(group.title)»: \
                    한 주간 목표가 \(weeks.count)개 주에 걸쳐 있다 — \(group.memos.joined(separator: ", "))
                    """
                )
            }
        }
    }

    /// 케이스의 «오늘» 이 적혀 있고 읽히는가. 없으면 «이번 주» 가 정해지지 않는다.
    func testEveryCaseDeclaresItsReferenceDate() throws {
        for goldenCase in try goldenCases() {
            XCTAssertNotNil(
                GoldenSet.date(goldenCase.referenceDate),
                "\(goldenCase.caseName): referenceDate 를 못 읽었다 — \(goldenCase.referenceDate)"
            )
        }
    }

    // MARK: - 가리키는 것이 실재하는가

    func testEveryReferencedIDExists() throws {
        for goldenCase in try goldenCases() {
            let known = Set(goldenCase.memos.map(\.id))

            for group in goldenCase.expectedGroups {
                for id in group.memos where !known.contains(id) {
                    XCTFail("\(goldenCase.caseName) / «\(group.title)»: 없는 id \(id)")
                }
            }
            for trap in goldenCase.traps ?? [] {
                for id in trap.groups.flatMap({ $0 }) where !known.contains(id) {
                    XCTFail("\(goldenCase.caseName): 함정이 없는 id \(id) 를 가리킨다")
                }
            }
        }
    }

    // MARK: - 묶음이 묶음다운가

    /// 묶음에는 **제목이 붙어야 한다.** 제목을 못 붙이면 그건 묶음이 아니다(라벨링 가이드).
    /// 그리고 혼자는 묶음이 아니다 — 쌍이 안 나와 채점에도 안 잡힌다.
    func testEveryExpectedGroupIsNamedAndHasAtLeastTwoMemos() throws {
        for goldenCase in try goldenCases() {
            for group in goldenCase.expectedGroups {
                XCTAssertFalse(
                    group.title.trimmingCharacters(in: .whitespaces).isEmpty,
                    "\(goldenCase.caseName): 제목 없는 묶음 — \(group.memos.joined(separator: ", "))"
                )
                XCTAssertGreaterThanOrEqual(
                    group.memos.count, 2,
                    "\(goldenCase.caseName) / «\(group.title)»: 혼자는 묶음이 아니다"
                )
            }
        }
    }

    /// `cases/weekly/` 에는 주간 정답만 있어야 한다. 월간은 입력 자체가 달라 여기 못 들어온다.
    func testWeeklyFolderHoldsOnlyWeeklyGroups() throws {
        for goldenCase in try goldenCases() {
            for group in goldenCase.expectedGroups {
                XCTAssertEqual(
                    group.type, .weekly,
                    "\(goldenCase.caseName) / «\(group.title)»: weekly 폴더에 \(group.type.rawValue) 가 있다"
                )
            }
        }
    }

    // MARK: - 함정이 정답과 싸우지 않는가

    /// 함정이 **정답 쌍을 금지하면 모순**이다. 모델이 맞혀도 감점된다.
    func testTrapsNeverForbidACorrectPair() throws {
        for goldenCase in try goldenCases() {
            let correct = PairEvaluator.pairs(ofAll: goldenCase.expectedMemoGroups(of: .weekly))
            let forbidden = PairEvaluator.pairs(ofAllTraps: goldenCase.traps ?? [])
            let contradiction = correct.intersection(forbidden)

            XCTAssertTrue(
                contradiction.isEmpty,
                "\(goldenCase.caseName): 함정이 정답 쌍을 금지한다 — \(contradiction.sorted().joined(separator: ", "))"
            )
        }
    }

    /// **정답만으로 표현되는 것을 함정에 또 적지 않는다.**
    ///
    /// `expectedGroups` 가 `[A, B]` 라는 건 그 자체로 «A 와 B 는 별개» 라는 뜻이고,
    /// 둘이 합쳐지면 precision 이 이미 세게 깎인다. 같은 말을 함정에 또 적으면
    /// 정답 묶음이 여럿인 케이스마다 붙는 상투구가 되어 «골라 적는다» 는 뜻이 사라진다.
    func testTrapsDoNotRestateTheAnswerKeysOwnSeparation() throws {
        for goldenCase in try goldenCases() {
            let answers = goldenCase.expectedMemoGroups(of: .weekly).map(Set.init)

            for trap in goldenCase.traps ?? [] {
                let groups = trap.groups.filter { !$0.isEmpty }.map(Set.init)
                guard groups.count >= 2 else { continue }
                // 함정의 묶음이 전부 정답 묶음 그대로면, 정답이 이미 하는 말을 반복한 것이다.
                let allRestated = groups.allSatisfy { group in answers.contains(group) }
                XCTAssertFalse(
                    allRestated,
                    """
                    \(goldenCase.caseName): 정답 묶음의 분리를 함정에 그대로 옮겨 적었다 — \
                    \(trap.groups.map { $0.joined(separator: "+") }.joined(separator: " vs "))
                    """
                )
            }
        }
    }
}
