import Foundation
import Observation

/// 리포트 보관함 창의 상태.
///
/// **목록의 근거는 DB 가 아니라 디스크다.** 예전에는 `@Query` 로 색인을 관찰하면서 목록은
/// 파일에서 읽었다 — 색인은 «다시 읽어라» 는 신호로만 쓰였다. 그 신호를 파이프라인
/// 완료 알림으로 바꾸고 `@Query` 를 걷어냈다.
@MainActor
@Observable
final class NewsArchiveViewModel {
    private(set) var entries: [NewsReportArchiveEntry] = []
    private(set) var selectedEntryID: String?

    var searchText = "" { didSet { guard searchText != oldValue else { return }; keepSelectionVisible() } }

    private var documents: [String: NewsReportArchiveDocument] = [:]

    /// 검색어에 맞는 것만. 본문까지 뒤지므로 제목만으로는 안 걸리는 것도 찾힌다.
    var visibleEntries: [NewsReportArchiveEntry] {
        entries.filter { entry in
            let filename = entry.reportURL.lastPathComponent
            guard let document = documents[entry.id] else {
                return searchText.isEmpty
                    || entry.topTitle.localizedCaseInsensitiveContains(searchText)
                    || filename.localizedCaseInsensitiveContains(searchText)
            }
            return document.matches(query: searchText, title: entry.topTitle, filename: filename)
        }
    }

    var selectedEntry: NewsReportArchiveEntry? {
        if let selectedEntryID, let selected = entries.first(where: { $0.id == selectedEntryID }) {
            return selected
        }
        return visibleEntries.first
    }

    func document(for entry: NewsReportArchiveEntry) -> NewsReportArchiveDocument? {
        documents[entry.id]
    }

    /// 폴더를 다시 훑는다.
    ///
    /// **본문을 전부 읽어 들인다.** 검색이 본문까지 훑기 때문인데, 리포트가 쌓이면 그만큼
    /// 비싸진다. 지금은 하루 한 편 수준이라 두었다 — 느려지면 검색 시점에 읽도록 바꾼다.
    /// `[확인 필요]`
    func reload(dataBasePath: String) {
        entries = NewsReportArchiveStore.loadEntries(dataBasePath: dataBasePath)
        documents = Dictionary(uniqueKeysWithValues: entries.map { entry in
            (
                entry.id,
                NewsReportArchiveDocument.load(
                    reportPath: entry.reportURL.path,
                    metaPath: entry.metaURL.path
                )
            )
        })
        keepSelectionVisible()
    }

    func select(_ id: String?) {
        selectedEntryID = id
    }

    /// 다른 창(팝오버)이 「이 리포트를 열어라」고 요청했을 때.
    func applySelectionRequest(reportID: String?) {
        if let reportID, let requested = entries.first(where: { $0.jobId == reportID }) {
            selectedEntryID = requested.id
        } else {
            selectedEntryID = visibleEntries.first?.id ?? entries.first?.id
        }
    }

    /// 고른 것이 목록에서 사라졌으면(검색으로 걸러짐·파일 삭제) 첫 항목으로 옮긴다.
    private func keepSelectionVisible() {
        let matches = visibleEntries
        if let selectedEntryID, matches.contains(where: { $0.id == selectedEntryID }) { return }
        selectedEntryID = matches.first?.id ?? entries.first?.id
    }
}
