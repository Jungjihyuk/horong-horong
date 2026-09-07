import Foundation

/// 한 감정 영역이 «한 번 오면 얼마나 머무는가».
struct DiaryMoodStreakSummary: Identifiable, Equatable, Sendable {
    let group: DiaryMoodGroup
    /// 이 영역이 몇 번 «찾아왔는가». 연속된 칸은 한 번으로 센다.
    let runCount: Int
    /// 한 번 찾아오면 평균 몇 칸 이어졌는가.
    let averageLength: Double
    let longestLength: Int
    /// 전체 기록 중 이 영역이 차지한 칸 수.
    let totalCount: Int

    var id: DiaryMoodGroup { group }
}

/// 감정이 이어진 길이를 잰다.
///
/// **점수를 매기지 않는다.** 어떤 감정이 더 좋은지 판단하는 대신 «무엇이 오래 머무는지» 만 본다.
enum DiaryMoodStreakPolicy {
    /// 이어진 같은 영역을 한 덩어리로 묶는다.
    ///
    /// **입력은 이미 시간 순으로 정렬돼 있어야 하고, 기록이 없는 칸은 애초에 들어오지 않는다.**
    /// 안 적은 날을 «같은 감정이 이어졌다» 로 읽으면 없는 사실을 지어내는 셈이라, 빈 칸을
    /// 건너뛰어 잇지 않고 그 자리에서 흐름이 끊긴 것으로 본다 — 그래서 호출부가 연속한
    /// 관측만 넘겨야 한다.
    ///
    /// 결과는 오래 머무는 감정부터, 같으면 자주 오는 감정부터 정렬한다.
    static func summarize(_ points: [DiaryMoodPoint]) -> [DiaryMoodStreakSummary] {
        guard !points.isEmpty else { return [] }

        var runs: [DiaryMoodGroup: [Int]] = [:]
        var currentGroup = points[0].mood.group
        var currentLength = 0

        for point in points {
            let group = point.mood.group
            if group == currentGroup {
                currentLength += 1
            } else {
                runs[currentGroup, default: []].append(currentLength)
                currentGroup = group
                currentLength = 1
            }
        }
        runs[currentGroup, default: []].append(currentLength)

        return runs.compactMap { group, lengths -> DiaryMoodStreakSummary? in
            guard !lengths.isEmpty else { return nil }
            let total = lengths.reduce(0, +)
            return DiaryMoodStreakSummary(
                group: group,
                runCount: lengths.count,
                averageLength: Double(total) / Double(lengths.count),
                longestLength: lengths.max() ?? 0,
                totalCount: total
            )
        }
        .sorted { lhs, rhs in
            if lhs.averageLength != rhs.averageLength { return lhs.averageLength > rhs.averageLength }
            if lhs.totalCount != rhs.totalCount { return lhs.totalCount > rhs.totalCount }
            return lhs.group.rawValue < rhs.group.rawValue
        }
    }
}
