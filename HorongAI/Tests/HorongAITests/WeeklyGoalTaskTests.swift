import XCTest
@testable import HorongAI

/// 주간 목표 태스크의 특성화 테스트 — **입력 고르기 · 직렬화 · 파싱**.
///
/// 원래 앱 테스트(`GoalSuggestionParserTests` · `GoalSuggestionRegressionTests`)에 있었다.
/// 재는 대상이 전부 패키지 코드인데 확인하려고 앱을 통째로 빌드하고 있었다.
/// 여기서는 `swift test` 로 0.04초에 돈다.
///
/// **앱에 남긴 것**: 파싱 결과에 앱이 덧붙이는 것(공급자 도장 `source`, 이유 72자 컷)과
/// 룰 기반 폴백. 셋 다 패키지가 모르는 앱 관심사다.
@available(macOS 26.0, *)
final class WeeklyGoalTaskTests: XCTestCase {

    func testParsesPerMemoGuidanceInsteadOfTreatingItAsAnEmptySuggestion() {
        let first = WeeklyGoalTask.Memo(id: UUID(), content: "취업 준비", icon: "💼", date: Date())
        let second = WeeklyGoalTask.Memo(id: UUID(), content: "지원서", icon: "📄", date: Date())
        let outcome = WeeklyGoalTask.parse(
            """
            {"resultType":"guidance","guidance":[
              {"items":[1],"missing":["specific","measurable"],"suggestion":"지원 직무와 지원할 공고를 정해보세요."},
              {"items":[2],"missing":["specific"],"suggestion":"지원 기업과 작성할 문항을 정해보세요."}
            ]}
            """,
            memos: [first, second],
            allowedIDs: [first.id, second.id],
            suggestionCount: 3,
            maxMemoCount: 3
        )

        guard case .guidance(let guidance) = outcome.result else {
            return XCTFail("정보 부족 응답이 guidance 결과로 전달되지 않았다")
        }
        XCTAssertTrue(outcome.drafts.isEmpty)
        XCTAssertEqual(guidance.map(\.inputID), [first.id, second.id])
        XCTAssertEqual(guidance[0].missing, ["specific", "measurable"])
    }

    private func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "%08X-0000-0000-0000-000000000000", n)) ?? UUID()
    }

    private func memo(
        _ content: String,
        id: UUID = UUID(),
        startDate: Date? = nil,
        deadline: Date? = nil,
        isCompleted: Bool = false
    ) -> WeeklyGoalTask.Memo {
        WeeklyGoalTask.Memo(
            id: id,
            content: content,
            icon: "📝",
            date: Date(timeIntervalSince1970: 1_785_000_000),
            startDate: startDate,
            deadline: deadline,
            isCompleted: isCompleted
        )
    }

    // MARK: - 프롬프트 예산
    // 인시던트 2026-07-31: 프롬프트가 커지면 추론이 통째로 거부된다
    // (에러명은 unsupportedLanguageOrLocale 로 오분류되어 나온다).

    /// AFM 예산. 앱의 `Constants.achievementPromptCharacterBudget(for: .appleFoundation)` 과 같은 값이다.
    private let appleFoundationBudget = 4_000

    func testPromptStaysWithinBudgetEvenWithManyLongMemos() {
        let memos = (0..<40).map { i in
            memo(String(repeating: "긴 메모 본문 예시 ", count: 12) + "\(i)")
        }
        let selected = WeeklyGoalTask.memosWithinPromptBudget(
            memos, suggestionCount: 4, maxMemoCount: 5, budget: appleFoundationBudget
        )
        let text = WeeklyGoalTask.prompt(for: selected, suggestionCount: 4, maxMemoCount: 5)

        XCTAssertLessThanOrEqual(text.count, appleFoundationBudget, "프롬프트가 예산을 넘으면 추론이 거부된다")
        XCTAssertLessThan(selected.count, memos.count, "예산을 맞추려면 일부는 잘려야 한다")
    }

    func testBudgetCutKeepsAtLeastTwoMemos() {
        // 묶으려면 최소 2개가 필요하다. 예산을 넘더라도 1개까지 줄이면 추천 자체가 불가능해진다.
        let huge = String(repeating: "아주 긴 본문 ", count: 400)
        let memos = [memo(huge), memo(huge), memo(huge)]
        let selected = WeeklyGoalTask.memosWithinPromptBudget(
            memos, suggestionCount: 4, maxMemoCount: 5, budget: appleFoundationBudget
        )
        XCTAssertGreaterThanOrEqual(selected.count, 2)
    }

    func testShortInputIsNotTrimmed() {
        let memos = (0..<3).map { memo("짧은 할일 \($0)") }
        let selected = WeeklyGoalTask.memosWithinPromptBudget(
            memos, suggestionCount: 4, maxMemoCount: 5, budget: appleFoundationBudget
        )
        XCTAssertEqual(selected.count, 3, "예산에 여유가 있으면 자르지 않는다")
    }

    // MARK: - 직렬화 다이어트
    // 값이 없는 필드를 "없음"으로 채우면 메모당 30자 이상을 정보 없이 소비한다.

    func testEmptyDateFieldsAreOmitted() {
        let text = WeeklyGoalTask.prompt(for: [memo("아침 러닝")], suggestionCount: 4, maxMemoCount: 5)
        XCTAssertFalse(text.contains("startDate:"), "startDate가 없으면 줄 자체를 넣지 않는다")
        XCTAssertFalse(text.contains("deadline:"), "deadline이 없으면 줄 자체를 넣지 않는다")
        XCTAssertFalse(text.contains("없음"), "빈 값을 문자열로 채우지 않는다")
        XCTAssertTrue(text.contains("[1] 아침 러닝"), "번호와 첫 줄이 깔끔하게 들어간다")
    }

    func testPresentDateFieldsAreIncluded() {
        let due = Date(timeIntervalSince1970: 1_785_600_000)
        let text = WeeklyGoalTask.prompt(
            for: [memo("보고서 제출", deadline: due)],
            suggestionCount: 4,
            maxMemoCount: 5
        )
        XCTAssertTrue(text.contains("마감"), "마감일이 있으면 인라인으로 전달한다")
    }

    func testCompletedFlagOmittedWhenFalse() {
        let text = WeeklyGoalTask.prompt(for: [memo("아침 러닝")], suggestionCount: 4, maxMemoCount: 5)
        XCTAssertFalse(text.contains("완료됨"))
    }

    func testFirstLineOnlyIsExtracted() {
        let memoWithMultiLines = memo("이력서 작성\n회의록 전문: 어쩌고 저쩌고\nhttps://example.com/link")
        let text = WeeklyGoalTask.prompt(for: [memoWithMultiLines], suggestionCount: 4, maxMemoCount: 5)
        XCTAssertTrue(text.contains("[1] 이력서 작성"))
        XCTAssertFalse(text.contains("회의록 전문"))
        XCTAssertFalse(text.contains("https://example.com"))
    }

    func testParsesIntegerItemIndexes() {
        let m1 = memo("이력서 작성", id: uuid(1))
        let m2 = memo("포트폴리오 배포", id: uuid(2))
        let jsonText = """
        {"suggestions": [{"title": "취업 준비", "reason": "함께 준비", "items": [1, 2], "emoji": "🎯"}]}
        """
        let outcome = WeeklyGoalTask.parse(
            jsonText,
            memos: [m1, m2],
            allowedIDs: Set([uuid(1), uuid(2)]),
            suggestionCount: 3,
            maxMemoCount: 3
        )
        XCTAssertEqual(outcome.drafts.count, 1)
        XCTAssertEqual(outcome.drafts.first?.title, "취업 준비")
        XCTAssertEqual(outcome.drafts.first?.memoIDs, [uuid(1), uuid(2)])
        XCTAssertEqual(outcome.drafts.first?.criterion, "연결한 할일 2개 완료")
    }

    /// **id 를 배열로 한 겹 더 감싸 보내는 모델이 있다.**
    ///
    /// 실측(2026-08-19/20) — `gemma-4-e4b` 계열이 `"items": [[16],[17],[18]]` 처럼 냈다.
    /// mlx·ollama 양쪽에서 5건. 내용은 멀쩡했는데(묶음 4~5개가 제대로 나왔다) 껍데기 한 겹
    /// 때문에 `typeMismatch:Index 0` 로 **통째로 버려졌다.**
    func testParsesItemIndexesWrappedInArrays() {
        let m1 = memo("이력서 작성", id: uuid(1))
        let m2 = memo("포트폴리오 배포", id: uuid(2))
        let jsonText = """
        {"suggestions": [{"title": "취업 준비", "reason": "함께 준비", "items": [[1], [2]], "emoji": "🎯"}]}
        """
        let outcome = WeeklyGoalTask.parse(
            jsonText,
            memos: [m1, m2],
            allowedIDs: Set([uuid(1), uuid(2)]),
            suggestionCount: 3,
            maxMemoCount: 3
        )
        XCTAssertEqual(outcome.drafts.first?.memoIDs, [uuid(1), uuid(2)])
    }

    /// 한 껍데기 안에 여럿을 담아 보내도 잃지 않는다. `[[1, 2]]` 도 `[1, 2]` 로 편다.
    func testParsesMultipleIDsInsideOneWrapper() {
        let m1 = memo("이력서 작성", id: uuid(1))
        let m2 = memo("포트폴리오 배포", id: uuid(2))
        let jsonText = """
        {"suggestions": [{"title": "취업 준비", "reason": "함께 준비", "items": [[1, 2]], "emoji": "🎯"}]}
        """
        let outcome = WeeklyGoalTask.parse(
            jsonText,
            memos: [m1, m2],
            allowedIDs: Set([uuid(1), uuid(2)]),
            suggestionCount: 3,
            maxMemoCount: 3
        )
        XCTAssertEqual(outcome.drafts.first?.memoIDs, [uuid(1), uuid(2)])
    }

    /// 섞여 와도 받는다. 모델이 일관되게 감싸리라는 보장이 없다.
    func testParsesMixedWrappedAndBareIDs() {
        let m1 = memo("이력서 작성", id: uuid(1))
        let m2 = memo("포트폴리오 배포", id: uuid(2))
        let jsonText = """
        {"suggestions": [{"title": "취업 준비", "reason": "함께 준비", "items": [1, [2]], "emoji": "🎯"}]}
        """
        let outcome = WeeklyGoalTask.parse(
            jsonText,
            memos: [m1, m2],
            allowedIDs: Set([uuid(1), uuid(2)]),
            suggestionCount: 3,
            maxMemoCount: 3
        )
        XCTAssertEqual(outcome.drafts.first?.memoIDs, [uuid(1), uuid(2)])
    }

    // MARK: - 파싱

    private func json(_ items: String) -> String {
        "{\"suggestions\": [\(items)]}"
    }

    private func item(
        title: String = "주간 보고서 마무리",
        reason: String = "같은 결과물로 이어진다",
        memoIDs: [Int],
        scheduleText: String = "월/수에 나눠 진행",
        criterion: String = "연결한 할일 2개 완료",
        emoji: String? = "📝"
    ) -> String {
        let ids = memoIDs.map { "\"\(uuid($0).uuidString)\"" }.joined(separator: ", ")
        let emojiField = emoji.map { "\"emoji\": \"\($0)\"" } ?? "\"emoji\": null"
        return """
        {"title": "\(title)", "reason": "\(reason)", "memoIDs": [\(ids)],
         "scheduleText": "\(scheduleText)", "criterion": "\(criterion)", \(emojiField)}
        """
    }

    private func parse(
        _ text: String,
        allowed: [Int] = [1, 2, 3, 4, 5],
        suggestionCount: Int = 3,
        maxMemoCount: Int = 3
    ) -> [GoalSuggestionDraft] {
        WeeklyGoalTask.parse(
            text,
            allowedIDs: Set(allowed.map(uuid)),
            suggestionCount: suggestionCount,
            maxMemoCount: maxMemoCount
        ).drafts
    }

    func testParsesValidSuggestion() {
        let result = parse(json(item(memoIDs: [1, 2])))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "주간 보고서 마무리")
        XCTAssertEqual(result.first?.memoIDs.count, 2)
        XCTAssertEqual(result.first?.targetValueText, "2개")
    }

    /// 모델이 JSON 앞뒤에 설명을 붙여도 살려낸다 — 첫 `{` 부터 마지막 `}` 까지만 자른다.
    func testExtractsJSONFromSurroundingText() {
        let text = "알겠습니다! 아래가 제안입니다.\n\(json(item(memoIDs: [1, 2])))\n도움이 되었길 바랍니다."
        XCTAssertEqual(parse(text).count, 1)
    }

    // MARK: - 방어 경로 다섯 갈래

    /// ① JSON 이 깨지면 빈 배열. 예외를 던지지 않는다.
    func testBrokenJSONReturnsEmpty() {
        XCTAssertTrue(parse("이건 JSON 이 아니다").isEmpty)
        XCTAssertTrue(parse("{\"suggestions\": [").isEmpty)
    }

    /// 깨졌다는 사실이 진단에 남아야 "모델이 적게 냄"과 구분된다.
    func testBrokenJSONIsReportedInDiagnostics() {
        let outcome = WeeklyGoalTask.parse(
            "이건 JSON 이 아니다", allowedIDs: [], suggestionCount: 3, maxMemoCount: 3
        )
        guard case let .decodeFailed(characters, reason) = outcome.diagnostics else {
            return XCTFail("디코드 실패가 진단에 안 남았다")
        }
        XCTAssertEqual(characters, "이건 JSON 이 아니다".count)
        XCTAssertEqual(reason, "noJSON", "JSON 을 아예 안 낸 경우")
    }

    /// **필수 키가 하나만 빠져도 제안 전체가 버려진다.** id 는 다섯 갈래로 방어하면서
    /// 필수 키(title, reason) 누락 시 디코드 실패가 명확한 이유로 남는다.
    func testMissingRequiredKeyLosesEverythingAndSaysWhich() {
        // reason 이 없다.
        let text = """
        {"suggestions": [{"title": "주간 보고서 마무리",
         "items": [1, 2], "scheduleText": "월/수"}]}
        """

        let outcome = WeeklyGoalTask.parse(
            text, allowedIDs: Set([1, 2].map(uuid)), suggestionCount: 3, maxMemoCount: 3
        )

        XCTAssertTrue(outcome.drafts.isEmpty, "필수 키 누락 시 제안이 비워진다")
        guard case let .decodeFailed(_, reason) = outcome.diagnostics else {
            return XCTFail("디코드 실패가 진단에 안 남았다")
        }
        XCTAssertEqual(reason, "missingKey:reason", "어느 키가 빠졌는지 남아야 원인을 안다")
    }

    /// 응답이 중간에 잘리면 `{` 만 있고 `}` 가 없다. 토큰 상한을 의심할 자리라 따로 가른다.
    func testTruncatedResponseIsDistinguishedFromMalformed() {
        let truncated = WeeklyGoalTask.parse(
            "{\"suggestions\": [{\"title\": \"보고서", allowedIDs: [], suggestionCount: 3, maxMemoCount: 3
        )
        // 괄호는 둘 다 있는데 문법이 깨진 경우
        let malformed = WeeklyGoalTask.parse(
            "{\"suggestions\": [{\"title\": }", allowedIDs: [], suggestionCount: 3, maxMemoCount: 3
        )

        guard case let .decodeFailed(_, truncatedReason) = truncated.diagnostics,
              case let .decodeFailed(_, malformedReason) = malformed.diagnostics else {
            return XCTFail("디코드 실패가 진단에 안 남았다")
        }
        XCTAssertEqual(truncatedReason, "truncated")
        XCTAssertEqual(malformedReason, "malformed")
    }

    /// ② 허용 목록에 없는 id 는 버린다. 모델이 id 를 지어내는 일이 있다.
    func testDropsUnknownIDs() {
        let text = json(item(memoIDs: [1, 2, 99]))
        XCTAssertEqual(parse(text, allowed: [1, 2]).first?.memoIDs.count, 2)
    }

    /// id 를 걸러낸 결과가 2개 미만이면 **제안 자체를 버린다.**
    func testDropsSuggestionWhenTooFewValidIDs() {
        let text = json(item(memoIDs: [1, 99]))
        XCTAssertTrue(parse(text, allowed: [1]).isEmpty)
    }

    /// ③ 같은 할일을 두 제안에 넣으면 뒤쪽에서 제거된다. 결과가 2개 미만이면 그 제안이 버려진다.
    func testDoesNotReuseSameMemoAcrossSuggestions() {
        let text = json([
            item(title: "첫째", memoIDs: [1, 2]),
            item(title: "둘째", memoIDs: [1, 2])
        ].joined(separator: ", "))

        let result = parse(text)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "첫째")
    }

    /// ④ 한 제안에 `maxMemoCount` 를 넘게 넣으면 초과분을 버린다.
    func testTrimsToMaxMemoCount() {
        let text = json(item(memoIDs: [1, 2, 3, 4]))
        XCTAssertEqual(parse(text, maxMemoCount: 3).first?.memoIDs.count, 3)
    }

    /// ⑤ 제안 개수도 상한을 넘으면 잘린다.
    func testTrimsToSuggestionCount() {
        let text = json([
            item(title: "하나", memoIDs: [1, 2]),
            item(title: "둘", memoIDs: [3, 4]),
            item(title: "셋", memoIDs: [5, 1])
        ].joined(separator: ", "))

        XCTAssertEqual(parse(text, suggestionCount: 2).count, 2)
    }

    /// `kept` 는 개수 상한으로 자르기 **전** 값이다. 자른 뒤 값을 쓰면
    /// "모델이 많이 냈는데 우리가 잘랐다"가 로그에서 사라진다.
    func testDiagnosticsReportKeptBeforeTrimming() {
        let text = json([
            item(title: "하나", memoIDs: [1, 2]),
            item(title: "둘", memoIDs: [3, 4]),
            item(title: "셋", memoIDs: [5, 1])
        ].joined(separator: ", "))

        let outcome = WeeklyGoalTask.parse(
            text, allowedIDs: Set([1, 2, 3, 4, 5].map(uuid)), suggestionCount: 2, maxMemoCount: 3
        )
        guard case .decoded(let modelReturned, let kept, _, _, _, _, _) = outcome.diagnostics else {
            return XCTFail("파싱 진단이 안 남았다")
        }
        XCTAssertEqual(modelReturned, 3)
        XCTAssertEqual(kept, 2, "셋째는 남은 id 가 모자라 파서가 버렸다")
        XCTAssertEqual(outcome.drafts.count, 2)
    }

    // MARK: - 빈 값 채우기

    /// 모델이 빈 문자열을 주면 사람이 읽을 수 있는 기본값으로 메운다.
    func testFillsEmptyFieldsWithDefaults() {
        let text = json(item(title: "", memoIDs: [1, 2], scheduleText: "", criterion: "", emoji: nil))
        let draft = parse(text).first

        XCTAssertEqual(draft?.title, "추천 목표")
        XCTAssertEqual(draft?.scheduleText, "이번 주에 나눠 진행")
        XCTAssertEqual(draft?.criterion, "연결한 할일 2개 완료")
        XCTAssertEqual(draft?.emoji, "🎯")
    }

    /// 이모지를 여러 글자 보내면 **첫 글자만** 쓴다. 목록에 두 칸을 차지하면 정렬이 깨진다.
    func testKeepsOnlyFirstEmojiCharacter() {
        let text = json(item(memoIDs: [1, 2], emoji: "📝✅🎯"))
        XCTAssertEqual(parse(text).first?.emoji, "📝")
    }

    /// 이유는 **자르지 않고** 그대로 둔다. 얼마나 줄일지는 보여주는 화면이 정한다.
    func testReasonIsNotTruncatedByTheTask() {
        let long = String(repeating: "가", count: 200)
        let text = json(item(reason: long, memoIDs: [1, 2]))

        XCTAssertEqual(parse(text).first?.reason, long)
    }

    // MARK: - extractJSONObject 특성화 테스트

    /// 모델이 `<think> ... </think>` 사고 과정을 함께 출력해도 제거하고 JSON만 추출한다.
    func testExtractJSONObjectRemovesThinkBlocks() {
        let raw = "<think>사용자의 메모를 분석해서 목표를 만듭니다.</think>{\"suggestions\": []}"
        let extracted = GoalSuggestionPayload.extractJSONObject(from: raw)
        XCTAssertEqual(extracted, "{\"suggestions\": []}")
    }

    /// 마크다운 코드 블록(```json ... ```)으로 감싸진 JSON을 정상 추출한다.
    func testExtractJSONObjectExtractsFromMarkdownCodeBlock() {
        let raw = """
        네, 목표 추천 결과입니다:
        ```json
        {"suggestions": []}
        ```
        확인해 주세요.
        """
        let extracted = GoalSuggestionPayload.extractJSONObject(from: raw)
        XCTAssertEqual(extracted, "{\"suggestions\": []}")
    }

    /// 언어 태그 없는 코드 블록(``` ... ```)도 정상 추출한다.
    func testExtractJSONObjectExtractsFromGenericCodeBlock() {
        let raw = """
        ```
        {"suggestions": []}
        ```
        """
        let extracted = GoalSuggestionPayload.extractJSONObject(from: raw)
        XCTAssertEqual(extracted, "{\"suggestions\": []}")
    }

    /// `<think>` 블록과 코드 블록이 혼합된 경우에도 온전한 JSON만 추출한다.
    func testExtractJSONObjectHandlesCombinedThinkAndCodeBlock() {
        let raw = """
        <think>
        분석 중...
        </think>
        다음은 JSON입니다:
        ```json
        {
          "suggestions": []
        }
        ```
        """
        let extracted = GoalSuggestionPayload.extractJSONObject(from: raw)
        XCTAssertEqual(extracted, "{\n  \"suggestions\": []\n}")
    }

    // MARK: - 생성 타임아웃

    /// 생성 작업이 타임아웃 시간을 초과하면 CancellationError로 중단되고 diagnostics에 failure가 기록된다.
    func testRunTimesOutWhenGenerationExceedsLimit() async {
        let memos = [memo("할일 1", id: uuid(1)), memo("할일 2", id: uuid(2))]
        let outcome = await WeeklyGoalTask.run(
            memos: memos,
            suggestionCount: 2,
            maxMemoCount: 3,
            inputLimit: 10,
            budget: 4000,
            timeoutInterval: 0.05,
            generate: { _, _ in
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5초 대기
                return "{\"suggestions\": []}"
            }
        )

        XCTAssertTrue(outcome.drafts.isEmpty)
        guard case .generationFailed(let error) = outcome.diagnostics else {
            return XCTFail("타임아웃 시 generationFailed 진단이 남아야 한다")
        }
        XCTAssertTrue(error is CancellationError)
    }
}
