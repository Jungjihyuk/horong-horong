import HorongAI
import XCTest
@testable import 호롱호롱

/// 프롬프트 문자열의 **바이트 단위 스냅샷**.
///
/// S4 에서 프롬프트를 `Tasks/` 와 `.md` 로 옮긴다. 옮기다 보면 들여쓰기·줄바꿈·마지막 개행이
/// 쉽게 달라지는데, 그러면 모델 출력이 실제로 나빠질 수 있다. 문제는 **실모델 점수로는 그걸 못 잡는다**는
/// 것이다 — 같은 프롬프트로도 매번 다르게 답하기 때문이다.
/// (참고: `docs/.../Bug/incident-20260813-nondeterministic-model-breaks-regression-check.md`)
///
/// 그래서 모델을 부르지 않고 **문자열만** 비교한다. 스냅샷이 바뀌면 의도한 변경인지 눈으로 확인하고,
/// 맞으면 `touch Evals/.record-prompts` 후 다시 떠서 갱신한다.
///
/// 환경변수가 아니라 마커 파일을 쓰는 이유는 `xcodebuild` 가 환경변수를 테스트 프로세스로
/// 전달하지 않기 때문이다 — 골든셋(`GoalSuggestionEvalTests`)이 `.run-golden` 을 쓰는 것과 같은 사정이다.
final class PromptSnapshotTests: XCTestCase {

    // MARK: - 고정 입력

    /// 날짜가 들어가는 프롬프트가 있으므로 시각을 고정한다. 안 그러면 매일 스냅샷이 깨진다.
    private static let fixedDate = Date(timeIntervalSince1970: 1_770_000_000)

    private func memo(
        _ shortID: String,
        _ content: String,
        icon: String,
        completed: Bool = false
    ) -> WeeklyGoalTask.Memo {
        WeeklyGoalTask.Memo(
            id: Self.deterministicUUID(for: shortID),
            content: content,
            icon: icon,
            date: Self.fixedDate,
            startDate: nil,
            deadline: nil,
            isCompleted: completed
        )
    }

    private var sampleMemos: [WeeklyGoalTask.Memo] {
        [
            memo("m1", "주간 보고서 초안 작성", icon: "doc"),
            memo("m2", "주간 보고서 검토 요청", icon: "doc"),
            memo("m3", "러닝 30분", icon: "figure.run", completed: true),
        ]
    }

    private var sampleGoals: [MonthlyGoalTask.Goal] {
        [
            MonthlyGoalTask.Goal(
                id: Self.deterministicUUID(for: "g1"),
                title: "주간 리포트 자동화",
                emoji: "📝",
                rule: "연결한 할일 3개 완료",
                done: 2,
                total: 3,
                sourceMemoIDs: [
                    Self.deterministicUUID(for: "m1"),
                    Self.deterministicUUID(for: "m2"),
                ],
                roleName: "기획자",
                vision: "반복 업무를 줄인다"
            ),
            MonthlyGoalTask.Goal(
                id: Self.deterministicUUID(for: "g2"),
                title: "체력 회복 루틴",
                emoji: "🏃",
                rule: "주 3회 운동",
                done: 1,
                total: 3,
                sourceMemoIDs: [Self.deterministicUUID(for: "m3")],
                roleName: "",
                vision: ""
            ),
        ]
    }

    // MARK: - 컴패니언 대화

    func testCompanionInstructionsSnapshot() throws {
        let rendered = CompanionPromptTemplate.instructions(
            for: .hororong,
            profile: .empty
        )
        try assertSnapshot(rendered, named: "companion_chat_instructions")
    }

    /// 사용자 정보가 있으면 프롬프트 뒤에 붙는다. 이 부분이 안전 필터에 걸리기 쉬워
    /// 문구가 바뀌면 응답이 통째로 막힐 수 있다.
    func testCompanionInstructionsWithProfileSnapshot() throws {
        let rendered = CompanionPromptTemplate.instructions(
            for: .hororong,
            profile: CompanionUserProfile(nickname: "지혁", note: "아침에 집중이 잘 된다")
        )
        try assertSnapshot(rendered, named: "companion_chat_instructions_with_profile")
    }

    // MARK: - 컴패니언 모델 입력 (근거 조립)

    // S5 에서 `modelInput` 이 `Tasks/CompanionChat/` 으로 나가고 인자가 `String?` 둘에서
    // `[Evidence]` 로 바뀐다. 지금 이걸 지키는 테스트는 전부 `contains(...)` 라
    // **지시 문구가 통째로 바뀌어도 통과한다** — 빈 줄 하나, 구분자 `\n\n`, 문장 순서도 안 본다.
    // 근거를 넣었을 때의 "이 안에서만 답하라" 지시는 한 글자만 달라져도 답이 흔들리는 자리다.

    private func evidence(_ text: String, source: String) -> Evidence {
        Evidence(id: "\(source).snapshot", source: source, text: text)
    }

    /// 할일 질문 경로. 목록을 나열하지 말라는 지시가 붙는다.
    func testCompanionModelInputWithTaskDigestSnapshot() throws {
        let rendered = CompanionChatTask.modelInput(
            userMessage: "오늘 할일 뭐 있어?",
            taskDigest: "오늘 등록된 할일:\n- 주간 보고서 초안\n- 러닝 30분"
        )
        try assertSnapshot(rendered, named: "companion_model_input_task_digest")
    }

    /// 앱 사실만 근거로 들어간 경로.
    func testCompanionModelInputWithAppFactsSnapshot() throws {
        let rendered = CompanionChatTask.modelInput(
            userMessage: "무슨 테마가 있어?",
            evidence: [
                evidence("팝오버 테마: 따뜻한 등불, 게임 픽셀\n지금 쓰는 테마: 따뜻한 등불", source: "appFacts")
            ]
        )
        try assertSnapshot(rendered, named: "companion_model_input_app_facts")
    }

    /// 앱 사실과 설명서 섹션이 함께 들어간 경로. 둘을 잇는 구분자가 이 스냅샷의 핵심이다.
    func testCompanionModelInputWithFactsAndGuideSnapshot() throws {
        let rendered = CompanionChatTask.modelInput(
            userMessage: "테마 어떻게 바꿔?",
            evidence: [
                evidence("관련 설정은 설정 → 외관 에 있다.", source: "settingsIndex"),
                evidence("7. 설정 창\n외관 탭에서 테마를 바꿉니다.", source: "guide"),
            ]
        )
        try assertSnapshot(rendered, named: "companion_model_input_facts_and_guide")
    }

    /// 출처 셋이 한 번에 걸린 경로. **S5d 에서 이음새가 바뀐 자리가 여기다** —
    /// 예전에는 앱 사실과 설정 위치가 `\n` 으로 붙어 있었고 이제 빈 줄로 띄운다.
    /// 조각이 하나뿐이면 차이가 안 드러나므로 여러 조각이 걸리는 경우를 따로 둔다.
    func testCompanionModelInputWithThreeSourcesSnapshot() throws {
        let rendered = CompanionChatTask.modelInput(
            userMessage: "테마 어떻게 바꿔?",
            evidence: [
                evidence("팝오버 테마: 따뜻한 등불, 게임 픽셀\n바꾸는 곳: 설정 → 외관 → 테마", source: "appFacts"),
                evidence("화면 모드: 라이트, 다크, 시스템", source: "appFacts"),
                evidence("관련 설정은 설정 → 외관 에 있다.", source: "settingsIndex"),
                evidence("7. 설정 창\n외관 탭에서 테마를 바꿉니다.", source: "guide"),
            ]
        )
        try assertSnapshot(rendered, named: "companion_model_input_three_sources")
    }

    // MARK: - 주간 목표 추천

    /// 프롬프트는 패키지가 만든다. 스냅샷은 **여기 모아 둔다** —
    /// 컴패니언·목표 추천 프롬프트를 한 자리에서 눈으로 대조할 수 있어야 하고,
    /// 픽스처(`Evals/fixtures/prompts/`)도 한 폴더에 있다.
    func testWeeklyGoalPromptSnapshot() throws {
        let rendered = WeeklyGoalTask.prompt(
            for: sampleMemos,
            suggestionCount: 3,
            maxMemoCount: 3
        )
        try assertSnapshot(rendered, named: "weekly_goal_suggestion")
    }

    // MARK: - 월간 목표 추천

    func testMonthlyGoalPromptSnapshot() throws {
        let rendered = MonthlyGoalTask.prompt(
            for: sampleGoals,
            suggestionCount: 2,
            maxGoalsPerSuggestion: 3
        )
        try assertSnapshot(rendered, named: "monthly_goal_suggestion")
    }

    // MARK: - 스냅샷 비교

    private func assertSnapshot(
        _ actual: String,
        named name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let url = try Self.snapshotDirectory().appendingPathComponent("\(name).txt")

        let marker = url.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".record-prompts")
        guard !FileManager.default.fileExists(atPath: marker.path) else {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try actual.write(to: url, atomically: true, encoding: .utf8)
            print("[snapshot] 기록: \(url.path)")
            return
        }

        guard let expected = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail(
                "스냅샷이 없다: \(url.path)\n"
                + "touch Evals/.record-prompts 후 테스트를 한 번 돌려 만들고, 내용을 눈으로 확인하고 커밋한다.",
                file: file, line: line
            )
            return
        }

        if actual != expected {
            XCTFail(
                """
                프롬프트가 바뀌었다: \(name)
                의도한 변경이면 touch Evals/.record-prompts 후 다시 떠서 갱신한다.

                --- 저장된 것 ---
                \(expected)
                --- 지금 것 ---
                \(actual)
                """,
                file: file, line: line
            )
        }
    }

    private static func snapshotDirectory() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Evals").path) {
                return url
                    .appendingPathComponent("Evals")
                    .appendingPathComponent("fixtures")
                    .appendingPathComponent("prompts")
            }
        }
        throw XCTSkip("리포지토리 루트를 찾지 못했다")
    }

    /// 짧은 id 에서 항상 같은 UUID 를 만든다. 실행마다 달라지면 스냅샷이 매번 깨진다.
    private static func deterministicUUID(for shortID: String) -> UUID {
        var bytes = Array(shortID.utf8.prefix(16))
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 16 - bytes.count))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
