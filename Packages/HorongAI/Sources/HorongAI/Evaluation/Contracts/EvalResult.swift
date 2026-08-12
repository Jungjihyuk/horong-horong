import Foundation

/// 평가 결과 한 건을 나타내는 구조체 (JSONL 포맷과 1:1 매핑)
public struct EvalResult: Codable {
    public let caseId: String
    public let input: String?
    public let level: String
    public let model: String?
    public let output: String
    public let scores: [String: Double]
    public let latencyMs: Int
    
    enum CodingKeys: String, CodingKey {
        case caseId = "case_id"
        case input
        case level
        case model
        case output
        case scores
        case latencyMs = "latency_ms"
    }
    
    public init(caseId: String, input: String? = nil, level: String, model: String? = nil, output: String, scores: [String: Double], latencyMs: Int) {
        self.caseId = caseId
        self.input = input
        self.level = level
        self.model = model
        self.output = output
        self.scores = scores
        self.latencyMs = latencyMs
    }
}
