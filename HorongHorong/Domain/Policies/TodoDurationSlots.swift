import Foundation

/// «걸리는 시간» 줄에 놓이는 네 칸.
///
/// **왼쪽 둘은 최근에 쓴 값이 흘러가고, 오른쪽 둘은 사용자가 박아 둔 값이다.**
/// 직접 입력한 5분이 다음에도 한 번에 잡히려면 어딘가 남아야 하는데, 네 칸을 모두 흘려보내면
/// 늘 쓰는 «1시간» 이 밀려나 버린다. 그래서 절반만 흐르게 두고 절반은 고정한다.
///
/// 순수 계산만 한다 — 저장은 화면이 맡는다. 그래야 «다섯 번 쓰면 무엇이 남는가» 를
/// 저장소 없이 검사할 수 있다.
enum TodoDurationSlots {
    struct Slot: Identifiable, Equatable, Sendable {
        let minutes: Int
        let isPinned: Bool

        var id: Int { minutes }
    }

    static let dynamicCount = 2
    static let pinnedCount = 2
    static let slotCount = dynamicCount + pinnedCount

    static let defaultRecent = [15, 30]
    static let defaultPinned = [60, 120]

    /// 화면에 그릴 네 칸. 왼쪽 둘이 유동, 오른쪽 둘이 고정이다.
    static func slots(recent: [Int], pinned: [Int]) -> [Slot] {
        let clean = normalized(recent: recent, pinned: pinned)
        return clean.recent.map { Slot(minutes: $0, isPinned: false) }
            + clean.pinned.map { Slot(minutes: $0, isPinned: true) }
    }

    /// 방금 쓴 길이를 최근 목록 맨 앞에 올린다. 고정 칸에 이미 있는 값은 흘리지 않는다 —
    /// 같은 값이 두 칸을 차지하면 고를 수 있는 길이가 셋으로 줄어든다.
    static func remembering(_ minutes: Int, recent: [Int], pinned: [Int]) -> [Int] {
        let clean = normalized(recent: recent, pinned: pinned)
        guard minutes > 0, !clean.pinned.contains(minutes) else { return clean.recent }
        return Array(([minutes] + clean.recent.filter { $0 != minutes }).prefix(dynamicCount))
    }

    /// 고정 칸으로 옮긴다. 밀려난 고정 값은 버리지 않고 최근 목록으로 내려보낸다.
    static func pinning(_ minutes: Int, recent: [Int], pinned: [Int]) -> (recent: [Int], pinned: [Int]) {
        let clean = normalized(recent: recent, pinned: pinned)
        guard minutes > 0, !clean.pinned.contains(minutes) else { return clean }

        let nextPinned = Array(([minutes] + clean.pinned).prefix(pinnedCount))
        let evicted = clean.pinned.filter { !nextPinned.contains($0) }
        let nextRecent = evicted + clean.recent.filter { $0 != minutes }
        return normalized(recent: nextRecent, pinned: nextPinned)
    }

    /// 고정을 푼다. 오른쪽 칸이 비지 않도록 최근 목록에서 한 칸을 끌어 올린다.
    static func unpinning(_ minutes: Int, recent: [Int], pinned: [Int]) -> (recent: [Int], pinned: [Int]) {
        let clean = normalized(recent: recent, pinned: pinned)
        guard clean.pinned.contains(minutes) else { return clean }

        let keptPinned = clean.pinned.filter { $0 != minutes }
        // 빈 오른쪽 칸은 **직접** 채운다. 기본값 메우기에 맡기면 방금 푼 값이 도로 들어온다.
        // 끌어 올리는 것은 최근 목록의 **뒤쪽** — 어차피 다음 값에 밀려날 자리라,
        // 거기를 고정하면 네 칸에 남는 서로 다른 길이가 가장 오래 유지된다.
        let promoted = clean.recent.last { !keptPinned.contains($0) && $0 != minutes }
        let nextPinned = keptPinned + (promoted.map { [$0] } ?? [])
        // 푼 값은 최근 목록 맨 앞으로 — 방금까지 쓰던 값이 사라지면 놀란다.
        let nextRecent = [minutes] + clean.recent.filter { $0 != promoted }
        return normalized(recent: nextRecent, pinned: nextPinned)
    }

    /// 저장된 값은 언제든 망가져 있을 수 있다 — 개수가 모자라거나, 겹치거나, 0 이거나.
    /// 화면이 늘 네 칸을 그릴 수 있도록 여기서 한 번에 손본다. 고정이 우선이다.
    static func normalized(recent: [Int], pinned: [Int]) -> (recent: [Int], pinned: [Int]) {
        let cleanPinned = fill(pinned, count: pinnedCount, from: defaultPinned + defaultRecent, excluding: [])
        let cleanRecent = fill(recent, count: dynamicCount, from: defaultRecent + defaultPinned, excluding: cleanPinned)
        return (cleanRecent, cleanPinned)
    }

    private static func fill(_ values: [Int], count: Int, from fallback: [Int], excluding taken: [Int]) -> [Int] {
        var result: [Int] = []
        for value in values + fallback where value > 0 {
            guard !result.contains(value), !taken.contains(value) else { continue }
            result.append(value)
            if result.count == count { break }
        }
        return result
    }

    // MARK: - 저장 형식

    /// `UserDefaults` 에는 «15,30» 처럼 적는다. 배열 하나를 위해 별도 저장소를 두지 않는다.
    static func decode(_ text: String) -> [Int] {
        text.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    static func encode(_ values: [Int]) -> String {
        values.map(String.init).joined(separator: ",")
    }
}

/// 걸리는 시간을 사람 말로 옮긴다. 프리셋이 아닌 임의의 분값도 다뤄야 한다.
enum TodoDurationText {
    /// «5분», «1시간», «1시간 30분».
    static func title(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours > 0 && rest > 0 { return "\(hours)시간 \(rest)분" }
        if hours > 0 { return "\(hours)시간" }
        return "\(rest)분"
    }

    /// 칩 아랫줄에 **끝나는 시각**을 적는다 — «1시간» 보다 «~9:00» 이 바로 와닿는다.
    /// «까지» 를 물결로 줄인 것은 넷이 한 줄에 들어가야 하기 때문이다.
    static func endLabel(start: Date, minutes: Int, calendar: Calendar = .current) -> String {
        let end = start.addingTimeInterval(TimeInterval(minutes * 60))
        let parts = calendar.dateComponents([.hour, .minute], from: end)
        return String(format: "~%d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
