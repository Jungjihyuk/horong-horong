import Foundation

/// 수면을 사람이 읽는 글로 바꾼다.
///
/// 편집기·타임라인·인사이트가 모두 이 한 곳을 쓴다. 전에는 같은 구현이 두 파일에 따로 있어
/// 한쪽만 고치면 화면마다 «7.5시간» 과 «7시간 30분» 이 섞였다.
@MainActor
enum DiarySleepText {
    /// "7시간 30분"
    static func duration(_ hours: Double) -> String {
        let totalMinutes = Int((hours * 60).rounded())
        let wholeHours = totalMinutes / 60
        let minutes = totalMinutes % 60
        guard minutes > 0 else { return "\(wholeHours)시간" }
        return "\(wholeHours)시간 \(minutes)분"
    }

    /// "23:40"
    static func clock(_ date: Date) -> String { clockFormatter.string(from: date) }

    /// "23:40 → 07:10 (7시간 30분)"
    static func range(_ window: DiarySleepWindow) -> String {
        "\(clock(window.start)) → \(clock(window.end)) (\(duration(window.hours)))"
    }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
