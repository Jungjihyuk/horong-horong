import SwiftData
import XCTest
@testable import 호롱호롱

/// 참고 자료 저장소가 실제 SwiftData 위에서 갈래·구조·위젯 상태를 제대로 다루는지 검사한다.
@MainActor
final class SwiftDataReferenceRepositoryTests: XCTestCase {
    /// **컨테이너를 함께 돌려준다.** 컨테이너가 먼저 풀리면 `mainContext` 가 매달린 참조가 되어
    /// 테스트가 첫 줄에서 트랩으로 죽는다.
    private func makeRepository() throws -> (SwiftDataReferenceRepository, ModelContext, ModelContainer) {
        let schema = Schema([Reference.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        return (SwiftDataReferenceRepository(context: context), context, container)
    }

    func testAddStoresTheRequestedKind() throws {
        let (repository, _, container) = try makeRepository()
        defer { withExtendedLifetime(container) {} }

        let link = try repository.add(kind: .link)
        let note = try repository.add(kind: .note)

        XCTAssertEqual(link.kind, .link)
        XCTAssertEqual(note.kind, .note)
        XCTAssertEqual(note.color, .yellow, "쪽지는 기본 색을 갖고 태어난다")
    }

    /// 갈래로 거르는 일은 저장소가 한다 — 화면이 거르면 페이징 계산이 틀어진다.
    func testFilteringByKindHappensInTheRepository() throws {
        let (repository, _, container) = try makeRepository()
        defer { withExtendedLifetime(container) {} }
        try repository.add(kind: .link)
        try repository.add(kind: .link)
        try repository.add(kind: .note)

        XCTAssertEqual(try repository.references(matching: "", kind: nil, limit: 10).count, 3)
        XCTAssertEqual(try repository.references(matching: "", kind: .link, limit: 10).count, 2)
        XCTAssertEqual(try repository.references(matching: "", kind: .note, limit: 10).count, 1)
    }

    func testLimitIsHonouredWithAndWithoutAKind() throws {
        let (repository, _, container) = try makeRepository()
        defer { withExtendedLifetime(container) {} }
        for _ in 0..<5 { try repository.add(kind: .link) }

        XCTAssertEqual(try repository.references(matching: "", kind: nil, limit: 3).count, 3)
        XCTAssertEqual(try repository.references(matching: "", kind: .link, limit: 2).count, 2)
    }

    /// 바꿀 필드만 담아 보내면 나머지는 그대로 남는다.
    func testUpdateOnlyTouchesGivenFields() throws {
        let (repository, _, container) = try makeRepository()
        defer { withExtendedLifetime(container) {} }
        let note = try repository.add(kind: .note)
        try repository.update(id: note.id, ReferenceChange(title: "알리오 올리오", body: "면수가 전부"))

        try repository.update(id: note.id, ReferenceChange(color: .pink))

        let saved = try XCTUnwrap(try repository.reference(id: note.id))
        XCTAssertEqual(saved.title, "알리오 올리오")
        XCTAssertEqual(saved.body, "면수가 전부")
        XCTAssertEqual(saved.color, .pink)
    }

    func testSearchLooksAtTitleUrlAndBody() throws {
        let (repository, _, container) = try makeRepository()
        defer { withExtendedLifetime(container) {} }
        let link = try repository.add(kind: .link)
        try repository.update(id: link.id, ReferenceChange(title: "논문", url: "https://arxiv.org/abs/1"))
        let note = try repository.add(kind: .note)
        try repository.update(id: note.id, ReferenceChange(title: "레시피", body: "면수를 남긴다"))

        XCTAssertEqual(try repository.references(matching: "arxiv", kind: nil, limit: 10).count, 1)
        XCTAssertEqual(try repository.references(matching: "면수", kind: nil, limit: 10).count, 1)
        XCTAssertEqual(try repository.references(matching: "논문", kind: nil, limit: 10).count, 1)
        XCTAssertTrue(try repository.references(matching: "없는말", kind: nil, limit: 10).isEmpty)
    }

    // MARK: - 위젯

    func testWidgetNotesReturnsOnlyPoppedOutNotes() throws {
        let (repository, _, container) = try makeRepository()
        defer { withExtendedLifetime(container) {} }
        let popped = try repository.add(kind: .note)
        try repository.update(id: popped.id, ReferenceChange(isWidget: true))
        try repository.add(kind: .note)
        let link = try repository.add(kind: .link)
        try repository.update(id: link.id, ReferenceChange(isWidget: true))

        let widgets = try repository.widgetNotes()

        XCTAssertEqual(widgets.count, 1, "쪽지만 위젯이 된다")
        XCTAssertEqual(widgets.first?.id, popped.id)
    }

    func testWidgetPositionSurvivesARoundTrip() throws {
        let (repository, _, container) = try makeRepository()
        defer { withExtendedLifetime(container) {} }
        let note = try repository.add(kind: .note)

        try repository.update(id: note.id, ReferenceChange(widgetPosition: CGPoint(x: 812, y: 344)))

        XCTAssertEqual(try repository.reference(id: note.id)?.widgetPosition, CGPoint(x: 812, y: 344))
    }

    func testWidgetSizeAndCollapseSurviveARoundTrip() throws {
        let (repository, _, container) = try makeRepository()
        defer { withExtendedLifetime(container) {} }
        let note = try repository.add(kind: .note)

        try repository.update(
            id: note.id,
            ReferenceChange(widgetSize: CGSize(width: 320, height: 280), isWidgetCollapsed: true)
        )

        let saved = try XCTUnwrap(try repository.reference(id: note.id))
        XCTAssertEqual(saved.widgetSize, CGSize(width: 320, height: 280))
        XCTAssertTrue(saved.isWidgetCollapsed)
    }

    /// 앞뒤 순서도 쪽지마다 따로 남는다.
    func testWidgetDepthSurvivesARoundTrip() throws {
        let (repository, _, container) = try makeRepository()
        defer { withExtendedLifetime(container) {} }
        let note = try repository.add(kind: .note)

        try repository.update(id: note.id, ReferenceChange(isWidgetBehind: true))
        XCTAssertTrue(try XCTUnwrap(try repository.reference(id: note.id)).isWidgetBehind)

        try repository.update(id: note.id, ReferenceChange(isWidgetBehind: false))
        XCTAssertFalse(try XCTUnwrap(try repository.reference(id: note.id)).isWidgetBehind)
    }

    /// 앞뒤를 바꾼 것도 내용 변경이 아니다 — 목록이 재배열되면 안 된다.
    func testChangingDepthDoesNotReorderTheList() throws {
        let (repository, _, container) = try makeRepository()
        defer { withExtendedLifetime(container) {} }
        let older = try repository.add(kind: .note)
        let newer = try repository.add(kind: .note)

        try repository.update(id: older.id, ReferenceChange(isWidgetBehind: true))

        XCTAssertEqual(try repository.references(matching: "", kind: nil, limit: 10).first?.id, newer.id)
    }

    /// 접힘 상태를 적지 않은 옛 기록은 «펼쳐짐» 으로 읽힌다.
    func testCollapseDefaultsToExpanded() throws {
        let (repository, _, container) = try makeRepository()
        defer { withExtendedLifetime(container) {} }
        let note = try repository.add(kind: .note)

        XCTAssertFalse(try XCTUnwrap(try repository.reference(id: note.id)).isWidgetCollapsed)
        XCTAssertFalse(try XCTUnwrap(try repository.reference(id: note.id)).isWidgetBehind, "기본은 맨 앞")
        XCTAssertNil(try repository.reference(id: note.id)?.widgetSize)
    }

    /// 창 크기를 바꾼 것도 내용이 바뀐 것이 아니다 — 목록이 재배열되면 안 된다.
    func testResizingAWidgetDoesNotReorderTheList() throws {
        let (repository, _, container) = try makeRepository()
        defer { withExtendedLifetime(container) {} }
        let older = try repository.add(kind: .note)
        let newer = try repository.add(kind: .note)

        try repository.update(id: older.id, ReferenceChange(widgetSize: CGSize(width: 300, height: 300)))
        try repository.update(id: older.id, ReferenceChange(isWidgetCollapsed: true))

        XCTAssertEqual(try repository.references(matching: "", kind: nil, limit: 10).first?.id, newer.id)
    }

    /// **창을 옮긴 것은 내용이 바뀐 것이 아니다.** 위치 저장이 `updatedAt` 을 건드리면
    /// 쪽지를 끌 때마다 목록 맨 위로 튀어 오른다.
    func testMovingAWidgetDoesNotReorderTheList() throws {
        let (repository, _, container) = try makeRepository()
        defer { withExtendedLifetime(container) {} }
        let older = try repository.add(kind: .note)
        let newer = try repository.add(kind: .note)
        XCTAssertEqual(try repository.references(matching: "", kind: nil, limit: 10).first?.id, newer.id)

        try repository.update(id: older.id, ReferenceChange(widgetPosition: CGPoint(x: 10, y: 20)))

        XCTAssertEqual(
            try repository.references(matching: "", kind: nil, limit: 10).first?.id,
            newer.id,
            "위치만 바뀌었으므로 순서는 그대로다"
        )
    }

    func testEditingContentDoesReorderTheList() throws {
        let (repository, _, container) = try makeRepository()
        defer { withExtendedLifetime(container) {} }
        let older = try repository.add(kind: .note)
        try repository.add(kind: .note)

        try repository.update(id: older.id, ReferenceChange(body: "새로 적음"))

        XCTAssertEqual(try repository.references(matching: "", kind: nil, limit: 10).first?.id, older.id)
    }

    // MARK: - 백필 전 옛 기록

    /// 갈래가 저장되기 전 행도 화면이 갈라 볼 수 있어야 한다.
    func testLegacyRowsAreReadWithTheOldRule() throws {
        let (repository, context, container) = try makeRepository()
        defer { withExtendedLifetime(container) {} }
        context.insert(Reference(content: "https://arxiv.org/abs/1"))
        context.insert(Reference(content: "장 볼 것\n우유\n달걀"))
        try context.save()

        let links = try repository.references(matching: "", kind: .link, limit: 10)
        let notes = try repository.references(matching: "", kind: .note, limit: 10)

        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.url, "https://arxiv.org/abs/1")
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.title, "장 볼 것", "첫 줄이 제목이 된다")
        XCTAssertEqual(notes.first?.body, "장 볼 것\n우유\n달걀")
    }

    /// 백필은 한 번만 돈다. 두 번째 실행이 사용자가 고친 값을 덮으면 안 된다.
    func testBackfillRunsOnceAndKeepsUserEdits() throws {
        let (repository, context, container) = try makeRepository()
        defer { withExtendedLifetime(container) {} }
        context.insert(Reference(content: "https://arxiv.org/abs/1"))
        try context.save()
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!

        AppDelegate.backfillReferenceStructure(in: context, defaults: defaults)
        let id = try XCTUnwrap(try repository.references(matching: "", kind: nil, limit: 10).first?.id)
        try repository.update(id: id, ReferenceChange(title: "내가 고친 제목"))

        AppDelegate.backfillReferenceStructure(in: context, defaults: defaults)

        XCTAssertEqual(try repository.reference(id: id)?.title, "내가 고친 제목")
    }
}
