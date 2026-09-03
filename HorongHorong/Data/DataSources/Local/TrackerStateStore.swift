import Foundation
import Observation

/// 휴가로 표시할 날짜 범위. start, end 모두 포함(inclusive).
struct VacationRange: Codable, Identifiable, Equatable {
    let id: UUID
    var start: Date
    var end: Date
    var label: String

    init(id: UUID = UUID(), start: Date, end: Date, label: String = "") {
        self.id = id
        // start ≤ end 보장 + 하루 단위로 정규화.
        let cal = Calendar.current
        let s = cal.startOfDay(for: min(start, end))
        let e = cal.startOfDay(for: max(start, end))
        self.start = s
        self.end = e
        self.label = label
    }

    func contains(_ date: Date) -> Bool {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        return day >= start && day <= end
    }

    var dayCount: Int {
        let cal = Calendar.current
        let components = cal.dateComponents([.day], from: start, to: end)
        return (components.day ?? 0) + 1
    }
}

/// 추적 기능의 상태(전체 ON/OFF, 민감 작업 일시 정지, 휴가 기간 목록)를 관리한다.
/// AppTracker 가 매 폴링마다 `shouldRecord(at:)` 를 검사해 기록 여부를 결정한다.
@Observable
final class TrackerStateStore: @unchecked Sendable {
    static let shared = TrackerStateStore()

    private let enabledKey = "tracker.enabled"
    private let sensitiveKey = "tracker.sensitiveMode"
    private let vacationsKey = "tracker.vacations.v1"
    private let manualAwayStartedAtKey = "tracker.manualAwayStartedAt"

    var isTrackingEnabled: Bool {
        didSet { UserDefaults.standard.set(isTrackingEnabled, forKey: enabledKey) }
    }

    var isSensitiveMode: Bool {
        didSet { UserDefaults.standard.set(isSensitiveMode, forKey: sensitiveKey) }
    }

    private(set) var manualAwayStartedAt: Date? {
        didSet {
            if let manualAwayStartedAt {
                UserDefaults.standard.set(manualAwayStartedAt, forKey: manualAwayStartedAtKey)
            } else {
                UserDefaults.standard.removeObject(forKey: manualAwayStartedAtKey)
            }
        }
    }

    private(set) var vacationRanges: [VacationRange]

    private init() {
        let defaults = UserDefaults.standard
        // enabled 키가 없을 땐 기본 true.
        isTrackingEnabled = (defaults.object(forKey: enabledKey) as? Bool) ?? true
        isSensitiveMode = defaults.bool(forKey: sensitiveKey)
        manualAwayStartedAt = defaults.object(forKey: manualAwayStartedAtKey) as? Date
        if let data = defaults.data(forKey: vacationsKey),
           let decoded = try? JSONDecoder().decode([VacationRange].self, from: data) {
            vacationRanges = decoded.sorted { $0.start < $1.start }
        } else {
            vacationRanges = []
        }
    }

    /// 지금/특정 시점에 기록을 남겨야 하는지.
    func shouldRecord(at date: Date = Date()) -> Bool {
        guard isTrackingEnabled else { return false }
        guard !isSensitiveMode else { return false }
        guard manualAwayStartedAt == nil else { return false }
        guard vacationRange(containing: date) == nil else { return false }
        return true
    }

    func markManualAway(startedAt: Date = Date()) {
        manualAwayStartedAt = startedAt
    }

    func clearManualAway() {
        manualAwayStartedAt = nil
    }

    func vacationRange(containing date: Date) -> VacationRange? {
        vacationRanges.first { $0.contains(date) }
    }

    func vacationCount(in startDate: Date, end endDate: Date) -> Int {
        let cal = Calendar.current
        let s = cal.startOfDay(for: startDate)
        let e = cal.startOfDay(for: endDate)
        var count = 0
        for range in vacationRanges {
            // 겹치는 일수 계산.
            let overlapStart = max(range.start, s)
            let overlapEnd = min(range.end, cal.date(byAdding: .day, value: -1, to: e) ?? e)
            if overlapStart <= overlapEnd {
                let days = (cal.dateComponents([.day], from: overlapStart, to: overlapEnd).day ?? 0) + 1
                count += days
            }
        }
        return count
    }

    func addVacation(start: Date, end: Date, label: String) {
        let range = VacationRange(start: start, end: end, label: label.trimmingCharacters(in: .whitespacesAndNewlines))
        vacationRanges.append(range)
        vacationRanges.sort { $0.start < $1.start }
        persistVacations()
    }

    func removeVacation(id: UUID) {
        vacationRanges.removeAll { $0.id == id }
        persistVacations()
    }

    private func persistVacations() {
        if let data = try? JSONEncoder().encode(vacationRanges) {
            UserDefaults.standard.set(data, forKey: vacationsKey)
        }
    }
}
