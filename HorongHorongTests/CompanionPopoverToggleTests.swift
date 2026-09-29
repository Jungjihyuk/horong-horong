import XCTest
@testable import 호롱호롱

/// 메뉴바 아이콘 클릭을 흉내 낸다. 누를 때마다 팝오버가 열리고 닫힌다.
@MainActor
private final class FakeMenuBarPopover {
    var isVisible = false
    var isButtonFound = true
    private(set) var clicks = 0

    func click() -> Bool {
        guard isButtonFound else { return false }
        clicks += 1
        isVisible.toggle()
        return true
    }
}

@MainActor
final class CompanionPopoverToggleTests: XCTestCase {
    private func makeToggle(_ popover: FakeMenuBarPopover) -> CompanionPopoverToggle {
        CompanionPopoverToggle(isVisible: { popover.isVisible }, toggle: { popover.click() })
    }

    /// 루미롱이 연 팝오버를 사용자가 닫은 뒤에도 「기록 탭 보기」가 다시 연다 (2026-09-29 버그).
    func testReopensAfterUserClosedPopoverThatCompanionOpened() {
        let popover = FakeMenuBarPopover()
        let toggle = makeToggle(popover)
        XCTAssertTrue(toggle.open())

        popover.isVisible = false // 사용자가 바깥을 눌러 닫음

        XCTAssertTrue(toggle.open())
        XCTAssertTrue(popover.isVisible)
    }

    /// 사용자가 열어 둔 팝오버를 누르면 닫혀 버리므로 누르지 않는다.
    func testOpenDoesNotClickWhenUserAlreadyOpenedPopover() {
        let popover = FakeMenuBarPopover()
        popover.isVisible = true
        let toggle = makeToggle(popover)

        XCTAssertTrue(toggle.open())
        XCTAssertTrue(popover.isVisible)
        XCTAssertEqual(popover.clicks, 0)
    }

    /// 사용자가 이미 닫은 팝오버를 닫으려고 누르면 다시 열리므로 누르지 않는다.
    func testCloseDoesNotReopenPopoverUserAlreadyClosed() {
        let popover = FakeMenuBarPopover()
        let toggle = makeToggle(popover)
        toggle.open()
        popover.isVisible = false

        toggle.close()

        XCTAssertFalse(popover.isVisible)
    }

    /// 사용자가 직접 연 팝오버는 온보딩이 끝나도 닫지 않는다.
    func testCloseKeepsPopoverUserOpened() {
        let popover = FakeMenuBarPopover()
        popover.isVisible = true
        let toggle = makeToggle(popover)
        toggle.open()

        toggle.close()

        XCTAssertTrue(popover.isVisible)
    }

    func testCloseClosesPopoverCompanionOpened() {
        let popover = FakeMenuBarPopover()
        let toggle = makeToggle(popover)
        toggle.open()

        toggle.close()

        XCTAssertFalse(popover.isVisible)
    }

    /// 메뉴바 버튼을 못 찾으면 열린 척하지 않는다.
    func testOpenFailsWhenStatusButtonMissing() {
        let popover = FakeMenuBarPopover()
        popover.isButtonFound = false
        let toggle = makeToggle(popover)

        XCTAssertFalse(toggle.open())
        XCTAssertFalse(popover.isVisible)
    }
}
