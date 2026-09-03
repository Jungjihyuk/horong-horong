import Foundation

// 리포트 폴더를 훑어 보관함 목록과 본문을 만든다.
//
// **DB 가 아니라 파일이 근거다.** 파이프라인이 만든 결과물은 markdown 파일과 그 옆의
// meta json 이고, DB 의 `NewsReportIndex` 는 색인일 뿐이다.

struct NewsReportArchiveMetadata: Decodable, Equatable {
    struct TopItem: Decodable, Equatable {
        let title: String
    }

    let jobId: String?
    let reportDate: String?
    let itemCount: Int?
    let interestKeywords: [String]
    let topItems: [TopItem]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jobId = try container.decodeIfPresent(String.self, forKey: .jobId)
        reportDate = try container.decodeIfPresent(String.self, forKey: .reportDate)
        itemCount = try container.decodeIfPresent(Int.self, forKey: .itemCount)
        interestKeywords = try container.decodeIfPresent([String].self, forKey: .interestKeywords) ?? []
        topItems = try container.decodeIfPresent([TopItem].self, forKey: .topItems) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case jobId
        case reportDate
        case itemCount
        case interestKeywords
        case topItems
    }
}

enum NewsReportArchiveStore {
    static func reportDirectoryURL(dataBasePath: String) -> URL {
        URL(fileURLWithPath: dataBasePath, isDirectory: true)
            .appendingPathComponent("data", isDirectory: true)
            .appendingPathComponent("reports", isDirectory: true)
    }

    static func configuredReportURL(reportPath: String, dataBasePath: String) -> URL {
        reportDirectoryURL(dataBasePath: dataBasePath)
            .appendingPathComponent(URL(fileURLWithPath: reportPath).lastPathComponent)
    }

    static func loadEntries(
        dataBasePath: String,
        fileManager: FileManager = .default
    ) -> [NewsReportArchiveEntry] {
        let reportDirectory = reportDirectoryURL(dataBasePath: dataBasePath)
        let metaDirectory = URL(fileURLWithPath: dataBasePath, isDirectory: true)
            .appendingPathComponent("data", isDirectory: true)
            .appendingPathComponent("meta", isDirectory: true)
        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        guard let reportURLs = try? fileManager.contentsOfDirectory(
            at: reportDirectory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return reportURLs.compactMap { reportURL in
            guard reportURL.pathExtension.lowercased() == "md",
                  let resourceValues = try? reportURL.resourceValues(forKeys: resourceKeys),
                  resourceValues.isRegularFile == true else {
                return nil
            }

            let baseName = reportURL.deletingPathExtension().lastPathComponent
            let metaURL = metaDirectory.appendingPathComponent("\(baseName).meta.json")
            let metadata = loadMetadata(at: metaURL)
            let fallbackDate = resourceValues.contentModificationDate ?? .distantPast
            let reportDate = parsedDate(metadata?.reportDate ?? baseName) ?? fallbackDate
            let topTitle = metadata?.topItems.first?.title
                ?? markdownTitle(at: reportURL)
                ?? reportURL.lastPathComponent

            return NewsReportArchiveEntry(
                id: reportURL.standardizedFileURL.path,
                jobId: metadata?.jobId ?? reportURL.standardizedFileURL.path,
                reportDate: reportDate,
                reportURL: reportURL,
                metaURL: metaURL,
                topTitle: topTitle,
                itemCount: metadata?.itemCount ?? metadata?.topItems.count ?? 0,
                createdAt: resourceValues.contentModificationDate ?? reportDate
            )
        }
        .sorted {
            if $0.reportDate != $1.reportDate { return $0.reportDate > $1.reportDate }
            return $0.createdAt > $1.createdAt
        }
    }

    static func loadMetadata(at url: URL) -> NewsReportArchiveMetadata? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(NewsReportArchiveMetadata.self, from: data)
    }

    private static func parsedDate(_ value: String) -> Date? {
        let dateText = String(value.prefix(10))
        let parts = dateText.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(
            from: DateComponents(year: parts[0], month: parts[1], day: parts[2])
        )
    }

    private static func markdownTitle(at url: URL) -> String? {
        guard let markdown = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return markdown.components(separatedBy: .newlines)
            .first { $0.hasPrefix("# ") }
            .map { String($0.dropFirst(2)) }
    }
}

struct NewsReportArchiveDocument: Equatable {
    let markdown: String
    let interestKeywords: [String]
    let fileSize: Int64?
    let errorMessage: String?

    static func load(reportPath: String, metaPath: String) -> NewsReportArchiveDocument {
        let reportURL = URL(fileURLWithPath: reportPath)
        let markdown: String
        let errorMessage: String?
        do {
            markdown = try String(contentsOf: reportURL, encoding: .utf8)
            errorMessage = nil
        } catch {
            markdown = ""
            errorMessage = "Markdown 파일을 읽을 수 없습니다."
        }

        let keywords: [String]
        if let metadata = NewsReportArchiveStore.loadMetadata(at: URL(fileURLWithPath: metaPath)) {
            keywords = metadata.interestKeywords
        } else {
            keywords = []
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: reportPath)
        let fileSize = (attributes?[.size] as? NSNumber)?.int64Value
        return NewsReportArchiveDocument(
            markdown: markdown,
            interestKeywords: keywords,
            fileSize: fileSize,
            errorMessage: errorMessage
        )
    }

    func matches(query: String, title: String, filename: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }
        return title.localizedCaseInsensitiveContains(normalized)
            || filename.localizedCaseInsensitiveContains(normalized)
            || interestKeywords.contains { $0.localizedCaseInsensitiveContains(normalized) }
            || markdown.localizedCaseInsensitiveContains(normalized)
    }

}
