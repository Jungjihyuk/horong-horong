import Foundation

/// 한 감정에서 다른 감정으로 넘어간 횟수.
struct DiaryMoodTransition: Identifiable, Equatable, Sendable {
    let from: DiaryMoodGroup
    let to: DiaryMoodGroup
    let count: Int

    /// 방향이 다르면 다른 전이다 — «걱정 → 지침» 과 «지침 → 걱정» 은 같은 이야기가 아니다.
    var id: String { "\(from.rawValue)>\(to.rawValue)" }
}

/// 감정이 어떤 순서로 바뀌는지 센다.
enum DiaryMoodTransitionPolicy {
    /// 연속한 두 관측을 이어 전이를 만든다.
    ///
    /// **같은 영역이 이어진 경우(self-transition)는 세지 않는다.** 그건 지속(streak)이 답하는
    /// 질문이고, 세면 원형 지도가 일곱 개의 자기 고리에 파묻혀 정작 «어디로 흘러가는가» 가 안 보인다.
    ///
    /// 입력은 시간 순으로 정렬된 «기록된» 관측만 담아야 한다. 빈 칸을 건너뛰어 이으면
    /// 3주 떨어진 두 감정이 이웃으로 둔갑한다.
    static func transitions(_ points: [DiaryMoodPoint]) -> [DiaryMoodTransition] {
        guard points.count >= 2 else { return [] }

        var counts: [String: (from: DiaryMoodGroup, to: DiaryMoodGroup, count: Int)] = [:]
        for (previous, next) in zip(points, points.dropFirst()) {
            let from = previous.mood.group
            let to = next.mood.group
            guard from != to else { continue }
            let key = "\(from.rawValue)>\(to.rawValue)"
            counts[key, default: (from, to, 0)].count += 1
        }

        return counts.values
            .map { DiaryMoodTransition(from: $0.from, to: $0.to, count: $0.count) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.id < rhs.id
            }
    }
}
