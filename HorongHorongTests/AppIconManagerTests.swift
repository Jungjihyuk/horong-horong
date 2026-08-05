import XCTest
@testable import 호롱호롱

@MainActor
final class AppIconManagerTests: XCTestCase {
    func testAllSelectableAppIconsAreBundled() {
        XCTAssertEqual(Constants.AppIconStyle.allCases.count, 3)

        for style in Constants.AppIconStyle.allCases {
            XCTAssertNotNil(
                AppIconManager.image(for: style),
                "\(style.resourceName).png 리소스를 찾을 수 없습니다."
            )
        }
    }

    func testInvalidStoredAppIconFallsBackToDefault() {
        XCTAssertEqual(
            Constants.AppIconStyle.normalized(rawValue: "unsupported"),
            .horong
        )
        XCTAssertEqual(Constants.defaultAppIcon, Constants.AppIconStyle.horong.rawValue)
    }
}
