import Foundation
import Observation

/// 뉴스 타임라인 화면의 상태.
///
/// 보관함(`NewsArchiveViewModel`)과 같은 규칙을 따른다 — 목록의 근거는 DB 가 아니라
/// 디스크이고, 파이프라인 완료 알림을 「다시 읽어라」 신호로 쓴다.
///
/// **타임라인을 스스로 만들지 않는다.** 리포트가 늘었다고 자동으로 생성·갱신하지 않고,
/// 사용자가 주제를 고르고 버튼을 눌렀을 때만 `NewsTimelineGateway` 를 호출한다.
@MainActor
@Observable
final class NewsTimelineViewModel {
    private(set) var timelines: [NewsTimeline] = []
    private(set) var selectedCategoryID: String?

    /// 리포트에서 만들 수 있는 주제 후보. 「만들기」를 열 때 채운다.
    private(set) var suggestions: [NewsTimelineSuggestion] = []
    private(set) var isLoadingSuggestions = false
    /// 지금 만들고 있는 주제. 비어 있으면 대기 상태다.
    private(set) var buildingLabel: String?
    private(set) var errorMessage: String?

    var selectedTimeline: NewsTimeline? {
        if let selectedCategoryID,
           let selected = timelines.first(where: { $0.categoryId == selectedCategoryID }) {
            return selected
        }
        return timelines.first
    }

    /// 타임라인이 아직 하나도 없는 상태. 화면이 「어떻게 만드는지」를 안내해야 한다.
    var isEmpty: Bool { timelines.isEmpty }

    // MARK: - 읽기

    func reload(dataBasePath: String) {
        timelines = NewsTimelineStore.loadTimelines(dataBasePath: dataBasePath)
        keepSelectionVisible()
    }

    func select(_ categoryID: String?) {
        selectedCategoryID = categoryID
    }

    // MARK: - 만들기 (사용자가 버튼을 눌렀을 때만)

    /// 만들 수 있는 주제를 찾아온다. LLM 을 쓰지 않아 즉시 끝난다.
    func loadSuggestions(gateway: NewsTimelineGateway, dataBasePath: String) async {
        isLoadingSuggestions = true
        errorMessage = nil
        defer { isLoadingSuggestions = false }

        do {
            suggestions = try await gateway.suggestTopics(dataBasePath: dataBasePath)
        } catch {
            suggestions = []
            errorMessage = error.localizedDescription
        }
    }

    /// 고른 주제로 타임라인을 만든다. **여기서만 LLM 비용이 발생한다.**
    func build(
        label: String,
        axisLimit: Int,
        gateway: NewsTimelineGateway,
        dataBasePath: String
    ) async {
        buildingLabel = label
        errorMessage = nil
        defer { buildingLabel = nil }

        do {
            try await gateway.buildTimeline(
                label: label,
                axisLimit: axisLimit,
                dataBasePath: dataBasePath
            )
            reload(dataBasePath: dataBasePath)
            // 방금 만든 것을 바로 보여준다.
            if let created = timelines.first(where: { $0.categoryLabel == label }) {
                selectedCategoryID = created.categoryId
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    private func keepSelectionVisible() {
        guard let selectedCategoryID else { return }
        if !timelines.contains(where: { $0.categoryId == selectedCategoryID }) {
            self.selectedCategoryID = timelines.first?.categoryId
        }
    }
}
