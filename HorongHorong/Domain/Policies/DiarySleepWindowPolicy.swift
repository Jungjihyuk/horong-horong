import Foundation

/// 그날 밤의 수면 구간.
///
/// **길이는 저장하지 않고 시작·끝에서 계산한다.** 사실로 남는 것은 «몇 시에 자서 몇 시에 깼는가»
/// 이고, «몇 시간 잤는가» 는 그 둘에서 언제든 다시 나온다.
struct DiarySleepWindow: Equatable, Sendable {
    let start: Date
    let end: Date

    var duration: TimeInterval { end.timeIntervalSince(start) }
    var hours: Double { duration / 3600 }
}

/// 수면 타임라인의 좌표를 정한다.
///
/// **바깥 환경을 읽지 않는다.** `Date()` 나 `Calendar.current` 를 안에서 부르면 자정 근처에서
/// 결과가 달라지고 테스트가 시계에 매인다. 기준 날짜·달력·축은 항상 매개변수로 받는다.
enum DiarySleepWindowPolicy {
    /// 손잡이를 끌 때 붙는 눈금. 1분 단위는 정확히 짚기 어렵고 30분 단위는 «23시 40분» 을 못 적는다.
    static let snapMinutes = 5

    /// 취침과 기상이 붙어 버리지 않도록 지키는 최소 길이.
    static let minimumMinutes = 15

    /// 기록이 없을 때 타임라인이 처음 보여 주는 구간.
    static let defaultBedHour = 23
    static let defaultWakeHour = 7

    // MARK: - 축 위의 좌표

    /// 축 위 비율(0…1) → 실제 시각. 눈금에 맞춰 붙인다.
    static func date(atFraction fraction: Double, day: Date, axis: DiarySleepAxis, calendar: Calendar) -> Date {
        let origin = axis.start(of: day, calendar: calendar)
        let clamped = min(max(fraction, 0), 1)
        return snap(origin.addingTimeInterval(clamped * axis.hours * 3600), from: origin)
    }

    /// 실제 시각 → 축 위 비율(0…1). **축 밖은 양 끝으로 자른다** — 축을 좁게 잡아 둔 사람의
    /// 낮잠이나 아주 이른 취침도 막대가 사라지는 대신 끝에 붙어 «축을 넘어갔다» 가 보인다.
    static func fraction(of date: Date, day: Date, axis: DiarySleepAxis, calendar: Calendar) -> Double {
        let origin = axis.start(of: day, calendar: calendar)
        let value = date.timeIntervalSince(origin) / (axis.hours * 3600)
        return min(max(value, 0), 1)
    }

    // MARK: - 구간 만들기

    /// 기상이 취침보다 앞서거나 같으면 자정을 넘긴 것으로 읽어 하루 뒤로 민다.
    static func normalize(start: Date, end: Date) -> DiarySleepWindow {
        guard end <= start else { return DiarySleepWindow(start: start, end: end) }
        return DiarySleepWindow(start: start, end: end.addingTimeInterval(24 * 3600))
    }

    /// 시간만 남아 있는 옛 기록을 축 위에 놓는다.
    ///
    /// 시작 시각을 모르므로 **기상 7시를 기준으로 역산**한다. 없는 사실을 지어내는 셈이지만,
    /// 그래프에서 그 날이 통째로 사라지는 것보다는 길이를 살려 두는 편이 낫다.
    static func window(hours: Double, day: Date, calendar: Calendar) -> DiarySleepWindow {
        let dayStart = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .hour, value: defaultWakeHour, to: dayStart) ?? dayStart
        return DiarySleepWindow(start: end.addingTimeInterval(-max(0, hours) * 3600), end: end)
    }

    /// 아직 아무것도 적지 않았을 때 손잡이가 놓이는 자리. 전날 23시 → 당일 7시.
    ///
    /// 축을 좁게 잡아 둔 사람에게는 이 기본값이 축 밖일 수 있으므로 **비율로 한 번 돌려 잘라
    /// 넣는다** — 손잡이가 화면 밖에 있으면 잡을 수 없다.
    static func defaultWindow(for day: Date, axis: DiarySleepAxis, calendar: Calendar) -> DiarySleepWindow {
        let dayStart = calendar.startOfDay(for: day)
        let bed = calendar.date(byAdding: .hour, value: defaultBedHour - 24, to: dayStart) ?? dayStart
        let wake = calendar.date(byAdding: .hour, value: defaultWakeHour, to: dayStart) ?? dayStart
        let clampedBed = date(atFraction: fraction(of: bed, day: day, axis: axis, calendar: calendar), day: day, axis: axis, calendar: calendar)
        let clampedWake = date(atFraction: fraction(of: wake, day: day, axis: axis, calendar: calendar), day: day, axis: axis, calendar: calendar)
        // 자르고 나서 둘이 겹쳤다면 최소 길이만큼 벌린다.
        guard clampedWake.timeIntervalSince(clampedBed) < Double(minimumMinutes) * 60 else {
            return DiarySleepWindow(start: clampedBed, end: clampedWake)
        }
        return DiarySleepWindow(start: clampedBed, end: clampedBed.addingTimeInterval(Double(minimumMinutes) * 60))
    }

    // MARK: - 내부

    /// 축의 시작점을 기준으로 눈금에 붙인다. 축이 정시에서 출발하므로 결과도 정시 + 5분 배수다.
    private static func snap(_ date: Date, from origin: Date) -> Date {
        let step = Double(snapMinutes) * 60
        let steps = (date.timeIntervalSince(origin) / step).rounded()
        return origin.addingTimeInterval(steps * step)
    }
}
