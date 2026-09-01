#if DEBUG
import Foundation

/// 창 여는 비용이 어디서 나는지 확인하는 임시 계측기.
///
/// **파일에 남긴다.** `print` 는 Xcode 콘솔에만 있고, `Logger` 는 실행 방식에 따라
/// 통합 로그에서 안 잡히는 경우가 있었다. 파일은 앱이 꺼진 뒤에도 남는다.
///
///     tail -40 ~/Library/Application\ Support/HorongHorong-Debug/perf.log
///
/// **원인을 찾으면 이 파일과 호출부를 지운다.**
@MainActor
enum PerfLog {
    private static var origin: CFAbsoluteTime?

    private static var fileURL: URL? {
        try? SwiftDataStoreLocation.applicationDirectoryURL()
            .appendingPathComponent("perf.log")
    }

    /// 측정 구간의 시작. 이후 `mark` 들이 이 시각을 기준으로 찍힌다.
    static func start(_ label: String) {
        origin = CFAbsoluteTimeGetCurrent()
        write("───── \(label) 시작  \(stamp()) ─────")
    }

    static func mark(_ label: String) {
        guard let origin else {
            write("        (기준 없음)  \(label)")
            return
        }
        let ms = (CFAbsoluteTimeGetCurrent() - origin) * 1000
        write(String(format: "%8.1fms  %@", ms, label))
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }

    private static func write(_ line: String) {
        print("⏱ [perf] \(line)")          // Xcode 콘솔에도 남긴다
        guard let fileURL else { return }
        guard let data = (line + "\n").data(using: .utf8) else { return }

        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }
    }
}
#endif
