import Foundation

/// 질문을 검색용 토큰으로 쪼갠다.
///
/// 검색기 하나에 속하지 않는다 — 설명서 검색과 설정 색인이 **같은 토큰**을 봐야
/// 두 근거가 같은 질문에 함께 걸린다. 한쪽만 규칙이 바뀌면 "설명서는 찾았는데
/// 설정 경로는 못 찾는" 어긋남이 조용히 생긴다.
public enum SearchTokens {

    /// 한국어는 조사가 붙어 있어 그대로는 잘 안 걸린다.
    /// 끝 한 글자를 뗀 형태도 함께 후보로 둔다("테마를" → "테마").
    public static func from(_ question: String) -> [String] {
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
}
