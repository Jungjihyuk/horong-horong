import Foundation
import Observation

/// 일기 화면의 상태.
///
/// **`@Query` 를 쓰지 않는다.** 예전에는 일기 전량을 가져와 날짜 사전을 지었다 —
/// 하루 한 장씩 늘기만 하므로 해가 갈수록 커진다. 지금은 **보고 있는 달만** 가져온다.
@MainActor
@Observable
final class DiaryViewModel {
    private(set) var visibleMonth: Date
    private(set) var selectedDay: Date
    /// 보고 있는 달의 기록. 달력 칸이 배열을 훑지 않도록 날짜로 찾을 수 있게 둔다.
    private(set) var monthEntries: [Date: DiaryDay] = [:]
    private(set) var selected: DiaryDay?
    private(set) var isPullingSleep = false

    /// 편집 중인 본문. **타건은 여기서 끝난다** — 저장은 400ms 뒤 한 번.
    var bodyDraft = ""

    private let repository: DiaryRepository
    private let sleep: SleepGateway
    private let calendar: Calendar
    private var saveTask: Task<Void, Never>?
    private var sleepTask: Task<Void, Never>?

    init(repository: DiaryRepository, sleep: SleepGateway, calendar: Calendar = .current) {
        self.repository = repository
        self.sleep = sleep
        self.calendar = calendar
        let today = calendar.startOfDay(for: Date())
        visibleMonth = today
        selectedDay = today
    }

    var isSleepAvailable: Bool { sleep.isAvailable }

    /// 이 달에 기록한 날 수.
    var writtenCount: Int { monthEntries.count }

    func entry(on day: Date) -> DiaryDay? { monthEntries[day] }

    // MARK: - 읽기

    func reload() {
        let entries = (try? repository.entries(inMonthOf: visibleMonth)) ?? []
        // 같은 날짜가 둘이어도 죽지 않게 관대하게 짓는다. 중복을 막는 일은 저장소가 한다.
        monthEntries = Dictionary(entries.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        refreshSelected()
    }

    func select(_ day: Date) {
        flush()
        let normalized = calendar.startOfDay(for: day)
        selectedDay = normalized
        // 달을 넘는 날을 고르면 달력도 따라간다 — 고른 날이 안 보이면 «어디 갔지» 가 된다.
        if !calendar.isDate(normalized, equalTo: visibleMonth, toGranularity: .month) {
            visibleMonth = normalized
            reload()
        } else {
            refreshSelected()
        }
        pullSleepIfNeeded()
    }

    func shiftMonth(_ delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: visibleMonth) else { return }
        visibleMonth = next
        reload()
    }

    func goToToday() {
        select(Date())
    }

    // MARK: - 쓰기

    func setMood(_ mood: DiaryMood) {
        // 같은 것을 다시 누르면 해제한다.
        apply { try repository.setMood(on: selectedDay, mood: selected?.mood == mood ? nil : mood) }
    }

    func setStress(_ value: Int) {
        apply { try repository.setStress(on: selectedDay, stress: selected?.stress == value ? nil : value) }
    }

    func setSleepHours(_ hours: Double) {
        apply { try repository.setSleep(on: selectedDay, hours: hours, source: .manual) }
    }

    func draftChanged() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.persistDraft()
        }
    }

    func flush() {
        saveTask?.cancel()
        saveTask = nil
        persistDraft()
    }

    // MARK: - 수면 가져오기

    /// 직접 입력한 값이 있으면 건드리지 않는다.
    func pullSleepIfNeeded() {
        guard selected?.sleepSource != .manual else { return }
        pullSleep(force: false)
    }

    /// `force` 는 «건강 앱에서 가져오기» 를 사용자가 직접 눌렀을 때다.
    /// 그때만 직접 입력한 값을 덮어쓴다 — 사용자가 그러라고 시켰으므로.
    func pullSleep(force: Bool) {
        sleepTask?.cancel()
        isPullingSleep = true
        let day = selectedDay
        sleepTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let hours = await self.sleep.sleepHours(on: day, calendar: self.calendar)
            self.isPullingSleep = false
            guard !Task.isCancelled, let hours, self.selectedDay == day else { return }
            // 가져오는 사이에 사용자가 직접 입력했을 수 있다. 다시 확인한다.
            if !force, self.selected?.sleepSource == .manual { return }
            self.apply { try self.repository.setSleep(on: day, hours: hours, source: .healthKit) }
        }
    }

    // MARK: - 내부

    private func persistDraft() {
        guard bodyDraft != (selected?.body ?? "") else { return }
        apply { try repository.setBody(on: selectedDay, body: bodyDraft) }
    }

    /// 쓰기 한 번 = 그날 한 장을 다시 받아 달력에도 반영. 목록 전체를 다시 읽지 않는다.
    private func apply(_ write: () throws -> DiaryDay) {
        guard let updated = try? write() else { return }
        selected = updated
        monthEntries[updated.day] = updated
    }

    private func refreshSelected() {
        selected = monthEntries[selectedDay] ?? (try? repository.entry(on: selectedDay))
        bodyDraft = selected?.body ?? ""
    }
}
