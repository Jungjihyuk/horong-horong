import Foundation
import Observation

enum DiaryInsightsRange: Int, CaseIterable, Identifiable {
    case week = 7
    case month = 30
    case quarter = 90
    /// 감정 패턴은 계절을 타기도 해서 반년까지 볼 수 있어야 한다.
    case half = 180

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .week: return "1주"
        case .month: return "1달"
        case .quarter: return "3달"
        case .half: return "6개월"
        }
    }
}

@MainActor
@Observable
final class DiaryInsightsViewModel {
    private(set) var snapshot: DiaryInsightsSnapshot = .empty
    private(set) var referenceDate: Date
    /// 설정에서 정한 수면 축. 취침·기상 막대의 좌표가 여기 기댄다.
    var sleepAxis: DiarySleepAxis = .default {
        didSet {
            guard sleepAxis != oldValue else { return }
            reload()
        }
    }

    var range: DiaryInsightsRange = .month {
        didSet {
            guard range != oldValue else { return }
            reload()
        }
    }

    private let repository: DiaryRepository
    private let calendar: Calendar

    init(
        repository: DiaryRepository,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.repository = repository
        self.calendar = calendar
        self.referenceDate = calendar.startOfDay(for: referenceDate)
    }

    func reload() {
        let end = calendar.date(byAdding: .day, value: 1, to: referenceDate) ?? referenceDate
        let start = calendar.date(byAdding: .day, value: -(range.rawValue - 1), to: referenceDate) ?? referenceDate
        let entries = (try? repository.entries(from: start, to: end)) ?? []
        snapshot = DiaryInsightsBuilder.build(
            entries: entries, start: start, end: end, axis: sleepAxis, calendar: calendar
        )
    }
}
