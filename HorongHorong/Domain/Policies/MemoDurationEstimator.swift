import Foundation

/// 미리알림을 메모로 가져올 때 붙일 "얼마나 걸릴 일인가"를 지난 메모에서 미루어 본다.
///
/// 미리알림 앱에는 시각이 하나뿐이라 언제 시작하는지만 알 수 있고 얼마나 걸리는지는 알 수 없다.
/// 그렇다고 가져올 때마다 사용자가 손으로 마감을 정하는 건 번거롭다. 그래서 이미 쌓여 있는
/// 메모(시작일과 마감이 둘 다 있는 것)를 이력 삼아 추정한다. 별도 저장소를 두지 않는 이유는
/// 필요한 기록이 이미 메모 안에 있기 때문이다.
enum MemoDurationEstimator {
    /// 이력이 없을 때 쓰는 값. 짧게 잡으면 시작하자마자 마감이 지나 "지각" 상태가 되어 더 불편하다.
    static let fallback: TimeInterval = 60 * 60

    /// 사람이 실제로 그렇게 쓸 법한 범위. 이 밖의 값은 잘못 입력된 것으로 보고 이력에서 뺀다.
    private static let plausible: ClosedRange<TimeInterval> = 60...(12 * 60 * 60)

    /// 개인화를 시작하기 전에 필요한 최소 이력. 이보다 적으면 몇 건 안 되는 기록이
    /// 전체 성향인 양 굳어져서, 사용자가 예측할 수 없는 값이 나온다.
    private static let minimumHistory = 5

    /// 같은 일을 전에도 했다면 그때 걸린 만큼, 아니면 평소 걸리던 만큼, 그것도 없으면 기본값.
    ///
    /// - Parameters:
    ///   - title: 가져오는 미리알림의 제목.
    ///   - history: 이력으로 볼 기존 메모들.
    static func estimate(title: String, history: [Memo]) -> TimeInterval {
        let samples = self.samples(from: history)
        // 이력이 얼마 없을 때는 넘겨짚지 않고 기본값을 쓴다.
        guard samples.count >= minimumHistory else { return fallback }

        // 같은 할일이 되풀이된 적이 있으면 그쪽을 우선한다. 한 번뿐인 기록은 우연일 수 있어 2개부터 믿는다.
        let key = normalize(title)
        let repeated = samples.filter { $0.key == key }.map(\.duration)
        if repeated.count >= 2 {
            return median(repeated)
        }

        // 되풀이 이력이 없으면 이 사람의 평소 소요 시간으로 대신한다.
        return median(samples.map(\.duration))
    }

    /// 제목에서 회차·날짜·기호를 걷어내 "같은 할일"로 알아보게 만든다.
    ///
    /// 예: "주간 회의 3회차" 와 "주간 회의 5회차" 를 같은 것으로 본다.
    static func normalize(_ title: String) -> String {
        title
            .lowercased()
            .components(separatedBy: CharacterSet.decimalDigits.union(.punctuationCharacters).union(.symbols))
            .joined(separator: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private struct Sample {
        let key: String
        let duration: TimeInterval
    }

    private static func samples(from history: [Memo]) -> [Sample] {
        history.compactMap { memo in
            guard let start = memo.startDate, let deadline = memo.deadline else { return nil }
            let duration = deadline.timeIntervalSince(start)
            guard plausible.contains(duration) else { return nil }
            return Sample(key: normalize(firstLine(of: memo.content)), duration: duration)
        }
    }

    /// 메모 제목은 첫 줄이다. 미리알림에서 가져온 메모도 같은 규칙으로 만들어진다.
    private static func firstLine(of content: String) -> String {
        content
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    /// 평균 대신 중앙값을 쓴다. 한 번 크게 미뤄진 기록이 전체를 끌고 가지 않도록.
    private static func median(_ values: [TimeInterval]) -> TimeInterval {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}
