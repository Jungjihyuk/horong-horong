import XCTest
import SwiftUI
@testable import 호롱호롱

@MainActor
final class ToastPanelTests: XCTestCase {

    /// 표준 토스트 패널이 구형 `.hudWindow` 레거시 마스크를 쓰지 않고
    /// 모던한 `.borderless` 스타일마스크를 사용하는지 검증한다.
    func testStandardStyleMaskUsesBorderlessWithoutHudWindow() {
        let mask = ToastPanel.Style.standard.styleMask

        XCTAssertTrue(mask.contains(.borderless))
        XCTAssertTrue(mask.contains(.nonactivatingPanel))
        XCTAssertFalse(mask.contains(.hudWindow), "구형 HUD 윈도우 스타일은 호롱 테마와 충돌하므로 사용하지 않는다.")
    }

    /// 표준 토스트 크기가 충분한 가로폭과 시인성을 갖는지 검증한다.
    func testStandardStyleSizeMatchesModernDesign() {
        let size = ToastPanel.Style.standard.size

        XCTAssertEqual(size.width, 360)
        XCTAssertEqual(size.height, 76)
    }

    /// 타이머 알림 토스트 스타일마스크도 borderless인지 확인한다.
    func testTimerAlertStyleMaskUsesBorderless() {
        let mask = ToastPanel.Style.timerAlert.styleMask

        XCTAssertTrue(mask.contains(.borderless))
        XCTAssertTrue(mask.contains(.nonactivatingPanel))
    }

    /// ToastView가 standard 스타일로 정상 인스턴스화되는지 확인한다.
    func testToastViewInitialization() {
        let view = ToastView(
            icon: "🧪",
            title: "오늘 실험 실행 시작",
            subtitle: "Claude 실행 커맨드를 터미널로 전달했습니다.",
            detail: nil,
            style: .standard,
            onDismiss: {}
        )

        XCTAssertEqual(view.icon, "🧪")
        XCTAssertEqual(view.title, "오늘 실험 실행 시작")
        XCTAssertEqual(view.subtitle, "Claude 실행 커맨드를 터미널로 전달했습니다.")
        XCTAssertEqual(view.style, .standard)
    }
}
