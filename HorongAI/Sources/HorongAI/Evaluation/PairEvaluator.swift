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
    
    /// **특히 틀리기 쉬운 자리.** 「묶이면 안 되는 모든 쌍」을 나열하는 대신,
    /// 그 케이스가 겨냥한 함정만 골라 적는다.
    ///
    /// 모든 쌍을 적으려 하면 조합이 폭발한다 — 3개짜리 묶음 둘이 합쳐지는 걸 막으려면
    /// 9쌍을 적어야 하는데, 그러면 무엇이 진짜 함정인지 묻혀 버린다.
    public struct Trap: Codable, Sendable, Equatable {
        /// 왜 함정인가. **이게 없으면 나중에 «왜 이걸 적었지» 가 된다.**
        public let why: String?
        /// - 묶음이 **하나**면 → 그 안의 항목들이 **서로** 묶이면 안 된다
        ///   (예: 같은 앱을 쓸 뿐인 할일 셋)
        /// - 묶음이 **둘 이상**이면 → 그 묶음들이 **합쳐지면** 안 된다.
        ///   묶음 **안**은 판단하지 않는다 — 오히려 정답일 수 있다
        public let groups: [[String]]

        public init(why: String? = nil, groups: [[String]]) {
            self.why = why
            self.groups = groups
        }
    }

    /// 함정이 금지하는 쌍들.
    public static func pairs(ofTrap trap: Trap) -> Set<String> {
        let groups = trap.groups.filter { !$0.isEmpty }
        guard groups.count >= 2 else {
            // 묶음 하나 — 그 안에서 서로 묶이면 안 된다.
            return pairs(ofAll: groups)
        }
        // 묶음 여럿 — **묶음 사이**만 금지한다. 묶음 안은 정답일 수 있다.
        var out = Set<String>()
        for i in 0..<groups.count {
            for j in (i + 1)..<groups.count {
                for a in groups[i] {
                    for b in groups[j] where a != b {
                        out.insert([a, b].sorted().joined(separator: "|"))
                    }
                }
            }
        }
        return out
    }

    public static func pairs(ofAllTraps traps: [Trap]) -> Set<String> {
        traps.reduce(into: Set<String>()) { $0.formUnion(pairs(ofTrap: $1)) }
    }

    public struct Score {
        public let precision: Double
        public let recall: Double
        /// 순수 쌍 단위 F1. **함정 감점 전** 값이라 옛 기록과 그대로 비교된다.
        public let f1: Double
        public let hit: Int
        public let expectedPairs: Int
        public let predictedPairs: Int
        /// 밟은 함정 쌍의 수.
        public let violations: Int
        /// 전체 함정 쌍의 수. 함정을 안 적은 케이스는 0.
        public let trapPairs: Int

        /// 함정을 얼마나 피했나. 함정이 없으면 `1.0`.
        public var trapAvoidance: Double {
            guard trapPairs > 0 else { return 1.0 }
            return 1.0 - Double(violations) / Double(trapPairs)
        }

        /// **묶음 일치도** — 최종 점수. F1 에 함정 회피를 곱한다.
        ///
        /// 함정 쌍은 이미 precision 을 한 번 깎는다(정답이 아닌 쌍이므로). 거기 더해 곱하는 이유는
        /// **함정이 보통 실수보다 무겁기** 때문이다 — 그 케이스가 존재하는 이유가 그 함정이다.
        /// 함정을 전부 밟으면 묶음을 아무리 잘해도 0 이 된다.
        public var groupingScore: Double { f1 * trapAvoidance }
    }
    
    /// 쌍(Pair) 단위로 채점한다. (score.mjs 와 같은 계산)
    public static func score(
        expectedGroups: [[String]],
        predictedGroups: [[String]],
        traps: [Trap] = []
    ) -> Score {
        let expected = pairs(ofAll: expectedGroups)
        let predicted = pairs(ofAll: predictedGroups)
        let forbidden = pairs(ofAllTraps: traps)
        
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
            violations: violations,
            trapPairs: forbidden.count
        )
    }
}
