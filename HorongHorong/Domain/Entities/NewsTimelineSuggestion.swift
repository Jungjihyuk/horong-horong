import Foundation

/// 리포트에서 «타임라인으로 만들 수 있는» 주제 후보 하나.
///
/// **없는 주제는 제안하지 않는다.** 사용자가 임의로 주제를 적어 넣으면 빈 타임라인이
/// 나오므로, 앱은 실제 리포트 헤딩에서 뽑아낸 것만 보여주고 사용자는 그중에서 고른다.
/// 후보 계산에는 LLM 이 쓰이지 않는다 — 리포트 마크다운 파싱과 집계가 전부다.
struct NewsTimelineSuggestion: Identifiable, Equatable, Sendable {
    /// 사용자에게 보이는 이름이자 생성 시 넘길 질의.
    let label: String
    /// 이 후보가 묶는 리포트 헤딩들. 「무엇이 들어오는지」를 보여줄 때 쓴다.
    let headings: [String]
    /// 만들면 나올 시점 수. 같은 기사가 여러 날 반복되면 처음 날에만 센다.
    let eventCount: Int
    /// 이 주제가 등장한 리포트 파일 수. 재료가 얼마나 있는지를 가장 직접적으로 보여준다.
    let reportCount: Int
    let monthCount: Int
    let dateFrom: String
    let dateTo: String
    /// 이미 만들어 둔 타임라인인가. 그렇다면 «만들기» 대신 «갱신» 이다.
    let alreadyExists: Bool
    /// 처음 만들 때 드는 LLM 호출 수(개월 수 + 개요 1회). 누르기 전에 비용을 알려준다.
    let estimatedCalls: Int
    /// 새로 추가된 리포트/사건이 있어 갱신이 필요한가.
    let hasUpdates: Bool

    init(
        label: String,
        headings: [String],
        eventCount: Int,
        reportCount: Int,
        monthCount: Int,
        dateFrom: String,
        dateTo: String,
        alreadyExists: Bool,
        estimatedCalls: Int,
        hasUpdates: Bool = true
    ) {
        self.label = label
        self.headings = headings
        self.eventCount = eventCount
        self.reportCount = reportCount
        self.monthCount = monthCount
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.alreadyExists = alreadyExists
        self.estimatedCalls = estimatedCalls
        self.hasUpdates = hasUpdates
    }

    var id: String { label }

    /// `2026-02-22 ~ 2026-09-08 · 80개 시점 · 8개월`
    var summaryLine: String {
        var parts: [String] = []
        if !dateFrom.isEmpty, !dateTo.isEmpty {
            parts.append("\(dateFrom) ~ \(dateTo)")
        }
        parts.append("리포트 \(reportCount)편")
        parts.append("\(eventCount)개 시점")
        parts.append("\(monthCount)개월")
        return parts.joined(separator: " · ")
    }
}
