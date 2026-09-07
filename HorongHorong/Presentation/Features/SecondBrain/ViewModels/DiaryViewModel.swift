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
    private(set) var insightPreview: DiaryInsightsSnapshot = .empty
    private(set) var isPullingSleep = false
    /// 설정에서 정한 수면 축. 화면이 넣어 준다 — ViewModel 이 `UserDefaults` 를 직접 읽으면
    /// 설정을 바꿔도 이미 만들어진 인스턴스가 옛 값을 물고 있는다.
    var sleepAxis: DiarySleepAxis = .default {
        didSet {
            guard sleepAxis != oldValue else { return }
            updateInsightPreview()
        }
    }

    /// 편집 중인 본문. **타건은 여기서 끝난다** — 저장은 400ms 뒤 한 번.
    var bodyDraft = ""

    private let repository: DiaryRepository
    private let sleep: SleepGateway?
    private let calendar: Calendar
    private var previewEntries: [Date: DiaryDay] = [:]
    private var saveTask: Task<Void, Never>?
    private var sleepTask: Task<Void, Never>?

    init(repository: DiaryRepository, sleep: SleepGateway? = nil, calendar: Calendar = .current) {
        self.repository = repository
        self.sleep = sleep
        self.calendar = calendar
        let today = calendar.startOfDay(for: Date())
        visibleMonth = today
        selectedDay = today
    }

    var isSleepAvailable: Bool { sleep?.isAvailable ?? false }

    /// 패널 인사이트 카드가 보는 기간. 수면 리듬은 한 주로는 규칙이 보이지 않아 두 주를 본다.
    static let previewDayCount = 14

    /// 이 달에 기록한 날 수.
    var writtenCount: Int { monthEntries.count }

    func entry(on day: Date) -> DiaryDay? { monthEntries[day] }

    // MARK: - 읽기

    func reload() {
        let entries = (try? repository.entries(inMonthOf: visibleMonth)) ?? []
        // 같은 날짜가 둘이어도 죽지 않게 관대하게 짓는다. 중복을 막는 일은 저장소가 한다.
        monthEntries = Dictionary(entries.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        refreshSelected()
        reloadInsightPreview()
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
            reloadInsightPreview()
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

    /// 같은 것을 다시 누르면 해제한다. 해제하면 그 칸의 원인·강도도 저장소가 함께 지운다.
    func setMood(_ mood: DiaryMood, in slot: DiaryMoodSlot) {
        let next = selected?.record(slot)?.mood == mood ? nil : mood
        apply { try repository.setMood(on: selectedDay, slot: slot, mood: next) }
    }

    func setCause(_ cause: DiaryCause, in slot: DiaryMoodSlot) {
        let next = selected?.record(slot)?.cause == cause ? nil : cause
        apply { try repository.setCause(on: selectedDay, slot: slot, cause: next) }
    }

    func setIntensity(_ intensity: Int, in slot: DiaryMoodSlot) {
        let next = selected?.record(slot)?.intensity == intensity ? nil : intensity
        apply { try repository.setIntensity(on: selectedDay, slot: slot, intensity: next) }
    }

    func setStress(_ value: Int) {
        apply { try repository.setStress(on: selectedDay, stress: selected?.stress == value ? nil : value) }
    }

    /// 타임라인에서 끌어 놓은 취침·기상 시각을 그대로 저장한다.
    func setSleepWindow(start: Date, end: Date) {
        let window = DiarySleepWindowPolicy.normalize(start: start, end: end)
        apply { try repository.setSleep(on: selectedDay, window: window, source: .manual) }
    }

    /// 잘못 찍은 수면을 지운다.
    func clearSleep() {
        apply { try repository.setSleep(on: selectedDay, window: nil, source: .manual) }
    }

    /// 길이만 아는 경로(옛 기록 이관, 건강 앱 연동)를 위한 입구. 기상 시각을 기준으로 역산한다.
    func setSleepHours(_ hours: Double) {
        let window = DiarySleepWindowPolicy.window(hours: hours, day: selectedDay, calendar: calendar)
        apply { try repository.setSleep(on: selectedDay, window: window, source: .manual) }
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

    /// 예전 건강 앱 연동을 주입받은 호환 호출. 현재 화면에는 이 경로가 없다.
    func pullSleep(force: Bool) {
        guard let sleep else { return }
        sleepTask?.cancel()
        isPullingSleep = true
        let day = selectedDay
        sleepTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let hours = await sleep.sleepHours(on: day, calendar: self.calendar)
            self.isPullingSleep = false
            guard !Task.isCancelled, let hours, self.selectedDay == day else { return }
            // 가져오는 사이에 사용자가 직접 입력했을 수 있다. 다시 확인한다.
            if !force, self.selected?.sleepSource == .manual { return }
            let window = DiarySleepWindowPolicy.window(hours: hours, day: day, calendar: self.calendar)
            self.apply { try self.repository.setSleep(on: day, window: window, source: .healthKit) }
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
        previewEntries[updated.day] = updated
        updateInsightPreview()
    }

    private func refreshSelected() {
        selected = monthEntries[selectedDay] ?? (try? repository.entry(on: selectedDay))
        bodyDraft = selected?.body ?? ""
    }

    private func reloadInsightPreview() {
        let start = calendar.date(byAdding: .day, value: -(Self.previewDayCount - 1), to: selectedDay) ?? selectedDay
        let end = calendar.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay
        let entries = (try? repository.entries(from: start, to: end)) ?? []
        previewEntries = Dictionary(entries.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        updateInsightPreview()
    }

    private func updateInsightPreview() {
        let start = calendar.date(byAdding: .day, value: -(Self.previewDayCount - 1), to: selectedDay) ?? selectedDay
        let end = calendar.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay
        insightPreview = DiaryInsightsBuilder.build(
            entries: Array(previewEntries.values),
            start: start,
            end: end,
            axis: sleepAxis,
            calendar: calendar
        )
    }
}
