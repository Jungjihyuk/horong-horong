import Foundation

/// `Evals/golden/` 의 케이스 파일을 읽는다.
///
/// 소비자가 둘이라 한 곳에 둔다 — 패키지 테스트(고정 응답으로 결정적 회귀 판정)와
/// 앱 테스트(실모델 품질 측정)가 **같은 케이스를 같은 방식으로** 읽어야
/// 두 결과를 나란히 놓을 수 있다.
///
/// 처음에는 `HorongAITestSupport` 에 뒀는데, 그 타깃을 앱 테스트 타깃에 연결하면
/// `Multiple commands produce 호롱호롱.app` 로 빌드가 깨진다(호스트 앱이 있는 유닛 테스트
/// 타깃에 패키지 제품을 더할 때 생기는 충돌). `Evaluation/` 은 `EvalRunner`·`PairEvaluator` 가
/// 이미 제품에 들어와 있는 자리라 여기로 옮겼다.
public enum GoldenSet {

    public struct Memo: Decodable, Sendable {
        public let id: String
        public let content: String
        public let icon: String?
        public let date: String?
        public let startDate: String?
        public let deadline: String?
    }

    public struct Case: Decodable, Sendable {
        public let caseName: String
        public let note: String?
        public let memos: [Memo]
        /// 정답 묶음. 짧은 id(`m1`) 로 적혀 있다.
        public let expectedGroups: [[String]]
        /// 묶으면 안 되는 조합. 없을 수 있다.
        public let shouldNotGroup: [[String]]?

        /// 짧은 id ↔ UUID 양방향 표. 파서는 UUID 로 말하고 채점은 짧은 id 로 한다.
        public var identifiers: (uuidByShortID: [String: UUID], shortIDByUUID: [UUID: String]) {
            var forward: [String: UUID] = [:]
            var backward: [UUID: String] = [:]
            for memo in memos {
                let uuid = GoldenSet.deterministicUUID(for: memo.id)
                forward[memo.id] = uuid
                backward[uuid] = memo.id
            }
            return (forward, backward)
        }

        /// 태스크에 넘길 입력.
        ///
        /// `defaultIcon` 을 받는 이유는 아이콘 기본값이 **앱이 정하는 값**이기 때문이다.
        /// 여기서 임의로 정하면 평가가 제품과 다른 프롬프트를 만든다.
        public func taskMemos(defaultIcon: String) -> [WeeklyGoalTask.Memo] {
            let uuidByShortID = identifiers.uuidByShortID
            return memos.map { memo in
                WeeklyGoalTask.Memo(
                    id: uuidByShortID[memo.id] ?? GoldenSet.deterministicUUID(for: memo.id),
                    content: memo.content,
                    icon: memo.icon ?? defaultIcon,
                    date: GoldenSet.date(memo.date) ?? Date(),
                    startDate: GoldenSet.date(memo.startDate),
                    deadline: GoldenSet.date(memo.deadline),
                    isCompleted: false
                )
            }
        }
    }

    // MARK: - 읽기

    /// `cases/` 와 `drafts/` 를 파일명 순으로 읽는다.
    /// `drafts/` 도 읽는 이유는 각색 전이라 커밋은 못 해도 로컬 측정은 가능해야 하기 때문이다.
    public static func load(repositoryRoot: URL) throws -> [Case] {
        let directories = ["Evals/golden/cases", "Evals/golden/drafts"]
            .map { repositoryRoot.appendingPathComponent($0, isDirectory: true) }
        let files = directories
            .flatMap { directory in
                (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            }
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return try files.map { try JSONDecoder().decode(Case.self, from: Data(contentsOf: $0)) }
    }

    /// 부르는 파일에서 위로 거슬러 올라가 `Evals/` 가 있는 곳을 찾는다.
    /// 패키지와 앱은 소스 깊이가 달라 고정 횟수로는 못 찾는다.
    public static func repositoryRoot(from filePath: String = #filePath) -> URL? {
        var url = URL(fileURLWithPath: filePath)
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Evals").path) {
                return url
            }
        }
        return nil
    }

    // MARK: - 보조

    /// 짧은 id 에서 항상 같은 UUID 를 만든다. 실행마다 달라지면 결과 비교가 불가능하다.
    public static func deterministicUUID(for shortID: String) -> UUID {
        var bytes = Array(shortID.utf8.prefix(16))
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 16 - bytes.count))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    public static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }
}
