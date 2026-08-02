import XCTest
@testable import 호롱호롱

/// 골든셋을 돌려 결과를 JSONL로 뱉는 **생성기**.
///
/// 채점은 여기서 하지 않는다. 추론은 느리고 채점 기준은 자주 바뀌므로,
/// 실행(느림)과 채점(빠름)을 분리해 결과 파일을 여러 번 재채점할 수 있게 한다.
/// 채점은 `Evals/score.mjs`가 담당한다.
///
/// 실행:
///   EVAL_GOLDEN=1 xcodebuild -project HorongHorong.xcodeproj -scheme HorongHorong \
///     -destination 'platform=macOS' -skipPackagePluginValidation -skipMacroValidation \
///     -only-testing:HorongHorongTests/GoalSuggestionEvalTests test
///
/// 환경변수 `EVAL_GOLDEN`이 없으면 건너뛴다. 평범한 `make unit` 실행을 느리게 만들지 않기 위함이다.
final class GoalSuggestionEvalTests: XCTestCase {

    // MARK: - 골든셋 입출력 모델

    private struct GoldenMemo: Decodable {
        let id: String
        let content: String
        let icon: String?
        let date: String?
        let startDate: String?
        let deadline: String?
    }

    private struct GoldenCase: Decodable {
        let caseName: String
        let note: String?
        let memos: [GoldenMemo]
        let expectedGroups: [[String]]
        let shouldNotGroup: [[String]]?
    }

    private struct EvalResult: Encodable {
        let caseName: String
        let promptCharacters: Int
        let memosInPrompt: Int
        let modelReturned: Int
        let predictedGroups: [[String]]
        let titles: [String]
        let source: String
    }

    // MARK: - 실행

    func testGenerateGoldenSetResults() async throws {
        let repositoryRoot = try Self.repositoryRoot()

        // 환경변수는 xcodebuild가 테스트 프로세스로 전달하지 않으므로 마커 파일로 켠다.
        //   touch Evals/.run-golden && make eval-golden
        let marker = repositoryRoot.appendingPathComponent("Evals/.run-golden")
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: marker.path),
            "Evals/.run-golden 없음 — 골든셋 실행을 건너뜁니다. (추론이 느려 기본 테스트에서는 제외)"
        )
        // drafts/ 도 함께 읽는다. 각색 전이라 커밋은 못 하지만 로컬 측정은 가능해야 한다.
        let directories = ["Evals/golden/cases", "Evals/golden/drafts"]
            .map { repositoryRoot.appendingPathComponent($0, isDirectory: true) }
        let caseFiles = directories
            .flatMap { directory in
                (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            }
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        XCTAssertFalse(caseFiles.isEmpty, "골든셋 케이스가 없습니다.")

        var lines: [String] = []
        for file in caseFiles {
            let goldenCase = try JSONDecoder().decode(GoldenCase.self, from: Data(contentsOf: file))
            let result = await run(goldenCase)
            lines.append(String(data: try JSONEncoder().encode(result), encoding: .utf8) ?? "")
        }

        let outputDirectory = repositoryRoot.appendingPathComponent("Evals/results", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let outputFile = outputDirectory.appendingPathComponent("\(stamp).jsonl")
        try lines.joined(separator: "\n").write(to: outputFile, atomically: true, encoding: .utf8)

        print("[eval] \(caseFiles.count)개 케이스 → \(outputFile.path)")
    }

    // MARK: - 한 케이스 실행

    private func run(_ goldenCase: GoldenCase) async -> EvalResult {
        // 골든셋의 짧은 id(m1)를 결정적 UUID로 바꾼다.
        // 같은 id는 항상 같은 UUID가 되어야 실행 간 비교가 가능하다.
        var uuidByShortID: [String: UUID] = [:]
        var shortIDByUUID: [UUID: String] = [:]
        for memo in goldenCase.memos {
            let uuid = Self.deterministicUUID(for: memo.id)
            uuidByShortID[memo.id] = uuid
            shortIDByUUID[uuid] = memo.id
        }

        let snapshots = goldenCase.memos.map { memo in
            AchievementMemoSnapshot(
                id: uuidByShortID[memo.id]!,
                content: memo.content,
                icon: memo.icon,
                date: Self.date(memo.date) ?? Date(),
                startDate: Self.date(memo.startDate),
                deadline: Self.date(memo.deadline),
                isCompleted: false
            )
        }

        // EVAL_PROVIDER=mlx 로 공급자를 바꿔 같은 골든셋을 두 모델에 돌린다.
        let requested = ProcessInfo.processInfo.environment["EVAL_PROVIDER"]
            ?? (try? String(contentsOf: Self.repositoryRoot().appendingPathComponent("Evals/.provider"), encoding: .utf8))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? Constants.defaultAchievementSuggestionProvider
        UserDefaults.standard.set(requested, forKey: Constants.AppStorageKey.achievementSuggestionProvider)

        let suggestions = await AchievementFoundationGoalSuggestionProvider.suggestions(
            from: snapshots,
            suggestionCount: Constants.defaultAchievementSuggestionCount,
            maxMemoCount: Constants.defaultAchievementSuggestionMaxTodoCount
        )

        let predicted = suggestions.map { suggestion in
            suggestion.memoIDs.compactMap { shortIDByUUID[$0] }
        }

        return EvalResult(
            caseName: goldenCase.caseName,
            promptCharacters: 0,   // 프롬프트 크기는 provider 내부 로그로 확인한다
            memosInPrompt: snapshots.count,
            modelReturned: suggestions.count,
            predictedGroups: predicted,
            titles: suggestions.map(\.title),
            source: suggestions.first?.source.rawValue ?? "none"
        )
    }

    // MARK: - 보조

    /// 짧은 id에서 항상 같은 UUID를 만든다. 실행마다 달라지면 결과 비교가 불가능하다.
    private static func deterministicUUID(for shortID: String) -> UUID {
        var bytes = Array(shortID.utf8.prefix(16))
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 16 - bytes.count))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }

    /// 테스트 번들 위치에서 저장소 루트를 거슬러 올라가 찾는다.
    private static func repositoryRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            url = url.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Evals").path) {
                return url
            }
        }
        throw XCTSkip("저장소 루트를 찾지 못했습니다.")
    }
}
