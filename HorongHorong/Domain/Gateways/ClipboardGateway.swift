import Foundation

/// 운영체제 클립보드와 문자열을 주고받는다. Presentation은 AppKit 구현을 알지 않는다.
@MainActor
protocol ClipboardGateway {
    func readText() -> String?
    @discardableResult func writeText(_ text: String) -> Bool
}
