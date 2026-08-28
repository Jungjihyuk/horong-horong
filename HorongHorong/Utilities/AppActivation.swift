import AppKit
import OSLog

/// 창을 앞으로 내보내는 것과 앱을 활성화하는 것은 다른 일이다.
///
/// `orderFrontRegardless()` 는 앱이 비활성인 채로도 창을 맨 앞에 올린다.
/// 그래서 활성화가 밀려도 화면상으로는 성공처럼 보이고, 그 상태에서는 IME 가 붙지 않아
/// 영문·기호만 입력되고 한글만 사라진다.
///
/// macOS 14 부터 `activate()` 는 «요청» 이라 시스템이 승인해야 반영되고, 반영도 비동기다.
/// 한 번 부르고 끝내면 밀렸는지 알 수 없으므로 **확인하고 재시도한다.**
@MainActor
enum AppActivation {
    private static let log = Logger(subsystem: "com.horonghorong.app", category: "Activation")

    /// 활성화가 실제로 반영됐는지 보는 시점. 밀렸을 때만 다음 요청이 나간다.
    /// 차가운 실행에서는 메인 스레드가 잠깐 막혀 첫 요청이 늦게 도착할 수 있어 두 번 본다.
    private static let checkDelays: [TimeInterval] = [0.15, 0.5]

    /// 창을 키 윈도우로 올리고, 앱 활성화가 실제로 끝났는지까지 확인한다.
    /// 첫 `NSApp.activate()` 는 사용자 클릭과 같은 런루프에서 부른 뒤 이 함수를 호출한다.
    static func front(_ window: NSWindow?) {
        guard let window else {
            log.error("전면화할 창을 찾지 못했다")
            return
        }
        // 실패했을 때만 남기면 «로그가 없다» 가 성공인지 미호출인지 구분되지 않는다.
        log.notice("front 요청 — 창: \(describe(window), privacy: .public)")
        window.makeKeyAndOrderFront(nil)
        verify(window, step: 0, startedAt: Date())
    }

    private static func verify(_ window: NSWindow, step: Int, startedAt: Date) {
        guard step < checkDelays.count else {
            log.error("활성화 실패 — 창은 앞에 있지만 앱이 비활성이라 한글 입력이 막힌다")
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + checkDelays[step]) {
            let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)

            guard window.isVisible else {
                log.error("확인 시점에 창이 보이지 않는다 — 대상을 잘못 잡았을 수 있다: \(describe(window), privacy: .public)")
                return
            }
            guard !NSApp.isActive else {
                // 앱은 활성인데 창이 key/main 이 아니면 원인이 «앱 활성화» 가 아니라는 뜻이다.
                if !window.isKeyWindow || !window.isMainWindow {
                    log.error("앱은 활성인데 창이 key/main 이 아니다 (경과 \(elapsed)ms): \(describe(window), privacy: .public)")
                }
                return
            }

            log.warning("활성화 요청이 밀렸다 — 재시도 \(step + 1) (경과 \(elapsed)ms)")
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            verify(window, step: step + 1, startedAt: startedAt)
        }
    }

    /// 어떤 창을 잡았는지 한 줄로. 제목만 보면 팝오버 패널과 통합 윈도우가 구분되지 않는다.
    private static func describe(_ window: NSWindow) -> String {
        let id = window.identifier?.rawValue ?? "-"
        return "\(type(of: window)) id=\(id) title=\(window.title) visible=\(window.isVisible) key=\(window.isKeyWindow) main=\(window.isMainWindow) appActive=\(NSApp.isActive)"
    }
}
