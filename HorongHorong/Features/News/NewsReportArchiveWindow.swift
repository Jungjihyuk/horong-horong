import AppKit
import Foundation
import SwiftData
import SwiftUI

@MainActor
final class NewsReportArchiveSelection: ObservableObject {
    struct Request: Equatable {
        let reportID: String?
        let token: UUID
    }

    static let shared = NewsReportArchiveSelection()

    @Published private(set) var request = Request(reportID: nil, token: UUID())

    private init() {}

    func select(reportID: String?) {
        request = Request(reportID: reportID, token: UUID())
    }
}

enum NewsReportMarkdownBlock: Equatable {
    case title(String)
    case heading(level: Int, text: String)
    case metadata(String)
    case quote(String)
    case callout(String)
    case insight(String)
    case note(String)
    case bullet(String)
    case numbered(number: String, text: String)
    case paragraph(String)
    case code(String)
    case divider
}

enum NewsReportMarkdownParser {
    static func parse(_ markdown: String) -> [NewsReportMarkdownBlock] {
        var blocks: [NewsReportMarkdownBlock] = []
        var codeLines: [String] = []
        var isInsideCodeBlock = false

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                if isInsideCodeBlock {
                    blocks.append(.code(codeLines.joined(separator: "\n")))
                    codeLines.removeAll(keepingCapacity: true)
                }
                isInsideCodeBlock.toggle()
                continue
            }

            if isInsideCodeBlock {
                codeLines.append(rawLine)
                continue
            }

            guard !line.isEmpty else { continue }

            if line == "---" || line == "***" || line == "___" {
                blocks.append(.divider)
            } else if line.hasPrefix("# ") {
                blocks.append(.title(String(line.dropFirst(2))))
            } else if line.hasPrefix("### ") {
                blocks.append(.heading(level: 3, text: String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                blocks.append(.heading(level: 2, text: String(line.dropFirst(3))))
            } else if line.hasPrefix("> ") {
                blocks.append(.quote(String(line.dropFirst(2))))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                blocks.append(.bullet(String(line.dropFirst(2))))
            } else if let numbered = numberedItem(in: line) {
                blocks.append(.numbered(number: numbered.number, text: numbered.text))
            } else if line.hasPrefix("생성일:") || line.hasPrefix("관심사:") {
                blocks.append(.metadata(line))
            } else if line.hasPrefix("🔑") || line.hasPrefix("📈") {
                blocks.append(.insight(line))
            } else if line.hasPrefix("**"), line.hasSuffix("**"), line.count > 4 {
                blocks.append(.callout(line))
            } else if line.hasPrefix("_"), line.hasSuffix("_"), line.count > 2 {
                blocks.append(.note(line))
            } else {
                blocks.append(.paragraph(line))
            }
        }

        if !codeLines.isEmpty {
            blocks.append(.code(codeLines.joined(separator: "\n")))
        }
        return blocks
    }

    private static func numberedItem(in line: String) -> (number: String, text: String)? {
        guard let separator = line.firstIndex(of: ".") else { return nil }
        let number = String(line[..<separator])
        guard !number.isEmpty,
              number.allSatisfy(\.isNumber) else { return nil }
        let textStart = line.index(after: separator)
        let text = line[textStart...].trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (number, text)
    }
}

struct NewsReportArchiveEntry: Identifiable, Equatable {
    let id: String
    let jobId: String
    let reportDate: Date
    let reportURL: URL
    let metaURL: URL
    let topTitle: String
    let itemCount: Int
    let createdAt: Date
}

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

struct NewsReportArchiveWindow: View {
    @Query(sort: \NewsReportIndex.createdAt, order: .reverse)
    private var indexedReports: [NewsReportIndex]
    @ObservedObject private var selection = NewsReportArchiveSelection.shared
    @AppStorage(Constants.NewsStorageKey.dataBasePath)
    private var dataBasePath = Constants.defaultNewsDataBasePath
    @AppStorage(Constants.AppStorageKey.popoverTheme)
    private var popoverTheme = Constants.defaultPopoverTheme

    @State private var entries: [NewsReportArchiveEntry] = []
    @State private var selectedEntryID: String?
    @State private var searchText = ""
    @State private var documents: [String: NewsReportArchiveDocument] = [:]

    var body: some View {
        let visibleEntries = matchingEntries()
        let selectedEntry = selectedEntry(from: visibleEntries)

        VStack(spacing: 0) {
            toolbar
            Divider().overlay(PopoverChrome.divider)

            HStack(spacing: 0) {
                reportList(visibleEntries)
                Divider().overlay(PopoverChrome.divider)
                detailPane(selectedEntry)
            }
        }
        .frame(minWidth: 840, minHeight: 540)
        .appearanceAccentTint(.popover)
        .background(PopoverChrome.surface)
        .id(popoverTheme)
        .onAppear {
            reloadArchive()
            applySelectionRequest(selection.request, filteredEntries: matchingEntries())
        }
        .onChange(of: selection.request) { _, request in
            applySelectionRequest(request, filteredEntries: matchingEntries())
        }
        .onChange(of: indexedReports.map(\.jobId)) { _, _ in
            reloadArchive()
        }
        .onChange(of: dataBasePath) { _, _ in
            reloadArchive()
        }
        .onChange(of: searchText) { _, _ in
            let matches = matchingEntries()
            if let selectedEntryID,
               matches.contains(where: { $0.id == selectedEntryID }) {
                return
            }
            selectedEntryID = matches.first?.id
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            reloadArchive()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PopoverChrome.accent)
                Text(abbreviatedPath(reportDirectoryURL.path))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(PopoverChrome.inkTertiary)
                TextField("리포트 검색...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 11)
            .frame(width: 210, height: 34)
            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous)
                    .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
            )

            Button {
                revealInFinder()
            } label: {
                Label("Finder에서 보기", systemImage: "folder")
            }
            .buttonStyle(NewsReportArchiveButtonStyle())
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
        .background(PopoverChrome.surfaceAlt.opacity(0.52))
    }

    private func reportList(_ filteredEntries: [NewsReportArchiveEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(searchText.isEmpty ? "\(entries.count)개 리포트" : "검색 결과 \(filteredEntries.count)개")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            if filteredEntries.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: entries.isEmpty ? "doc.text.magnifyingglass" : "magnifyingglass")
                        .font(.system(size: 26))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                    Text(entries.isEmpty ? "저장된 리포트가 없습니다" : "일치하는 리포트가 없습니다")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(18)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredEntries) { entry in
                            reportCard(entry)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 14)
                }
            }
        }
        .frame(width: 250)
        .frame(maxHeight: .infinity)
        .background(PopoverChrome.surfaceAlt.opacity(0.34))
    }

    private func reportCard(_ entry: NewsReportArchiveEntry) -> some View {
        let document = documents[entry.id]
        let isSelected = selectedEntryID == entry.id

        return Button {
            selectedEntryID = entry.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.reportURL.lastPathComponent)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                    .lineLimit(1)

                Text("\(entry.itemCount)개 항목 · \(formattedFileSize(document?.fileSize))")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)

                if let keywords = document?.interestKeywords, !keywords.isEmpty {
                    NewsKeywordFlowLayout(spacing: 5) {
                        ForEach(Array(keywords.prefix(5)), id: \.self) { keyword in
                            keywordChip(keyword)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(11)
            .background(
                isSelected ? PopoverChrome.accentSoft.opacity(0.42) : PopoverChrome.card,
                in: RoundedRectangle(cornerRadius: PopoverChrome.radius(11), style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PopoverChrome.radius(11), style: .continuous)
                    .stroke(
                        isSelected ? PopoverChrome.accent : PopoverChrome.border,
                        lineWidth: isSelected ? 1.5 : PopoverChrome.borderWidth
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func detailPane(_ entry: NewsReportArchiveEntry?) -> some View {
        Group {
            if let entry {
                VStack(spacing: 0) {
                    detailHeader(entry)
                    Divider().overlay(PopoverChrome.divider)
                    reportBody(entry)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "newspaper")
                        .font(.system(size: 34))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                    Text(entries.isEmpty ? "리포트를 생성하면 이곳에서 볼 수 있습니다" : "왼쪽에서 리포트를 선택해주세요")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PopoverChrome.surface)
    }

    private func detailHeader(_ entry: NewsReportArchiveEntry) -> some View {
        let document = documents[entry.id]

        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(entry.reportURL.lastPathComponent)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(formattedDate(entry.reportDate))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                    if let keywords = document?.interestKeywords, !keywords.isEmpty {
                        Text("관심 키워드")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(PopoverChrome.inkSecondary)
                        ForEach(Array(keywords.prefix(4)), id: \.self) { keyword in
                            keywordChip(keyword)
                        }
                    }
                }
            }

            Spacer(minLength: 12)

            Button {
                NSWorkspace.shared.open(entry.reportURL)
            } label: {
                Label("Markdown 열기", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(NewsReportArchiveButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(PopoverChrome.surfaceAlt.opacity(0.28))
    }

    @ViewBuilder
    private func reportBody(_ entry: NewsReportArchiveEntry) -> some View {
        if let document = documents[entry.id] {
            if let errorMessage = document.errorMessage {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(PopoverChrome.accent)
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                    Text(entry.reportURL.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(NewsReportMarkdownParser.parse(document.markdown).enumerated()), id: \.offset) { _, block in
                            markdownBlock(block)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 22)
                }
                .tint(PopoverChrome.accent)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func markdownBlock(_ block: NewsReportMarkdownBlock) -> some View {
        switch block {
        case .title(let text):
            Text(inlineMarkdown(text))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [PopoverChrome.accent, PopoverChrome.accent.opacity(0.76)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: PopoverChrome.radius(14), style: .continuous)
                )
                .padding(.bottom, 2)

        case .heading(let level, let text):
            Text(inlineMarkdown(text))
                .font(.system(size: level == 2 ? 18 : 15, weight: .bold, design: .rounded))
                .foregroundStyle(level == 2 ? PopoverChrome.accent : PopoverChrome.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, level == 2 ? 10 : 5)
                .padding(.bottom, level == 2 ? 2 : 0)

        case .metadata(let text):
            Text(inlineMarkdown(text))
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)

        case .quote(let text):
            HStack(spacing: 8) {
                Capsule()
                    .fill(PopoverChrome.accent)
                    .frame(width: 3)
                Text(inlineMarkdown(text))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(PopoverChrome.accentSoft.opacity(0.34), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))

        case .callout(let text):
            Text(inlineMarkdown(text))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13)
                .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous)
                        .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
                )

        case .insight(let text):
            Text(inlineMarkdown(text))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(PopoverChrome.surfaceAlt.opacity(0.75), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))

        case .note(let text):
            Text(inlineMarkdown(text))
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)

        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Circle()
                    .fill(PopoverChrome.accent)
                    .frame(width: 5, height: 5)
                Text(inlineMarkdown(text))
                    .font(.system(size: 12.5, weight: .regular, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 4)

        case .numbered(let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(number)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .frame(width: 20, height: 20)
                    .background(PopoverChrome.accent, in: Circle())
                Text(inlineMarkdown(text))
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .paragraph(let text):
            Text(inlineMarkdown(text))
                .font(.system(size: 12.5, weight: .regular, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

        case .code(let text):
            ScrollView(.horizontal) {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .background(PopoverChrome.surfaceAlt, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))

        case .divider:
            Divider().overlay(PopoverChrome.divider)
        }
    }

    private func matchingEntries() -> [NewsReportArchiveEntry] {
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

    private func selectedEntry(from filteredEntries: [NewsReportArchiveEntry]) -> NewsReportArchiveEntry? {
        if let selectedEntryID,
           let selected = entries.first(where: { $0.id == selectedEntryID }) {
            return selected
        }
        return filteredEntries.first
    }

    private func reloadArchive() {
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
        ensureValidSelection(in: matchingEntries())
    }

    private func applySelectionRequest(
        _ request: NewsReportArchiveSelection.Request,
        filteredEntries: [NewsReportArchiveEntry]
    ) {
        if let requestedID = request.reportID,
           let requestedEntry = entries.first(where: { $0.jobId == requestedID }) {
            selectedEntryID = requestedEntry.id
        } else {
            selectedEntryID = filteredEntries.first?.id ?? entries.first?.id
        }
    }

    private func ensureValidSelection(in filteredEntries: [NewsReportArchiveEntry]) {
        guard let selectedEntryID,
              entries.contains(where: { $0.id == selectedEntryID }) else {
            self.selectedEntryID = filteredEntries.first?.id ?? entries.first?.id
            return
        }
    }

    private var reportDirectoryURL: URL {
        NewsReportArchiveStore.reportDirectoryURL(dataBasePath: dataBasePath)
    }

    private func revealInFinder() {
        NSWorkspace.shared.open(reportDirectoryURL)
    }

    private func abbreviatedPath(_ path: String) -> String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        guard path == homePath || path.hasPrefix(homePath + "/") else { return path }
        return "~" + path.dropFirst(homePath.count)
    }

    private func formattedDate(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private func formattedFileSize(_ bytes: Int64?) -> String {
        guard let bytes else { return "크기 알 수 없음" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func keywordChip(_ keyword: String) -> some View {
        Text(keyword)
            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .foregroundStyle(PopoverChrome.accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(PopoverChrome.accentSoft.opacity(0.44), in: Capsule())
            .fixedSize()
    }

    private func inlineMarkdown(_ source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
    }
}

private struct NewsReportArchiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(PopoverChrome.inkSecondary)
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(
                configuration.isPressed ? PopoverChrome.accentSoft.opacity(0.48) : PopoverChrome.card,
                in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous)
                    .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
            )
    }
}

private struct NewsKeywordFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var points: [CGPoint] = []
        var cursor = CGPoint.zero
        var lineHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursor.x > 0, cursor.x + size.width > maxWidth {
                cursor.x = 0
                cursor.y += lineHeight + spacing
                lineHeight = 0
            }
            points.append(cursor)
            cursor.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            usedWidth = max(usedWidth, cursor.x - spacing)
        }

        return (
            CGSize(width: usedWidth, height: cursor.y + lineHeight),
            points
        )
    }
}
