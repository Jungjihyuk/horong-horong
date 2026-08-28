import Foundation

/// 단계마다 걸린 시간을 재는 작은 시계.
///
/// 총 시간만으로는 진단이 안 된다. 실측 예: 목표 추천 한 번이 58초 걸렸는데,
/// 그게 프롬프트를 만드느라 그런 건지 모델이 안 돌아와서 그런 건지 **로그로는 알 수 없었다**.
/// 타임스탬프 차이로 손계산하려 해도 줄이 아홉 개라 서로 맞춰야 했다.
///
/// `mark` 는 **직전 표시 이후** 걸린 시간을 적는다. 같은 이름을 두 번 표시하면 더해진다 —
/// 재시도처럼 한 단계를 여러 번 지나는 경우를 그대로 담기 위해서다.
final class StepClock {
    private var last: DispatchTime
    private(set) var elapsed: [String: Int] = [:]

    init() {
        last = DispatchTime.now()
    }

    func mark(_ step: String) {
        let now = DispatchTime.now()
        let ms = Int((now.uptimeNanoseconds &- last.uptimeNanoseconds) / 1_000_000)
        elapsed[step, default: 0] += ms
        last = now
    }
}
