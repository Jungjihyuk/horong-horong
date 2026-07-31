import Foundation

/// 사용 설명서에서 잘라낸 한 섹션.
struct CompanionGuideSection: Equatable, Sendable {
    let title: String
    let body: String

    var injectedText: String { "\(title)\n\(body)" }
}

/// `USER_GUIDE.md` 를 읽어 질문에 맞는 섹션 하나만 골라낸다.
///
/// 문서 전체를 넣을 수는 없다. 온디바이스 모델의 컨텍스트가 짧고,
/// 오늘 확인했듯 프롬프트가 길어질수록 답이 무너진다.
/// 그래서 근거가 될 한 조각만 골라 넣고, 없으면 아무것도 넣지 않는다.
enum CompanionGuide {
    static let resourceName = "USER_GUIDE"

    /// 프롬프트에 넣을 섹션 길이 상한(글자).
    static let maxSectionLength = 700

    /// `## ` 제목을 기준으로 자른다. 하위 제목(`###`)은 섹션 안에 남긴다.
    static func sections(from markdown: String) -> [CompanionGuideSection] {
        var sections: [CompanionGuideSection] = []
        var title: String?
        var body: [String] = []

        func flush() {
            defer { title = nil; body = [] }
            guard let title else { return }
            let text = body
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            sections.append(CompanionGuideSection(title: title, body: text))
        }

        for line in markdown.components(separatedBy: .newlines) {
            if line.hasPrefix("## ") {
                flush()
                title = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if title != nil {
                body.append(line)
            }
        }
        flush()
        return sections
    }

    /// 질문과 가장 많이 겹치는 섹션. 겹치는 게 없으면 nil 이라 근거 없이 답하지 않는다.
    static func bestMatch(
        for question: String,
        in sections: [CompanionGuideSection]
    ) -> CompanionGuideSection? {
        let tokens = searchTokens(in: question)
        guard !tokens.isEmpty else { return nil }

        var best: (section: CompanionGuideSection, score: Int)?
        for section in sections {
            let title = section.title.lowercased()
            let body = section.body.lowercased()
            var score = 0
            for token in tokens {
                // 제목에 걸리면 훨씬 확실한 단서다.
                if title.contains(token) { score += 5 }
                if body.contains(token) { score += 1 }
            }
            guard score > 0 else { continue }
            if best == nil || score > best!.score {
                best = (section, score)
            }
        }
        return best?.section
    }

    /// 한국어는 조사가 붙어 있어 그대로는 잘 안 걸린다.
    /// 끝 한 글자를 뗀 형태도 함께 후보로 둔다("테마를" → "테마").
    static func searchTokens(in question: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(CharacterSet(charactersIn: "?!"))

        var tokens: Set<String> = []
        for raw in question.lowercased().components(separatedBy: separators) {
            let word = raw.trimmingCharacters(in: .whitespaces)
            guard word.count >= 2 else { continue }
            tokens.insert(word)
            if word.count >= 3 {
                tokens.insert(String(word.dropLast()))
            }
        }
        return Array(tokens)
    }

    /// 길면 앞부분만 쓴다. 근거가 길어지면 오히려 답이 흐트러진다.
    static func clipped(_ text: String, limit: Int = maxSectionLength) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "\n(이하 생략)"
    }

    static func loadFromBundle(_ bundle: Bundle = .main) -> [CompanionGuideSection] {
        guard let url = bundle.url(forResource: resourceName, withExtension: "md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return sections(from: markdown)
    }
}

/// 사용자의 말이 "이 앱을 어떻게 쓰는지" 묻는 것인지 판정한다.
enum CompanionGuideQuestion {
    private static let keywords = [
        "어떻게", "어디서", "어디에", "어디야", "방법", "하는 법", "하는법",
        "뭐가 있", "뭐 있", "무엇이 있", "설정", "바꾸", "켜", "끄", "쓰는",
        "사용법", "기능", "가능해", "돼?", "되나", "할 수 있",
    ]

    static func matches(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return keywords.contains { normalized.contains($0) }
    }
}
