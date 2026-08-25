import Foundation

/// `RunRecord` 를 JSONL 파일에 한 줄씩 쌓는다.
///
/// 이름이 `EvalRunner` 였는데, 케이스를 돌리지도 채점하지도 않아 실제와 맞지 않았다.
/// 채점이 끝난 결과를 받아 적기만 한다 — 그래서 기록기다. 실험실(골든셋)과 야생(실사용)이
/// **같은 기록기**를 쓴다. 나눠 두면 두 결과를 나란히 놓을 수 없다.
///
/// 파일로 남기는 이유는 추론이 느리기 때문이다(케이스당 수 초). 한 번 돌려 떨궈 두면
/// **모델을 다시 안 돌리고** 채점 기준만 바꿔 재채점할 수 있다.
public final class RunLogger {
    private let outputURL: URL
    private let timestampStyle: TimestampStyle
    private let queue = DispatchQueue(label: "com.horonghorong.ai.runlogger")

    /// 이어 쓸지 새로 쓸지.
    public enum Mode {
        /// 런 하나 = 파일 하나. 기존 파일이 있으면 지운다(골든셋).
        case replace
        /// 실사용 기록처럼 계속 쌓이는 경우.
        case append
    }

    /// 기록 파일의 날짜 표기 시간대.
    /// 실사용 로그는 기존 UTC를 유지하고, 골든셋 결과만 KST로 읽기 쉽게 기록한다.
    public enum TimestampStyle {
        case utc
        case koreaStandardTime
    }

    public init(
        outputURL: URL,
        mode: Mode = .replace,
        timestampStyle: TimestampStyle = .utc
    ) {
        self.outputURL = outputURL
        self.timestampStyle = timestampStyle
        if mode == .replace, FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        if !FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        }
    }

    public func record(_ record: RunRecord) {
        queue.async {
            let encoder = JSONEncoder()
            // 한 줄이어야 하므로 prettyPrinted 를 쓰지 않는다.
            // 날짜는 사람이 읽고 다른 도구가 파싱할 수 있게 ISO8601 로 남긴다.
            switch self.timestampStyle {
            case .utc:
                encoder.dateEncodingStrategy = .iso8601
            case .koreaStandardTime:
                encoder.dateEncodingStrategy = .custom { date, encoder in
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
                    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"

                    var container = encoder.singleValueContainer()
                    try container.encode(formatter.string(from: date))
                }
            }
            guard let data = try? encoder.encode(record),
                  let json = String(data: data, encoding: .utf8),
                  let line = (json + "\n").data(using: .utf8) else {
                return
            }

            if let handle = try? FileHandle(forWritingTo: self.outputURL) {
                handle.seekToEndOfFile()
                handle.write(line)
                handle.closeFile()
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
