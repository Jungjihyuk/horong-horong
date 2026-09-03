import Foundation

/// 뉴스 수집·요약 파이프라인을 돌린다. 구현은 `Data/Adapters/` 에 있다.
///
/// **시작만 시킨다.** 진행 단계·경과 시간·오류는 파이프라인 쪽이 스스로 알리고 화면이
/// 그걸 직접 관찰한다 — 그 상태까지 이 계약에 담으면 관찰이 끊긴다(`@Observable` 은
/// 프로토콜 뒤에서 추적되지 않는다). `[확인 필요]`
@MainActor
protocol NewsPipelineGateway {
    /// 저장된 설정으로 한 번 실행한다.
    func launch()
}
