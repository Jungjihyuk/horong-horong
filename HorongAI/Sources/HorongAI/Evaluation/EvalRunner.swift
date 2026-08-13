import Foundation

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

    /// 큐에 밀어 넣은 기록이 전부 파일에 닿을 때까지 기다린다.
    ///
    /// `record` 는 비동기라 호출 직후 프로세스가 끝나면 마지막 결과가 유실된다.
    /// 케이스가 늘거나 CI 에서 빨리 끝날수록 확률이 올라가는데, 조용히 한 줄이 사라지는
    /// 종류라 나중에 원인을 찾기 어렵다. 런을 마칠 때 반드시 부른다.
    public func flush() {
        queue.sync {}
    }
}
