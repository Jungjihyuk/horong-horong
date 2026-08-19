import Foundation

/// `RunTrace` 를 실행당 파일 하나로 남긴다.
///
/// **기본은 꺼져 있다.** 앱이 개발자 모드일 때만 켠다 — 원문에는 사용자의 할일이 그대로 들어간다.
///
/// 요약(`RunRecord`)과 파일을 나눈 이유는 크기다. 프롬프트가 3천~1만 6천 자인데 요약 파일에
/// 같이 넣으면 리포트 도구가 매번 그걸 다 읽는다. 실행당 파일로 두면 **필요할 때만** 연다.
///
/// ```
/// runs/2026-08-17.jsonl                      요약 — 항상
/// runs/traces/R-20260817-163944-EC36.json    원문 — 개발자 모드에서만
/// ```
public final class TraceRecorder {
    /// 앱이 시작할 때 켠다. 패키지는 `UserDefaults` 를 읽지 않으므로 주입받는다.
    ///
    /// ```swift
    /// TraceRecorder.shared = TraceRecorder(directory: …, isEnabled: 개발자모드)
    /// ```
    /// `nonisolated(unsafe)` 인 이유: **앱이 시작할 때 한 번만 쓰고 그 뒤로는 읽기만 한다.**
    /// 실제 쓰기는 인스턴스 내부 큐가 직렬화하므로 경쟁이 생기는 자리는 이 대입 한 번뿐이다.
    nonisolated(unsafe) public static var shared: TraceRecorder?

    private let directory: URL
    let isEnabled: Bool
    private let retention: TimeInterval
    private let queue = DispatchQueue(label: "com.horonghorong.ai.tracerecorder")

    /// - Parameter retentionDays: 이보다 오래된 파일은 지운다. 켜 둔 걸 잊어도 무한정 쌓이지 않게.
    public init(directory: URL, isEnabled: Bool, retentionDays: Int = 7) {
        self.directory = directory
        self.isEnabled = isEnabled
        self.retention = TimeInterval(retentionDays * 24 * 60 * 60)
    }

    public func record(_ trace: RunTrace) {
        guard isEnabled else { return }
        queue.async {
            do {
                try FileManager.default.createDirectory(
                    at: self.directory,
                    withIntermediateDirectories: true
                )
                let encoder = JSONEncoder()
                // 사람이 직접 열어 읽는 파일이다. 한 줄로 뭉쳐 놓으면 아무 소용이 없다.
                encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(trace)
                try data.write(
                    to: self.fileURL(runId: trace.runId, task: trace.task, attempt: trace.attempt),
                    options: .atomic
                )
            } catch {
                // 기록은 부수 작업이다. 여기서 던지면 본래 하려던 일까지 죽는다.
                AILog.recording.error("trace 기록 실패 runId=\(trace.runId, privacy: .public)")
            }
        }
    }

    /// 파일 하나가 **시도 하나**다.
    ///
    /// `runId` 만으로 이름을 지으면 덮인다. 주간·월간은 한 번 누른 실행을 묶으려고 **설계상
    /// 같은 `runId` 를 공유**하고, 폴백이 일어나면 한 태스크가 시도를 여러 번 한다.
    ///
    /// 실측(2026-08-19) — 한 실행이 trace 3개를 만들었는데 파일은 1개만 남았고, 그것도
    /// **나중에 쓴 성공한 폴백**이 남아 정작 보려던 실패가 지워졌다. 원문을 남기는 목적이
    /// 실패를 쫓는 것인데 실패만 골라 지우는 셈이었다.
    public func fileURL(runId: String, task: String? = nil, attempt: Int? = nil) -> URL {
        directory.appendingPathComponent(Self.fileName(runId: runId, task: task, attempt: attempt))
    }

    /// `R-20260819-154405-9F5C_weekly_goal_1.json`
    ///
    /// `runId` 를 맨 앞에 두는 이유는 한 실행의 시도들을 **이름만으로 모을 수 있게** 하기
    /// 위해서다(`runId` 에는 `_` 가 없으므로 접두사로 안전하게 걸린다).
    static func fileName(runId: String, task: String?, attempt: Int?) -> String {
        var name = runId
        if let task, !task.isEmpty { name += "_\(task)" }
        if let attempt { name += "_\(attempt)" }
        return name + ".json"
    }

    public func trace(runId: String, task: String? = nil, attempt: Int? = nil) -> RunTrace? {
        let url = fileURL(runId: runId, task: task, attempt: attempt)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(RunTrace.self, from: data)
    }

    /// 보존 기한이 지난 파일을 지운다. 앱 시작 시 한 번 부른다.
    ///
    /// 켜 둔 것을 잊는 일이 실제로 일어나므로, 끄는 것에 기대지 않고 스스로 줄어들게 한다.
    public func purgeExpired(now: Date = Date()) {
        queue.async {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: self.directory,
                includingPropertiesForKeys: [.contentModificationDateKey]
            )) ?? []
            for file in files where file.pathExtension == "json" {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
                guard let modified, now.timeIntervalSince(modified) > self.retention else { continue }
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// 큐에 넣은 쓰기가 끝날 때까지 기다린다. `RunLogger.flush()` 와 같은 사정이다.
    public func flush() {
        queue.sync {}
    }
}

extension TraceRecorder {
    /// 이 실행의 원문을 모을 수집기. **꺼져 있으면 `nil`** 이라 부르는 쪽이 아무 비용도 치르지 않는다.
    public func makeCollector(
        runId: String,
        task: String? = nil,
        provider: String? = nil,
        model: String? = nil,
        attempt: Int? = nil
    ) -> TraceCollector? {
        guard isEnabled else { return nil }
        return TraceCollector(runId: runId, task: task, provider: provider, model: model, attempt: attempt)
    }

    /// 수집기가 모은 것을 파일로 남긴다.
    public func record(_ collector: TraceCollector) {
        record(collector.finish())
    }
}

/// 실행 한 건의 원문을 모은다.
///
/// 태스크가 `trace?.add(…)` 로 부르므로, 꺼져 있으면(`nil`) 문자열을 만드는 비용조차 들지 않는다.
/// `RunOutcome` 에 원문을 싣지 않기로 한 결정을 지키면서 원문을 꺼내는 통로다.
public final class TraceCollector {
    private var trace: RunTrace
    private let lock = NSLock()

    init(runId: String, task: String?, provider: String?, model: String?, attempt: Int?) {
        self.trace = RunTrace(runId: runId, task: task, provider: provider, model: model, attempt: attempt)
    }

    public func add(_ name: RunTrace.Span.Name, _ text: String, facts: [String: Int]? = nil) {
        lock.lock()
        defer { lock.unlock() }
        trace.append(.init(name, text: text, facts: facts))
    }

    public func finish() -> RunTrace {
        lock.lock()
        defer { lock.unlock() }
        return trace
    }
}
