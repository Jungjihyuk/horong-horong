import Foundation

/// 수면 타임라인의 가로축.
///
/// 상수가 아니라 값인 이유: 사람마다 자는 시간대가 다르다. 새벽 4시에 자는 사람에게 «전날 21시 →
/// 당일 12시» 축은 절반이 빈 자리다. 설정에서 범위와 눈금 간격을 바꿀 수 있어야 한다.
///
/// **저장소(UserDefaults)를 여기서 읽지 않는다.** 화면이 읽어 값으로 넘긴다 — 그래야 축 계산을
/// 설정과 무관하게 테스트할 수 있다.
struct DiarySleepAxis: Equatable, Sendable {
    /// 축이 시작하는 시각. 일기 날짜의 **전날** 시각이다(자정 이후 값이면 당일).
    let startHour: Int
    /// 축이 끝나는 시각. 일기 날짜 **당일**이다.
    let endHour: Int
    /// 눈금을 몇 시간마다 세울지.
    let tickInterval: Int

    /// 대부분의 밤잠이 들어가는 구간. 21시부터 정오까지 15시간.
    static let `default` = DiarySleepAxis(startHour: 21, endHour: 12, tickInterval: 1)

    /// 설정에서 고를 수 있는 값들. 축이 뒤집히거나 0시간이 되는 조합을 막는다.
    static let selectableHours = Array(0...23)
    static let selectableTickIntervals = [1, 2, 3, 4, 6]

    init(startHour: Int, endHour: Int, tickInterval: Int) {
        let start = Self.wrapped(startHour)
        let end = Self.wrapped(endHour)
        self.startHour = start
        self.endHour = end
        // 시작과 끝이 같으면 하루 전체로 읽는다 — 0시간짜리 축은 그릴 수 없다.
        let span = (end - start + 24) % 24
        let hours = span == 0 ? 24 : span
        self.tickInterval = min(max(tickInterval, 1), hours)
    }

    /// 축 길이(시간).
    var hours: Double {
        let span = (endHour - startHour + 24) % 24
        return Double(span == 0 ? 24 : span)
    }

    /// 축의 왼쪽 끝. 끝 시각보다 늦게 시작하면 전날로 넘긴다.
    func start(of day: Date, calendar: Calendar) -> Date {
        let dayStart = calendar.startOfDay(for: day)
        // 21시처럼 끝(12시)보다 큰 시작 시각은 전날 것이다.
        let offset = startHour >= endHour ? startHour - 24 : startHour
        return calendar.date(byAdding: .hour, value: offset, to: dayStart) ?? dayStart
    }

    func end(of day: Date, calendar: Calendar) -> Date {
        start(of: day, calendar: calendar).addingTimeInterval(hours * 3600)
    }

    /// 축 위 비율(0…1)에 놓인 시각의 «몇 시».
    func hour(atFraction fraction: Double) -> Int {
        let offset = Int((fraction * hours).rounded())
        return Self.wrapped(startHour + offset)
    }

    /// 눈금 시각과 그 비율. 마지막 눈금은 축 끝에 정확히 붙는다.
    var ticks: [(hour: Int, fraction: Double)] {
        let total = Int(hours)
        var offsets = Array(stride(from: 0, through: total, by: tickInterval))
        if offsets.last != total { offsets.append(total) }
        return offsets.map { (Self.wrapped(startHour + $0), Double($0) / hours) }
    }

    /// 좁은 화면용으로 솎아 낸 눈금.
    ///
    /// 설정한 간격을 그대로 쓰면 15시간 축에 1시간 간격 눈금 16개가 260pt 안에 겹쳐 아무것도
    /// 안 읽힌다. 설정을 무시하는 것이 아니라 **읽을 수 있는 만큼만 남긴다.**
    func ticks(maximumCount: Int) -> [(hour: Int, fraction: Double)] {
        let all = ticks
        guard maximumCount > 1, all.count > maximumCount else { return all }
        let step = Int((Double(all.count) / Double(maximumCount)).rounded(.up))
        var thinned = stride(from: 0, to: all.count, by: max(step, 1)).map { all[$0] }
        if let last = all.last, thinned.last?.fraction != last.fraction { thinned.append(last) }
        return thinned
    }

    private static func wrapped(_ hour: Int) -> Int { ((hour % 24) + 24) % 24 }
}
