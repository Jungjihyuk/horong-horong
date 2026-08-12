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
        icon: String? = nil,
        completed: Bool = false
    ) -> AchievementMemoSnapshot {
        AchievementMemoSnapshot(
            id: Self.deterministicUUID(for: shortID),
            content: content,
            icon: icon,
            date: Self.fixedDate,
            startDate: nil,
            deadline: nil,
            isCompleted: completed
        )
    }

    private var sampleMemos: [AchievementMemoSnapshot] {
        [
            memo("m1", "주간 보고서 초안 작성", icon: "doc"),
            memo("m2", "주간 보고서 검토 요청", icon: "doc"),
            memo("m3", "러닝 30분", icon: "figure.run", completed: true),
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

    // MARK: - 주간 목표 추천

    /// AFM 구현체가 프롬프트·파서를 겸하고 있어 `@available` 이 여기까지 따라온다.
    /// S4 에서 프롬프트가 `Tasks/` 로 나오면 이 제약도 사라진다.
    @available(macOS 26.0, *)
    func testWeeklyGoalPromptSnapshot() throws {
        let rendered = FoundationModelsGoalSuggestionProvider().prompt(
            for: sampleMemos,
            suggestionCount: 3,
            maxMemoCount: 3
        )
        try assertSnapshot(rendered, named: "weekly_goal_suggestion")
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
