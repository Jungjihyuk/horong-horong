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

    /// 케이스 파일의 할일 하나.
    ///
    /// 날짜는 **`startDate` 와 `deadline` 둘뿐이다.** 예전에는 `date` 를 따로 적었는데,
    /// 앱에는 그런 저작 필드가 없다 — `AchievementDataBuilder.memoDate` 가
    /// `deadline ?? startDate ?? updatedAt` 로 **파생시킨다.** 골든셋만 갖고 있던 가짜 필드였고,
    /// 게다가 `WeeklyGoalTask.prompt` 는 `Memo.date` 를 한 번도 읽지 않아 아무 데도 안 닿았다.
    ///
    /// 둘 다 없을 수도, 한쪽만 있을 수도 있다. 실제 사용자의 할일이 그렇다.
    public struct Memo: Decodable, Sendable {
        public let id: String
        public let content: String
        public let icon: String?
        /// `yyyy-MM-dd` 또는 `yyyy-MM-dd HH:mm`.
        public let startDate: String?
        /// `yyyy-MM-dd` 또는 `yyyy-MM-dd HH:mm`.
        public let deadline: String?

        /// 앱이 파생시키는 그 값. 프롬프트에는 안 실리지만 태스크 입력이 요구한다.
        public func derivedDate(referenceDate: Date) -> Date {
            GoldenSet.date(deadline) ?? GoldenSet.date(startDate) ?? referenceDate
        }

        /// 주 판정에 쓸 날짜. 둘 다 없으면 `nil` — **«언제든» 할일이라 주를 넘길 수 없다.**
        public var scheduledDate: Date? {
            GoldenSet.date(deadline) ?? GoldenSet.date(startDate)
        }
    }

    /// 정답 묶음 하나.
    ///
    /// 예전에는 그냥 `[["m1","m2"]]` 였다. 그래서 **주간인지 월간인지 구분되지 않았고**,
    /// 묶어 놓고 그게 무슨 목표인지도 안 적혀 있었다.
    public struct ExpectedGroup: Decodable, Sendable {
        public enum GoalType: String, Decodable, Sendable {
            case weekly = "weekly_goal"
            case monthly = "monthly_goal"
        }

        public let type: GoalType
        /// 사람이 붙인 목표 제목.
        ///
        /// **묶음 채점에는 안 쓴다.** 제목 품질은 쌍 단위로 잴 수 있는 것이 아니라
        /// 별도 판정자가 볼 몫이다. 여기 적는 이유는 «이 묶음이 무슨 목표인가» 가
        /// 라벨링 의도를 남기는 유일한 자리이기 때문이다 —
        /// 제목이 안 붙는 묶음은 애초에 묶음이 아니다(라벨링 가이드).
        public let title: String
        public let memos: [String]
    }

    public struct Case: Decodable, Sendable {
        public let caseName: String
        public let note: String?
        /// 이 케이스에서 «오늘». **«이번 주» 가 어디인지 정하는 값**이다.
        ///
        /// 없으면 케이스가 시간에 따라 뜻이 달라진다 — 어제는 이번 주였던 할일이
        /// 다음 달에 돌리면 지난 주가 된다. 둘 다 날짜가 없는 할일의 파생 날짜도 이 값으로 채운다.
        public let referenceDate: String
        public let memos: [Memo]
        /// 정답 묶음. 짧은 id(`m1`) 로 적혀 있다.
        public let expectedGroups: [ExpectedGroup]
        /// **특히 틀리기 쉬운 자리.** 없을 수 있다.
        ///
        /// 예전 이름은 `shouldNotGroup` 이었는데, «묶이면 안 되는 모든 쌍» 을 뜻하는 것처럼 읽혀
        /// «왜 이 쌍만 적었나» 라는 물음이 나왔다. 실제로는 **골라 적은 함정**이다.
        public let traps: [PairEvaluator.Trap]?

        /// 이 케이스의 «오늘».
        public var reference: Date { GoldenSet.date(referenceDate) ?? Date() }

        /// 채점에 넘길 묶음. **타입으로 걸러서** 넘긴다 —
        /// 주간 실행 결과를 월간 정답으로 채점하면 안 된다.
        public func expectedMemoGroups(of type: ExpectedGroup.GoalType) -> [[String]] {
            expectedGroups.filter { $0.type == type }.map(\.memos)
        }

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
                    date: memo.derivedDate(referenceDate: reference),
                    startDate: GoldenSet.date(memo.startDate),
                    deadline: GoldenSet.date(memo.deadline),
                    isCompleted: false
                )
            }
        }
    }

    // MARK: - 읽기

    /// `cases/weekly/` 를 **하위 폴더까지** 훑어 경로 순으로 읽는다.
    ///
    /// 하위 폴더로 나누는 이유는 케이스가 늘면서 **페르소나별로 갈리기** 때문이다
    /// (`weekly/developer/`, `weekly/jobseeker/`, `weekly/common/` …).
    /// 한 겹만 읽으면 폴더를 나누는 순간 케이스가 조용히 사라진다.
    ///
    /// **`cases/monthly/` 는 여기서 안 읽는다.** 월간 태스크는 할일이 아니라 **주간 목표**를
    /// 입력으로 받아(`MonthlyGoalTask.Goal`) `goalIDs` 를 뱉는다. 케이스 파일의 모양 자체가
    /// 달라서(`memos` 대신 `weeklyGoals`) 같은 타입으로 못 읽는다. 월간 스키마가 정해지면
    /// 자기 로더를 갖는다.
    ///
    /// **`drafts/` 도 읽지 않는다.** 거기 있는 것은 각색·라벨링 전의 초안이라 정답이 없고,
    /// 채점에 섞이면 «만들다 만 것» 이 «모델이 틀린 것» 으로 집계된다
    /// (실측 2026-08-21: 6건 중 2건이 항상 0점이라 평균이 0.47 로 눌려 있었다. 실제는 0.70).
    /// 초안은 사람이 눈으로 참고하는 재료로만 둔다.
    public static func load(repositoryRoot: URL) throws -> [Case] {
        let root = repositoryRoot.appendingPathComponent("Evals/golden/cases/weekly", isDirectory: true)
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let files = (enumerator?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "json" }
            // 경로 전체로 정렬해야 폴더 순서가 유지된다. 파일명만 쓰면 폴더가 뒤섞인다.
            .sorted { $0.path < $1.path }

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

    /// `yyyy-MM-dd HH:mm` 을 먼저 시도하고, 안 되면 `yyyy-MM-dd`.
    ///
    /// 시간을 받는 이유는 실제 할일에 시간이 있기 때문이다 — 같은 날 14시 시작과 18시 마감은
    /// 하루짜리 계획이 아니라 그날 안에서 이어지는 실행이다.
    /// 시간이 없으면 자정으로 읽힌다.
    public static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        for format in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    /// 그 날짜가 속한 주의 시작(월요일 0시).
    ///
    /// 월요일 기준인 이유는 앱이 그렇기 때문이다 — `Constants` 의 달력이 `firstWeekday = 2` 다.
    /// 여기서 일요일 시작으로 재면 골든셋과 제품이 서로 다른 «이번 주» 를 보게 된다.
    public static func weekStart(of date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }
}
