import AppKit
import Foundation
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

struct NewsReportArchiveWindow: View {
    @Environment(\.appearanceDensity) private var appearanceDensity
    @ObservedObject private var selection = NewsReportArchiveSelection.shared
    @AppStorage(Constants.NewsStorageKey.dataBasePath)
    private var dataBasePath = Constants.defaultNewsDataBasePath
    @AppStorage(Constants.AppStorageKey.popoverTheme)
    private var popoverTheme = Constants.defaultPopoverTheme

    @State private var viewModel = NewsArchiveViewModel()

    var body: some View {
        let visibleEntries = viewModel.visibleEntries
        let selectedEntry = viewModel.selectedEntry

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
            viewModel.reload(dataBasePath: dataBasePath)
            viewModel.applySelectionRequest(reportID: selection.request.reportID)
        }
        .onChange(of: selection.request) { _, request in
            viewModel.applySelectionRequest(reportID: request.reportID)
        }
        .onChange(of: dataBasePath) { _, _ in
            viewModel.reload(dataBasePath: dataBasePath)
        }
        // `@Query` 로 색인을 관찰하던 자리. 리포트는 파이프라인이 끝날 때만 늘어난다.
        .onReceive(NotificationCenter.default.publisher(for: .newsPipelineJobFinished)) { _ in
            viewModel.reload(dataBasePath: dataBasePath)
        }
        // 앱 밖에서 파일을 지우거나 옮겼을 수 있다.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.reload(dataBasePath: dataBasePath)
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
                TextField("리포트 검색...", text: $viewModel.searchText)
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
            Text(viewModel.searchText.isEmpty ? "\(viewModel.entries.count)개 리포트" : "검색 결과 \(filteredEntries.count)개")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            if filteredEntries.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: viewModel.entries.isEmpty ? "doc.text.magnifyingglass" : "magnifyingglass")
                        .font(.system(size: 26))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                    Text(viewModel.entries.isEmpty ? "저장된 리포트가 없습니다" : "일치하는 리포트가 없습니다")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(18)
            } else {
                ScrollView {
                    LazyVStack(spacing: appearanceDensity.informationMetric(10)) {
                        ForEach(filteredEntries) { entry in
                            reportCard(entry)
                        }
                    }
                    .padding(.horizontal, appearanceDensity.informationMetric(12))
                    .padding(.bottom, appearanceDensity.informationMetric(14))
                }
            }
        }
        .frame(width: 250)
        .frame(maxHeight: .infinity)
        .background(PopoverChrome.surfaceAlt.opacity(0.34))
    }

    private func reportCard(_ entry: NewsReportArchiveEntry) -> some View {
        let document = viewModel.document(for: entry)
        let isSelected = viewModel.selectedEntryID == entry.id

        return Button {
            viewModel.select(entry.id)
        } label: {
            VStack(alignment: .leading, spacing: appearanceDensity.informationMetric(8)) {
                Text(entry.reportURL.lastPathComponent)
                    .font(.system(size: appearanceDensity.informationMetric(12.5), weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                    .lineLimit(1)

                Text("\(entry.itemCount)개 항목 · \(formattedFileSize(document?.fileSize))")
                    .font(.system(size: appearanceDensity.informationMetric(10.5), weight: .medium, design: .rounded))
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
            .padding(appearanceDensity.informationMetric(11))
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
                    Text(viewModel.entries.isEmpty ? "리포트를 생성하면 이곳에서 볼 수 있습니다" : "왼쪽에서 리포트를 선택해주세요")
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
        let document = viewModel.document(for: entry)

        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: appearanceDensity.informationMetric(7)) {
                Text(entry.reportURL.lastPathComponent)
                    .font(.system(size: appearanceDensity.informationMetric(17), weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(formattedDate(entry.reportDate))
                        .font(.system(size: appearanceDensity.informationMetric(11), weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                    if let keywords = document?.interestKeywords, !keywords.isEmpty {
                        Text("관심 키워드")
                            .font(.system(size: appearanceDensity.informationMetric(10.5), weight: .semibold, design: .rounded))
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
        if let document = viewModel.document(for: entry) {
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
                    LazyVStack(alignment: .leading, spacing: appearanceDensity.informationMetric(12)) {
                        ForEach(Array(NewsReportMarkdownParser.parse(document.markdown).enumerated()), id: \.offset) { _, block in
                            markdownBlock(block)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, appearanceDensity.informationMetric(24))
                    .padding(.vertical, appearanceDensity.informationMetric(22))
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
                .font(.system(size: appearanceDensity.informationMetric(22), weight: .bold, design: .rounded))
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
                .font(.system(size: appearanceDensity.informationMetric(level == 2 ? 18 : 15), weight: .bold, design: .rounded))
                .foregroundStyle(level == 2 ? PopoverChrome.accent : PopoverChrome.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, level == 2 ? 10 : 5)
                .padding(.bottom, level == 2 ? 2 : 0)

        case .metadata(let text):
            Text(inlineMarkdown(text))
                .font(.system(size: appearanceDensity.informationMetric(11.5), weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)

        case .quote(let text):
            HStack(spacing: 8) {
                Capsule()
                    .fill(PopoverChrome.accent)
                    .frame(width: 3)
                Text(inlineMarkdown(text))
                    .font(.system(size: appearanceDensity.informationMetric(11), weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(PopoverChrome.accentSoft.opacity(0.34), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))

        case .callout(let text):
            Text(inlineMarkdown(text))
                .font(.system(size: appearanceDensity.informationMetric(13), weight: .semibold, design: .rounded))
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
                .font(.system(size: appearanceDensity.informationMetric(12), weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(PopoverChrome.surfaceAlt.opacity(0.75), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))

        case .note(let text):
            Text(inlineMarkdown(text))
                .font(.system(size: appearanceDensity.informationMetric(11.5), weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)

        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Circle()
                    .fill(PopoverChrome.accent)
                    .frame(width: 5, height: 5)
                Text(inlineMarkdown(text))
                    .font(.system(size: appearanceDensity.informationMetric(12.5), weight: .regular, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 4)

        case .numbered(let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(number)
                    .font(.system(size: appearanceDensity.informationMetric(10), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .frame(width: 20, height: 20)
                    .background(PopoverChrome.accent, in: Circle())
                Text(inlineMarkdown(text))
                    .font(.system(size: appearanceDensity.informationMetric(12.5), weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .paragraph(let text):
            Text(inlineMarkdown(text))
                .font(.system(size: appearanceDensity.informationMetric(12.5), weight: .regular, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

        case .code(let text):
            ScrollView(.horizontal) {
                Text(text)
                    .font(.system(size: appearanceDensity.informationMetric(11), design: .monospaced))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .background(PopoverChrome.surfaceAlt, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))

        case .divider:
            Divider().overlay(PopoverChrome.divider)
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
