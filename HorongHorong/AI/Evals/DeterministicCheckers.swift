import Foundation

/// AI 텍스트 출력의 품질을 결정적으로(규칙 기반으로) 검사하는 유틸리티
public struct DeterministicCheckers {
    
    /// 문장 끝이 존댓말("요", "다", "까", "죠")로 끝나는지 검사하여 비율 반환 (0.0 ~ 1.0)
    public static func checkHonorific(_ text: String) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0.0 }
        
        // 줄바꿈이나 문장 부호로 분리하여 문장 배열 추출
        let sentences = trimmed.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        if sentences.isEmpty { return 0.0 }
        
        var honorificCount = 0
        for sentence in sentences {
            if sentence.hasSuffix("요") || 
               sentence.hasSuffix("다") || 
               sentence.hasSuffix("까") ||
               sentence.hasSuffix("죠") ||
               sentence.hasSuffix("니다") {
                honorificCount += 1
            }
        }
        
        return Double(honorificCount) / Double(sentences.count)
    }
    
    /// 텍스트의 문장 수가 제한(기본 3)을 넘지 않는지 검사 (초과 시 감점)
    public static func checkSentenceCount(_ text: String, maxCount: Int = 3) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0.0 }
        
        let sentences = trimmed.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        let count = sentences.count
        if count <= maxCount {
            return 1.0
        } else {
            // 한 문장 초과할 때마다 0.5점씩 깎음 (매우 엄격하게 제재)
            let penalty = Double(count - maxCount) * 0.5
            return max(0.0, 1.0 - penalty)
        }
    }
    
    /// 마크다운 기호(*, #, - 등)가 노출되지 않고 정제되었는지 검사 (기호가 없을수록 1.0)
    public static func checkMarkdownSymbols(_ text: String) -> Double {
        let symbols = CharacterSet(charactersIn: "*#`")
        let totalCount = text.count
        if totalCount == 0 { return 1.0 }
        
        var symbolCount = 0
        for char in text.unicodeScalars {
            if symbols.contains(char) {
                symbolCount += 1
            }
        }
        
        if symbolCount == 0 { return 1.0 }
        
        // 기호가 조금이라도 나오면 점수를 크게 차감
        let score = 1.0 - (Double(symbolCount) * 0.2)
        return max(0.0, score)
    }
}
