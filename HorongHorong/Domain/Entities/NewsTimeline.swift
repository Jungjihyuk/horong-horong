import Foundation

/// 한 분야의 월간 타임라인.
///
/// **근거는 DB 가 아니라 파일이다.** 파이썬 파이프라인이 `data/timeline/<분야>.json` 에
/// 남긴 것을 그대로 읽는다. 리포트 보관함(`NewsReportArchiveEntry`)이 파일을 근거로
/// 삼는 것과 같은 이유다 — 앱이 만든 것이 아니라 앱 밖에서 자라는 데이터다.
struct NewsTimeline: Identifiable, Equatable, Sendable {
    let categoryId: String
    let categoryLabel: String
    /// 한 달에 표시할 대표 사건의 사용자 지정 최대치(1...5).
    let axisLimit: Int
    /// `2026-02-22` 형태. 문자열 그대로 두는 이유는 아래 `NewsTimelineEvent.date` 와 같다.
    let dateFrom: String
    let dateTo: String
    let months: [NewsTimelineMonth]
    let overview: NewsTimelineOverview
    /// 종합에 실패한 달이 있으면 그 사유. 비어 있는 것이 정상이다.
    let warnings: [String]

    var id: String { categoryId }

    /// 축과 세부를 합친 사건 수. 머리말의 «N개 시점» 이다.
    var totalEventCount: Int {
        months.reduce(0) { $0 + $1.axisEvents.count + $1.detailEvents.count }
    }

    var turningPointMonthKeys: [String] {
        months.filter(\.hasTurningPoint).map(\.monthKey)
    }

    var turningPointCount: Int {
        months.reduce(0) { count, month in
            count + month.axisEvents.filter(\.isTurningPoint).count
        }
    }
}

/// 월 버킷 하나.
struct NewsTimelineMonth: Identifiable, Equatable, Sendable {
    /// `2026-04`.
    let monthKey: String
    /// 이 달을 종합한 시각(ISO8601 문자열). 비어 있으면 아직 종합 전이다.
    let synthesizedAt: String
    /// LLM 이 만든 그 달의 종합 정리.
    let summary: String
    let keyTerms: [String]
    /// 그 달을 대표하는 사건. 최대 3개.
    let axisEvents: [NewsTimelineEvent]
    /// 우선순위순 세부 사건.
    let detailEvents: [NewsTimelineEvent]

    var id: String { monthKey }

    var isSynthesized: Bool { !synthesizedAt.isEmpty }

    var hasTurningPoint: Bool { axisEvents.contains(where: \.isTurningPoint) }

    /// 이 달이 마감됐는지. **저장하지 않고 매번 계산한다** — 이번 달은 다음 달이 되면
    /// 지난 달이라, 쓰기 없이 자정만 지나도 틀리는 값이기 때문이다(CLAUDE.md R2).
    /// 파이썬 쪽 `timeline/state.py::is_sealed` 와 같은 판단이다.
    func isSealed(now: Date, calendar: Calendar = .current) -> Bool {
        monthKey < Self.monthKey(of: now, calendar: calendar)
    }

    static func monthKey(of date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        guard let year = parts.year, let month = parts.month else { return "" }
        return String(format: "%04d-%02d", year, month)
    }

    /// `2026-04` → `2026년 4월`. 표시용이라 저장하지 않는다.
    var displayLabel: String {
        let parts = monthKey.split(separator: "-")
        guard parts.count == 2, let month = Int(parts[1]) else { return monthKey }
        return "\(parts[0])년 \(month)월"
    }
}

/// 타임라인의 한 시점에서 일어난 사건.
struct NewsTimelineEvent: Identifiable, Equatable, Sendable {
    let eventId: String
    /// `2026-04-10`. **`Date` 로 바꾸지 않는다** — 원본이 날짜 문자열이고, 시간대에 따라
    /// 하루가 밀리면 월 버킷이 어긋난다. 표시할 때만 `MM-dd` 로 자른다.
    let date: String
    let title: String
    let url: String
    /// 월 맥락에서 공통 루브릭으로 다시 평가한 중요도 0~100.
    let importance: Int
    let importanceAssessment: NewsTimelineImportanceAssessment?
    let bullets: [String]
    let tags: [String]
    /// 축 사건만 채워진다. 「왜 이것이 이 달의 축인가」.
    let whyItMatters: String
    /// 비어 있지 않으면 이 대표 사건이 해당 월의 전환점이다.
    let turningPointReason: String

    var id: String { eventId }

    /// `2026-04-10` → `04-10`. 월 컬럼 안에서는 연도가 반복이라 지운다.
    var shortDate: String {
        date.count >= 10 ? String(date.dropFirst(5)) : date
    }

    var linkURL: URL? { url.isEmpty ? nil : URL(string: url) }

    var isTurningPoint: Bool { !turningPointReason.isEmpty }
}

/// 모든 뉴스 분야가 공유하는 중요도 100점 루브릭.
struct NewsTimelineImportanceAssessment: Equatable, Sendable {
    let changeMagnitude: Int
    let impactScope: Int
    let durability: Int
    let trajectoryPower: Int
    let evidenceStrength: Int
    let reason: String

    var total: Int {
        changeMagnitude + impactScope + durability + trajectoryPower + evidenceStrength
    }
}

/// 타임라인 전체 머리말.
struct NewsTimelineOverview: Equatable, Sendable {
    let summary: String
    let emphasisKeywords: [String]

    static let empty = NewsTimelineOverview(
        summary: "",
        emphasisKeywords: []
    )
}
