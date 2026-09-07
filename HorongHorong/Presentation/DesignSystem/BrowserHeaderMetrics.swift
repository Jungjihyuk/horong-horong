import AppKit
import SwiftUI

/// Second Brain 목록 화면(Todo · Quick Note)이 공유하는 머리말 치수.
///
/// `private` 이 아닌 이유는 **최소 너비가 머리말을 담을 수 있는지 테스트가 검사**하기 때문이다.
/// 이 관계가 깨지면 제목이 «To / do» 처럼 두 줄로 접힌다 (2026-09-07 회귀).
@MainActor
enum BrowserHeaderMetrics {
    static let horizontalPadding: CGFloat = 18
    static let titleSearchSpacing: CGFloat = 12
    static let titleSearchMinimumGap: CGFloat = 8
    static let searchFieldWidth: CGFloat = 220
    /// 돋보기와 «할 일 검색» 안내 문구가 다 보이는 선.
    static let searchFieldMinimumWidth: CGFloat = 130

    /// 제목·부제가 쓸 자리를 뺀 나머지. 머리말이 아무리 좁아져도 이만큼은 고정으로 든다.
    static let fixedChromeWidth =
        horizontalPadding * 2 + titleSearchSpacing * 2 + titleSearchMinimumGap

    /// 재는 쪽과 그리는 쪽이 어긋나지 않도록 `NSFont` 를 원본으로 두고 `Font` 를 파생시킨다.
    static let titleNSFont: NSFont = {
        let base = NSFont.systemFont(ofSize: 19, weight: .heavy)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: descriptor, size: 19) ?? base
    }()
    static let titleFont = Font(titleNSFont)
    static let subtitleFont = Font.system(size: 11.5, weight: .semibold, design: .rounded)
}
