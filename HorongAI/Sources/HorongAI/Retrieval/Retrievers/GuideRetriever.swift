import Foundation

/// 사용 설명서에서 잘라낸 한 섹션.
public struct GuideSection: Equatable, Sendable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }

    public var injectedText: String { "\(title)\n\(body)" }
}

/// 마크다운 설명서에서 질문에 맞는 섹션 하나만 골라낸다.
///
/// 문서 전체를 넣을 수는 없다. 온디바이스 모델의 컨텍스트가 짧고,
/// 프롬프트가 길어질수록 답이 무너진다(인시던트 2026-07-31).
/// 그래서 근거가 될 한 조각만 골라 넣고, 없으면 아무것도 넣지 않는다.
///
/// 마크다운을 **어디서 읽어 오는지는 모른다.** 앱이 번들에서 읽어 문자열로 넘긴다 —
/// 패키지가 앱 번들(`USER_GUIDE.md`)을 알면 평가가 앱 빌드에 묶인다.
public enum GuideRetriever {

    /// 프롬프트에 넣을 섹션 길이 상한(글자).
    public static let maxSectionLength = 700

    /// `## ` 제목을 기준으로 자른다. 하위 제목(`###`)은 섹션 안에 남긴다.
    public static func sections(from markdown: String) -> [GuideSection] {
        var sections: [GuideSection] = []
        var title: String?
        var body: [String] = []

        func flush() {
            defer { title = nil; body = [] }
            guard let title else { return }
            let text = body
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            sections.append(GuideSection(title: title, body: text))
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
    public static func bestMatch(
        for question: String,
        in sections: [GuideSection]
    ) -> GuideSection? {
        let tokens = SearchTokens.from(question)
        guard !tokens.isEmpty else { return nil }

        var best: (section: GuideSection, score: Int)?
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

    /// 길면 앞부분만 쓴다. 근거가 길어지면 오히려 답이 흐트러진다.
    public static func clipped(_ text: String, limit: Int = maxSectionLength) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "\n(이하 생략)"
    }
}
