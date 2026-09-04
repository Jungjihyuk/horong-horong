import SwiftUI
import AppKit

enum BrainMarkdownBlock: Identifiable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case quote(String)
    case bullet(String, task: Bool?)
    case numbered(Int, String)
    case code(String)
    case divider
    case empty

    var id: String {
        switch self {
        case .heading(let level, let text): return "h\(level)-\(text)"
        case .paragraph(let text): return "p-\(text.prefix(40))"
        case .quote(let text): return "q-\(text.prefix(40))"
        case .bullet(let text, let task): return "b-\(task?.description ?? "")-\(text.prefix(40))"
        case .numbered(let n, let text): return "n-\(n)-\(text.prefix(40))"
        case .code(let text): return "c-\(text.prefix(40))"
        case .divider: return "hr"
        case .empty: return "empty"
        }
    }
}

enum BrainMarkdownParser {
    static func parse(_ markdown: String) -> (title: String?, blocks: [BrainMarkdownBlock]) {
        var source = markdown
        if source.hasPrefix("---") {
            if let end = source.range(of: "\n---", range: source.index(after: source.startIndex)..<source.endIndex) {
                source = String(source[end.upperBound...]).trimmingCharacters(in: .newlines)
            }
        }

        var blocks: [BrainMarkdownBlock] = []
        var title: String?
        var inCode = false
        var codeLines: [String] = []
        var number = 0

        for raw in source.components(separatedBy: .newlines) {
            if raw.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(codeLines.joined(separator: "\n")))
                    codeLines.removeAll()
                }
                inCode.toggle()
                continue
            }
            if inCode {
                codeLines.append(raw)
                continue
            }

            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                number = 0
                continue
            }
            if line == "---" || line == "***" {
                blocks.append(.divider)
                continue
            }
            if let heading = heading(line) {
                if title == nil { title = heading.text }
                blocks.append(.heading(level: heading.level, text: heading.text))
                continue
            }
            if line.hasPrefix("> ") {
                blocks.append(.quote(String(line.dropFirst(2))))
                continue
            }
            if let task = taskItem(line) {
                blocks.append(.bullet(task.text, task: task.done))
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                blocks.append(.bullet(String(line.dropFirst(2)), task: nil))
                continue
            }
            if let numbered = numberedItem(line) {
                number = numbered.number
                blocks.append(.numbered(number, numbered.text))
                continue
            }
            blocks.append(.paragraph(line))
        }
        if !codeLines.isEmpty {
            blocks.append(.code(codeLines.joined(separator: "\n")))
        }
        return (title, blocks)
    }

    private static func heading(_ line: String) -> (level: Int, text: String)? {
        guard line.hasPrefix("#") else { return nil }
        var level = 0
        for character in line {
            if character == "#" { level += 1 } else { break }
        }
        guard (1...4).contains(level), line.count > level, line[line.index(line.startIndex, offsetBy: level)] == " " else {
            return nil
        }
        return (level, String(line.dropFirst(level + 1)))
    }

    private static func taskItem(_ line: String) -> (done: Bool, text: String)? {
        if line.hasPrefix("- [ ] ") { return (false, String(line.dropFirst(6))) }
        if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") { return (true, String(line.dropFirst(6))) }
        return nil
    }

    private static func numberedItem(_ line: String) -> (number: Int, text: String)? {
        guard let dot = line.firstIndex(of: ".") else { return nil }
        let numberText = String(line[..<dot])
        guard let number = Int(numberText) else { return nil }
        let text = line[line.index(after: dot)...].trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (number, text)
    }
}

struct MarkdownDocumentView: View {
    /// 블록마다·렌더마다 새로 컴파일하면 패턴 파싱과 NFA 구성이 그만큼 반복된다.
    private static let wikiLinkRegex = try? NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#)

    let markdown: String
    var onWikiLink: ((String) -> Void)?

    var body: some View {
        let parsed = BrainMarkdownParser.parse(markdown)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(Array(parsed.blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }

    @ViewBuilder
    private func blockView(_ block: BrainMarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineText(text)
                .font(.system(size: level == 1 ? 26 : level == 2 ? 20 : 16, weight: .bold, design: .rounded))
                .foregroundStyle(level <= 2 ? PopoverChrome.accent : PopoverChrome.ink)
                .padding(.top, level == 1 ? 4 : 10)
        case .paragraph(let text):
            inlineText(text)
                .font(.system(size: 14.5, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
                .fixedSize(horizontal: false, vertical: true)
        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                Capsule().fill(PopoverChrome.accent).frame(width: 3)
                inlineText(text)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
            }
            .padding(10)
            .background(PopoverChrome.accentSoft.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .bullet(let text, let task):
            HStack(alignment: .top, spacing: 8) {
                if let task {
                    Image(systemName: task ? "checkmark.square.fill" : "square")
                        .foregroundStyle(task ? PopoverChrome.accent : PopoverChrome.inkTertiary)
                } else {
                    Text("•").foregroundStyle(PopoverChrome.accent)
                }
                inlineText(text)
                    .font(.system(size: 14, design: .rounded))
                    .strikethrough(task == true)
            }
        case .numbered(let number, let text):
            HStack(alignment: .top, spacing: 8) {
                Text("\(number).")
                    .foregroundStyle(PopoverChrome.accent)
                    .monospacedDigit()
                inlineText(text)
                    .font(.system(size: 14, design: .rounded))
            }
        case .code(let text):
            Text(text)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(PopoverChrome.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(PopoverChrome.surfaceAlt, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .textSelection(.enabled)
        case .divider:
            Divider().overlay(PopoverChrome.divider)
        case .empty:
            EmptyView()
        }
    }

    private func inlineText(_ source: String) -> Text {
        var attributed = AttributedString(source)
        if let regex = Self.wikiLinkRegex {
            let ns = source as NSString
            let matches = regex.matches(in: source, range: NSRange(location: 0, length: ns.length))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: source),
                      let inner = Range(match.range(at: 1), in: source) else { continue }
                let title = String(source[inner]).split(separator: "|").first.map(String.init) ?? String(source[inner])
                var replacement = AttributedString(title)
                replacement.foregroundColor = PopoverChrome.accent
                replacement.underlineStyle = .single
                if let attrRange = Range(match.range, in: attributed) {
                    attributed.replaceSubrange(attrRange, with: replacement)
                }
                _ = range
            }
        }
        return Text(attributed)
    }
}
