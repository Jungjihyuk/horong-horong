#if DEBUG
import SwiftUI
import SwiftData

/// 성능 측정용 합성 기록 생성기. **Debug 빌드에서만 컴파일된다.**
///
/// 리팩터링 전후를 비교하려면 "기록이 많을 때"를 재현해야 하는데, 실사용 데이터로는
/// 같은 조건을 두 번 만들 수 없다. 그래서 분포를 고정한 합성 데이터를 쓴다.
///
/// 실사용 저장소를 건드리지 않는 근거는 두 겹이다.
/// ① `SwiftDataStoreLocation.currentScope` 가 Debug 에서 `.development` 라 파일이 애초에 다르다
/// (`HorongHorong-Debug/`). ② 그래도 `guardDevelopmentStore()` 로 한 번 더 막는다 —
/// 누군가 Release 에서 이 코드를 살려낼 때를 대비한 안전장치다.
enum SecondBrainSeeder {
    enum SeedError: LocalizedError {
        case notDevelopmentStore

        var errorDescription: String? {
            "개발용 저장소가 아닙니다. 합성 데이터를 만들지 않았습니다."
        }
    }

    /// 실측 대조를 위해 분포를 고정한다. 비율이 바뀌면 이전 측정과 비교할 수 없다.
    private static let sectionWeights: [(MemoSection, Int)] = [
        (.quickNote, 40),
        (.todo, 40),
        (.reference, 20),
    ]

    static func count(in context: ModelContext) -> Int {
        let todos = (try? context.fetchCount(FetchDescriptor<Todo>())) ?? 0
        let notes = (try? context.fetchCount(FetchDescriptor<QuickNote>())) ?? 0
        let references = (try? context.fetchCount(FetchDescriptor<Reference>())) ?? 0
        return todos + notes + references
    }

    /// `count` 건을 넣는다. 저장은 마지막에 한 번만 한다 —
    /// 건마다 `save()` 하면 SQLite fsync 가 1만 번 일어나 몇 분이 걸린다.
    static func seed(count: Int, into context: ModelContext) throws {
        try guardDevelopmentStore()

        // 시드를 고정해 실행할 때마다 같은 데이터가 나오게 한다.
        // 측정값이 달라졌을 때 데이터 탓인지 코드 탓인지 가리려면 이게 필요하다.
        var rng = SeededGenerator(seed: 20260901)
        let now = Date()

        for index in 0..<count {
            let section = weightedSection(&rng)
            let itemContent = content(index: index, section: section, &rng)
            let ageDays = Double(rng.next(upTo: 730))
            let created = now.addingTimeInterval(-ageDays * 86_400)
            let isPinned = rng.next(upTo: 100) < 5

            switch section {
            case .todo:
                let todo = Todo(content: itemContent)
                todo.createdAt = created
                todo.updatedAt = created
                todo.isPinned = isPinned
                applyTodoDates(to: todo, now: now, &rng)
                context.insert(todo)
            case .quickNote:
                let note = QuickNote(content: itemContent)
                note.createdAt = created
                note.updatedAt = created
                note.isPinned = isPinned
                context.insert(note)
            case .reference:
                let reference = Reference(content: itemContent)
                reference.createdAt = created
                reference.updatedAt = created
                reference.isPinned = isPinned
                context.insert(reference)
            }
        }

        try context.save()
    }

    /// 개발 저장소의 기록을 전부 지운다. 합성분만 골라내지 않는 이유는
    /// 표식용 필드를 넣으려면 스키마를 바꿔야 하고, 그건 측정과 무관한 변경이기 때문이다.
    static func deleteAll(in context: ModelContext) throws {
        try guardDevelopmentStore()
        try context.delete(model: Todo.self)
        try context.delete(model: QuickNote.self)
        try context.delete(model: Reference.self)
        try context.save()
    }

    private static func guardDevelopmentStore() throws {
        guard SwiftDataStoreLocation.currentScope == .development else {
            throw SeedError.notDevelopmentStore
        }
    }

    private static func weightedSection(_ rng: inout SeededGenerator) -> MemoSection {
        let total = sectionWeights.reduce(0) { $0 + $1.1 }
        var roll = rng.next(upTo: total)
        for (section, weight) in sectionWeights {
            if roll < weight { return section }
            roll -= weight
        }
        return .quickNote
    }

    private static func applyTodoDates(to record: Todo, now: Date, _ rng: inout SeededGenerator) {
        // -60 ~ +60일. 지남/오늘/예정 버킷이 골고루 차게 한다.
        let offset = Double(rng.next(upTo: 121) - 60)
        let day = now.addingTimeInterval(offset * 86_400)

        if rng.next(upTo: 100) < 20 {
            record.startDate = nil          // 언젠가 버킷
            record.deadline = nil
        } else if rng.next(upTo: 100) < 50 {
            record.deadline = day
        } else {
            record.startDate = day
        }

        if rng.next(upTo: 100) < 30 {
            record.setCompleted(true, at: day)
        }
    }

    // MARK: - 본문

    /// 한국어로 만든다. `localizedCaseInsensitiveContains` 는 ICU 로케일 비교라
    /// 영문보다 비싸고, 한글 IME 는 조합 단계마다 바인딩을 커밋해 재렌더가 배로 는다.
    /// 영문 더미로 재면 실사용보다 낙관적인 숫자가 나온다.
    private static func content(index: Int, section: MemoSection, _ rng: inout SeededGenerator) -> String {
        if section == .reference, rng.next(upTo: 100) < 60 {
            return "https://example.com/article/\(index)\n참고용으로 저장해 둔 링크 \(index)"
        }

        let title = "\(titles[rng.next(upTo: titles.count)]) \(index)"
        let extraLines = rng.next(upTo: 5)          // 0~4줄. 길이를 흩뿌린다
        guard extraLines > 0 else { return title }

        let body = (0..<extraLines)
            .map { _ in bodies[rng.next(upTo: bodies.count)] }
            .joined(separator: "\n")
        return title + "\n" + body
    }

    private static let titles = [
        "회의 준비 정리", "장보기 목록", "읽을 논문 메모", "리팩터링 아이디어",
        "운동 계획 세우기", "여행 일정 초안", "책에서 인상 깊었던 문장", "버그 재현 순서",
        "다음 주 목표", "전화할 곳", "정리해야 할 서류", "새로 배운 단축키",
    ]

    private static let bodies = [
        "생각보다 오래 걸릴 수 있으니 미리 시작해 두는 편이 낫다.",
        "관련해서 지난번에 정리해 둔 문서를 다시 찾아봐야 한다.",
        "우선순위가 높지는 않지만 잊어버리면 곤란한 항목이다.",
        "담당자와 이야기해 보고 나서 결정하기로 했다.",
        "비슷한 사례를 찾아서 어떻게 처리했는지 확인이 필요하다.",
        "마감이 가까워지면 다시 확인할 것.",
    ]
}

/// 재현 가능한 난수. `SystemRandomNumberGenerator` 를 쓰면 실행할 때마다 데이터가 달라져
/// 측정값 차이가 코드 때문인지 데이터 때문인지 구분할 수 없다.
private struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    }

    /// xorshift64. 품질보다 재현성과 단순함이 목적이다.
    private mutating func nextRaw() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func next(upTo bound: Int) -> Int {
        guard bound > 0 else { return 0 }
        return Int(nextRaw() % UInt64(bound))
    }
}

/// 설정 > 데이터 페이지 맨 아래에 붙는 Debug 전용 카드.
struct SecondBrainSeederCard: View {
    @Environment(\.modelContext) private var modelContext
    @State private var memoCount = 0
    @State private var message = ""
    @State private var isWorking = false

    var body: some View {
        SettingsGroupCard("성능 측정용 합성 데이터 (Debug 전용)") {
            SettingsRow(
                "현재 기록",
                subtitle: message.isEmpty
                    ? "저장소: \(SwiftDataStoreLocation.currentScope == .development ? "HorongHorong-Debug" : "⚠️ 실사용")"
                    : message
            ) {
                Text("\(memoCount)건")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }

            SettingsRow(
                "합성 기록 생성",
                subtitle: "Quick Note 40% · Todo 40% · References 20%. 시드 고정이라 실행할 때마다 같은 데이터가 나온다"
            ) {
                HStack(spacing: 8) {
                    Button("1천 건") { seed(1_000) }
                    Button("1만 건") { seed(10_000) }
                }
                .controlSize(.small)
                .disabled(isWorking)
            }

            SettingsRow(
                "전부 삭제",
                subtitle: "개발 저장소의 기록을 모두 지운다. 실사용 저장소는 파일이 달라 영향받지 않는다"
            ) {
                Button("삭제", role: .destructive) { deleteAll() }
                    .controlSize(.small)
                    .disabled(isWorking)
            }
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        memoCount = SecondBrainSeeder.count(in: modelContext)
    }

    private func seed(_ count: Int) {
        isWorking = true
        do {
            try SecondBrainSeeder.seed(count: count, into: modelContext)
            message = "\(count)건 추가함"
        } catch {
            message = error.localizedDescription
        }
        refresh()
        isWorking = false
    }

    private func deleteAll() {
        isWorking = true
        do {
            try SecondBrainSeeder.deleteAll(in: modelContext)
            message = "모두 삭제함"
        } catch {
            message = error.localizedDescription
        }
        refresh()
        isWorking = false
    }
}
#endif
