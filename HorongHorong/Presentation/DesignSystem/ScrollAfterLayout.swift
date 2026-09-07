import SwiftUI

extension ScrollViewProxy {
    /// 배치가 **끝난 뒤에** 스크롤한다.
    ///
    /// `onAppear`·`onChange` 는 SwiftUI 갱신 주기 **안에서** 불린다. 그 안에서 `scrollTo` 를
    /// 부르면 스크롤 위치가 바뀌고 → 지연 컨테이너(`LazyVStack` 등)가 새 항목을 만들고 →
    /// 그게 다시 배치를 부르면서 **트랜잭션이 중첩된다.** 풀리지 않고 쌓이면 앱이 멈춘다.
    ///
    /// 2026-09-07 조사에서 멈춘 프로세스를 3초 간격으로 샘플링하니 `sizeThatFits` 재귀 깊이가
    /// **62 → 90 → 172** 로 계속 자랐고, 그 최심부에 `GraphHost.runTransaction` 이 중첩돼 있었다.
    /// 한 턴 뒤로 미루면 스크롤이 별도 트랜잭션에서 일어나 이 중첩이 생기지 않는다.
    ///
    /// - Parameter animation: `nil` 이면 애니메이션 없이 즉시 옮긴다.
    @MainActor
    func scrollAfterLayout(
        to id: some Hashable,
        anchor: UnitPoint = .center,
        animation: Animation? = nil
    ) {
        Task { @MainActor in
            guard let animation else {
                scrollTo(id, anchor: anchor)
                return
            }
            withAnimation(animation) { scrollTo(id, anchor: anchor) }
        }
    }
}
