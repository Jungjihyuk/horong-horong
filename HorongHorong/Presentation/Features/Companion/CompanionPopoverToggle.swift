import Foundation

/// 메뉴바 팝오버를 대신 열고 닫는다. 열림 여부는 기억하지 않고 매번 실제 창에서 읽는다.
///
/// 예전에는 "컴패니언이 열었다"는 플래그로 열림을 짐작했다. 사용자가 팝오버를 직접 닫거나 열면
/// 플래그가 어긋나서, 닫힌 팝오버를 열린 줄 알고 탭만 바꾸거나(무반응) 열린 팝오버를 눌러
/// 닫아 버렸다 (2026-09-29 · 루미롱 「기록 탭 보기」). 메뉴바 아이콘은 누를 때마다 열고 닫기를
/// 뒤집으므로, 누르기 전에 실제 상태를 봐야 한다.
@MainActor
final class CompanionPopoverToggle {
    private let isVisible: () -> Bool
    private let toggle: () -> Bool
    /// 컴패니언이 연 팝오버만 닫기 위한 표시다. 열림 여부 판단에는 쓰지 않는다.
    private var openedByCompanion = false

    init(isVisible: @escaping () -> Bool, toggle: @escaping () -> Bool) {
        self.isVisible = isVisible
        self.toggle = toggle
    }

    /// 팝오버가 보이게 한다. 메뉴바 버튼을 못 찾으면 false.
    @discardableResult
    func open() -> Bool {
        // 이미 보이면 누르지 않는다. 누르면 닫힌다.
        if isVisible() { return true }
        guard toggle() else { return false }
        openedByCompanion = true
        return true
    }

    /// 컴패니언이 연 팝오버가 아직 보일 때만 닫는다.
    func close() {
        defer { openedByCompanion = false }
        // 사용자가 이미 닫았으면 누르지 않는다. 누르면 다시 열린다.
        guard openedByCompanion, isVisible() else { return }
        _ = toggle()
    }
}
