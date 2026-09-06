import Foundation

/// 바깥에서 그날의 수면 시간을 가져온다. 구현은 `Data/Adapters/` 에 있다.
///
/// 과거 건강 앱 연동을 읽던 경계. 현재 앱에서는 구현체를 조립하지 않고 수면을 직접 입력한다.
/// 그러면 «직접 입력한 값을 건강 앱이 덮어쓰지 않는다» 같은 규칙을 테스트할 수 없다.
@MainActor
protocol SleepGateway {
    /// 이 기기에서 쓸 수 있는지. 못 쓰면 화면이 «직접 입력하세요» 로 안내한다.
    var isAvailable: Bool { get }

    /// 못 가져오면 `nil`. 권한 거절과 «그날 잠 기록이 없음» 을 구분하지 않는다 —
    /// 화면이 할 일이 어느 쪽이든 같기 때문이다.
    func sleepHours(on day: Date, calendar: Calendar) async -> Double?
}
