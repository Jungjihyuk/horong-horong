import Foundation

public struct PairEvaluator {
    
    /// 한 묶음에서 나올 수 있는 모든 2개 조합을 "a|b"(정렬) 형태로 만든다.
    public static func pairs(of group: [String]) -> Set<String> {
        let ids = group.sorted()
        var out = Set<String>()
        guard ids.count >= 2 else { return out }
        
        for i in 0..<ids.count {
            for j in (i + 1)..<ids.count {
                out.insert("\(ids[i])|\(ids[j])")
            }
        }
        return out
    }
    
    /// 여러 묶음의 쌍을 합집합으로 모은다.
    public static func pairs(ofAll groups: [[String]]) -> Set<String> {
        var out = Set<String>()
        for g in groups {
            out.formUnion(pairs(of: g))
        }
        return out
    }
    
    public struct Score {
        public let precision: Double
        public let recall: Double
        public let f1: Double
        public let hit: Int
        public let expectedPairs: Int
        public let predictedPairs: Int
        public let violations: Int
    }
    
    /// 쌍(Pair) 단위 F1 스코어를 계산한다. (score.mjs의 이식 버전)
    public static func score(
        expectedGroups: [[String]],
        predictedGroups: [[String]],
        shouldNotGroup: [[String]] = []
    ) -> Score {
        let expected = pairs(ofAll: expectedGroups)
        let predicted = pairs(ofAll: predictedGroups)
        let forbidden = pairs(ofAll: shouldNotGroup)
        
        var hit = 0
        var violations = 0
        
        for p in predicted {
            if expected.contains(p) { hit += 1 }
            if forbidden.contains(p) { violations += 1 }
        }
        
        let precision: Double
        if predicted.isEmpty {
            precision = expected.isEmpty ? 1.0 : 0.0
        } else {
            precision = Double(hit) / Double(predicted.count)
        }
        
        let recall: Double
        if expected.isEmpty {
            recall = predicted.isEmpty ? 1.0 : 0.0
        } else {
            recall = Double(hit) / Double(expected.count)
        }
        
        let f1: Double
        if precision + recall == 0 {
            f1 = 0.0
        } else {
            f1 = (2 * precision * recall) / (precision + recall)
        }
        
        return Score(
            precision: precision,
            recall: recall,
            f1: f1,
            hit: hit,
            expectedPairs: expected.count,
            predictedPairs: predicted.count,
            violations: violations
        )
    }
}
