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

/// 채점 결과를 모아서 JSONL 파일로 떨궈주는 실행기(로거)
public class EvalRunner {
    private let outputURL: URL
    private let queue = DispatchQueue(label: "com.horonghorong.evalrunner")
    
    /// 새로운 평가 런(Run)을 시작하며, 기존 파일이 있다면 덮어씁니다.
    public init(outputURL: URL) {
        self.outputURL = outputURL
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: nil)
    }
    
    /// 테스트 케이스 하나의 결과를 JSONL 형식으로 파일 끝에 추가합니다.
    public func record(_ result: EvalResult) {
        queue.async {
            let encoder = JSONEncoder()
            // 한 줄로 출력되어야 하므로 prettyPrinted 옵션은 사용하지 않음
            guard let data = try? encoder.encode(result),
                  let jsonString = String(data: data, encoding: .utf8),
                  let textData = (jsonString + "\n").data(using: .utf8) else {
                return
            }
            
            if let fileHandle = try? FileHandle(forWritingTo: self.outputURL) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(textData)
                fileHandle.closeFile()
            }
        }
    }
}
