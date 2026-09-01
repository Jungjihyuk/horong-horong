import XCTest
import SwiftData
@testable import 호롱호롱

/// 허브를 열 때 무엇이 비싼지 **클릭 없이** 재기 위한 측정.
///
/// 창을 여는 순간 각 탭의 `@Query` 가 도는데, 그 비용을 실제 규모(13,000건)로 재현한다.
/// 화면을 띄우지 않으므로 SwiftUI body 비용은 안 들어간다 — **fetch 비용만** 본다.
@MainActor
final class MemoFetchCostTests: XCTestCase {
    private var container: ModelContainer!

    private var storeURL: URL!

    /// **디스크 저장소로 잰다.** 인메모리로 재면 SwiftData 가 SQLite 에서 객체를
    /// fault-in 하는 비용이 빠져 실제보다 낙관적인 숫자가 나온다.
    override func setUpWithError() throws {
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fetch-cost-\(UUID().uuidString).store")
        let schema = HorongHorongModelSchema.make()
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        container = try ModelContainer(for: schema, configurations: [configuration])

        let context = container.mainContext
        let sections: [MemoSection] = [.quickNote, .todo, .reference]
        for index in 0..<13_000 {
            let section = sections[index % 3]
            let memo = Memo(content: "기록 \(index)\n두 번째 줄이 있는 경우도 있다", section: section)
            memo.createdAt = Date().addingTimeInterval(-Double(index) * 60)
            if section == .todo, index % 4 == 0 {
                memo.deadline = memo.createdAt
            }
            context.insert(memo)
        }
        try context.save()
    }

    override func tearDownWithError() throws {
        container = nil
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(
                at: storeURL.deletingPathExtension()
                    .appendingPathExtension("store" + suffix)
            )
        }
    }

    private func time(_ label: String, _ block: () throws -> Int) rethrows {
        let start = CFAbsoluteTimeGetCurrent()
        let count = try block()
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print(String(format: "⏱ %7.1fms  %d건  |  %@", ms, count, label))
    }

    /// Stats·Achievement 가 지금 하는 일: 조건 없이 전량 + updatedAt 정렬.
    func testCostBreakdown() throws {
        let context = container.mainContext

        try time("① 전량 fetch (정렬 없음)") {
            try context.fetch(FetchDescriptor<Memo>()).count
        }

        try time("② 전량 fetch + updatedAt 정렬  ← Stats·Achievement") {
            try context.fetch(FetchDescriptor<Memo>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )).count
        }

        try time("③ 술어 fetch (todo) + createdAt 정렬  ← 지금 기록탭") {
            try context.fetch(FetchDescriptor<Memo>(
                predicate: #Predicate { $0.sectionRaw == "todo" },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )).count
        }

        try time("④ 술어 + 페이징 50건  ← Phase 3 목표") {
            var descriptor = FetchDescriptor<Memo>(
                predicate: #Predicate { $0.sectionRaw == "todo" },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            descriptor.fetchLimit = 50
            return try context.fetch(descriptor).count
        }

        try time("⑤ fetchCount (개수만)") {
            try context.fetchCount(FetchDescriptor<Memo>())
        }

        // 실체화 비용: fetch 한 뒤 실제로 속성을 읽으면 얼마나 더 드는가
        let all = try context.fetch(FetchDescriptor<Memo>())
        try time("⑥ 전량 순회하며 속성 읽기  ← makeSnapshot 이 하는 일") {
            all.filter { $0.resolvedSection == .todo && !$0.isArchivedValue }.count
        }
    }
}
