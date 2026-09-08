import Foundation
import Observation

/// 뉴스 타임라인 화면의 상태.
///
/// 보관함(`NewsArchiveViewModel`)과 같은 규칙을 따른다 — 목록의 근거는 DB 가 아니라
/// 디스크이고, 파이프라인 완료 알림을 「다시 읽어라」 신호로 쓴다.
@MainActor
@Observable
final class NewsTimelineViewModel {
    private(set) var timelines: [NewsTimeline] = []
    private(set) var selectedCategoryID: String?

    var selectedTimeline: NewsTimeline? {
        if let selectedCategoryID,
           let selected = timelines.first(where: { $0.categoryId == selectedCategoryID }) {
            return selected
        }
        return timelines.first
    }

    /// 타임라인이 아직 하나도 없는 상태. 화면이 「어떻게 만드는지」를 안내해야 한다.
    var isEmpty: Bool { timelines.isEmpty }

    func reload(dataBasePath: String) {
        timelines = NewsTimelineStore.loadTimelines(dataBasePath: dataBasePath)
        keepSelectionVisible()
    }

    func select(_ categoryID: String?) {
        selectedCategoryID = categoryID
    }

    private func keepSelectionVisible() {
        guard let selectedCategoryID else { return }
        if !timelines.contains(where: { $0.categoryId == selectedCategoryID }) {
            self.selectedCategoryID = timelines.first?.categoryId
        }
    }
}
