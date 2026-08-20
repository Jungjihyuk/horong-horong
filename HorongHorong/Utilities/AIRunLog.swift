import Foundation
import HorongAI

/// 실사용 AI 실행을 **파일로** 남기는 자리.
///
/// `OSLog`(터미널)와 나뉜 이유가 둘이다.
/// ① 시스템 로그는 순환 삭제라 **며칠 뒤 사라진다** — "지난주보다 나아졌나"를 물을 수 없다.
/// ② 로그는 문장이라 기계가 못 읽는다. 아홉 줄을 타임스탬프로 손수 맞춰야 한 번의 실행이 보인다.
///
/// 골든셋(`GoalSuggestionEvalTests`)과 **같은 `RunRecord` 모양**을 쓴다.
/// 나눠 두면 "실험실에선 좋아졌는데 실사용은 어떤가"를 나란히 놓을 수 없다.
///
/// **사용자 내용은 담지 않는다.** 할 일 제목 대신 id 만 남기고, 원문이 필요하면
/// 저장소에서 붙인다(→ `RunRecord`).
enum AIRunLog {

    /// 하루치를 한 파일에 쌓는다. 실행마다 파일을 만들면 금세 수천 개가 된다.
    ///
    /// 릴리스 앱은 리포지토리에 쓸 수 없으므로 앱 지원 폴더에 남긴다.
    /// 디버그·릴리스가 다른 폴더를 쓰는 것도 앱의 기존 관례를 그대로 따른다
    /// (`SwiftDataStoreLocation` — 개발 중 기록이 실사용 기록을 오염시키지 않는다).
    static func currentLogger(now: Date = Date()) -> RunLogger? {
        guard let directory = try? SwiftDataStoreLocation.applicationDirectoryURL()
            .appendingPathComponent("runs", isDirectory: true) else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let file = directory.appendingPathComponent("\(formatter.string(from: now)).jsonl")
        return RunLogger(outputURL: file, mode: .append)
    }

    /// 실행 한 건을 남긴다. 실패해도 조용히 넘어간다 — **기록 때문에 기능이 멈추면 안 된다.**
    static func record(_ record: RunRecord) {
        guard let logger = currentLogger() else { return }
        logger.record(record)
        // 앱은 골든셋 러너처럼 곧 끝나지 않지만, 마지막 줄이 유실되는 것보다
        // 여기서 잠깐 기다리는 편이 낫다. 한 줄 쓰는 데 드는 시간이다.
        logger.flush()
    }

    /// 원문(trace) 기록기를 세운다. 앱이 시작할 때 한 번 부른다.
    ///
    /// **개발자 모드에서만 켜진다.** 원문에는 프롬프트 전문과 사용자의 할 일이 그대로 들어가므로
    /// 기본은 꺼짐이다. 켜는 법은 AI 실험실 탭을 켜는 것과 같다 —
    /// Debug 빌드는 자동, Release 는 `defaults write com.horonghorong.app ailab.enabled -bool YES`.
    ///
    /// 패키지는 `UserDefaults` 를 읽지 않으므로 그 판단을 여기서 해 주입한다.
    static func installTraceRecorder(now: Date = Date()) {
        guard let directory = try? SwiftDataStoreLocation.applicationDirectoryURL()
            .appendingPathComponent("runs", isDirectory: true)
            .appendingPathComponent("traces", isDirectory: true) else {
            return
        }
        let recorder = TraceRecorder(
            directory: directory,
            isEnabled: SettingsTab.showsDeveloperTabs
        )
        TraceRecorder.shared = recorder
        // 켜 둔 것을 잊는 일이 실제로 있다. 끄는 것에 기대지 않고 스스로 줄어들게 한다.
        recorder.purgeExpired(now: now)
    }

    /// 버튼 한 번에 붙는 id. 주간·월간이 이 값을 공유해 한 실행으로 묶인다.
    static func newRunID(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "R-\(formatter.string(from: now))-\(UUID().uuidString.prefix(4))"
    }
}

/// 한 번의 실행을 기록으로 묶는 데 필요한 것들.
///
/// **시도마다 한 줄이 나가므로** 순번(`attemptNumber`)을 달고 다닌다. Ollama 가 실패해
/// AFM 으로 내려가면 두 시도는 예산이 달라(16k vs 4k) 입력 자체가 다른 질문이 된다 —
/// 최종 결과만 남기면 실패한 시도의 시간과 입력이 통째로 사라진다.
struct RunContext {
    let runID: String
    /// `"weekly_goal"` · `"monthly_goal"`.
    let task: String
    /// 필터를 통과한 전체 후보 수. `item_count` 와 벌어질수록 모델이 못 본 것이 많다(실측 123 → 6).
    let candidateCount: Int
    /// 주간·월간을 **어떻게 돌렸나** — `"parallel"` · `"sequential"`.
    ///
    /// 어느 쪽이 빠른지는 공급자마다 다르고 우리는 아직 추측으로 정해 두었다.
    /// 기록에 남겨야 «AFM 은 정말 병렬이 빠른가» 를 숫자로 답할 수 있다.
    var variant: String?
    var attemptNumber: Int = 1

    func attempt(_ number: Int) -> RunContext {
        var copy = self
        copy.attemptNumber = number
        return copy
    }

    /// 이 시도의 기록 한 줄.
    ///
    /// `scores` 는 비운다 — `pairF1` 은 정답 묶음이 있어야 매길 수 있고, 사용자의 할일에는 정답이 없다.
    func record(
        startedAt: Date,
        provider: String,
        model: String?,
        outcome: String,
        outcomeDetail: String? = nil,
        titles: [String] = [],
        selectedIDs: [UUID] = [],
        promptCharacters: Int = 0,
        parse: RunRecord.ParseSummary? = nil,
        usage: RunRecord.UsageSummary? = nil,
        timings: [String: Int] = [:],
        parameters: [String: Double]? = nil,
        /// 어떤 기법을 켠 실행인가. 모델은 프롬프트만 쓰고, 룰 폴백은 어느 룰인지 담는다.
        recipe: String = "promptOnly"
    ) -> RunRecord {
        RunRecord(
            model: model,
            // 사람이 훑어볼 요약. 입력이 아니라 **출력**이라 원문 규칙에 걸리지 않는다.
            output: titles.map { "- \($0)" }.joined(separator: "\n"),
            totalMs: Int(Date().timeIntervalSince(startedAt) * 1000),
            runId: runID,
            startedAt: startedAt,
            task: task,
            source: "live",
            recipe: recipe,
            variant: variant,
            provider: provider,
            attempt: attemptNumber,
            inputSummary: RunRecord.InputSummary(
                candidateCount: candidateCount,
                itemCount: selectedIDs.count,
                itemIDs: selectedIDs.map(\.uuidString),
                promptCharacters: promptCharacters
            ),
            outcome: outcome,
            outcomeDetail: outcomeDetail,
            parse: parse,
            usage: usage,
            timings: timings,
            parameters: parameters
        )
    }
}

extension Error {
    /// 발생한 에러를 분석하여 타임아웃, 연결 거부, 네트워크 단절 등 구체적인 원인을 반환한다.
    var detailedFailureReason: String {
        if self is CancellationError {
            return "timeout"
        }
        // 안 받아 둔 모델을 고른 것뿐인데 `inferenceError` 로 남으면 모델이 고장 난 것처럼 보인다.
        // 보통은 `preflight` 가 먼저 막지만, 고른 뒤 `ollama rm` 을 하면 여기까지 온다.
        if case .modelNotFound = (self as? OllamaChatError) ?? .serverUnavailable {
            return "modelUnavailable"
        }
        if let urlError = self as? URLError {
            switch urlError.code {
            case .timedOut:
                return "timeout"
            case .cannotConnectToHost, .cannotFindHost:
                return "connectionRefused"
            case .networkConnectionLost, .notConnectedToInternet:
                return "networkDisconnected"
            default:
                return "networkError"
            }
        }
        let nsError = self as NSError
        if nsError.domain == NSURLErrorDomain {
            if nsError.code == NSURLErrorTimedOut { return "timeout" }
            if nsError.code == NSURLErrorCannotConnectToHost { return "connectionRefused" }
            return "networkError"
        }
        if nsError.code == 61 { // ECONNREFUSED
            return "connectionRefused"
        }
        let desc = String(describing: self).lowercased()
        if desc.contains("timed out") || desc.contains("timeout") || desc.contains("cancelled") {
            return "timeout"
        }
        if desc.contains("connection refused") {
            return "connectionRefused"
        }
        return "inferenceError"
    }
}

extension WeeklyGoalTask.RunOutcome.Diagnostics {
    /// 기록에 남길 결과 이름. 로그의 `failure=` 값과 같은 어휘를 쓴다.
    func recordedOutcome(hasDrafts: Bool) -> String {
        switch self {
        case .generationFailed:
            return "generationFailed"
        case .parsed(let diagnostics):
            if case .decodeFailed = diagnostics { return "decodeFailed" }
            return hasDrafts ? "ok" : "parsedEmpty"
        }
    }

    /// 한 겹 더 들여다본 구체적 이유.
    /// 생성 실패는 타임아웃/연결실패 등을, 파싱/검증 실패는 noJSON/가짜ID환각/메모부족 등을 기록한다.
    var outcomeDetail: String? {
        switch self {
        case .generationFailed(let error):
            return error.detailedFailureReason
        case .parsed(let diagnostics):
            switch diagnostics {
            case .decodeFailed(_, let reason):
                return reason
            case let .decoded(modelReturned, kept, _, badID, alreadyUsed, _, tooFewIDs):
                if kept > 0 { return nil }
                if modelReturned == 0 { return "emptyList" }
                if badID > 0 { return "hallucinatedIDs" }
                if tooFewIDs > 0 { return "tooFewMemos" }
                if alreadyUsed > 0 { return "duplicateMemos" }
                return "validationFailed"
            }
        }
    }

    var parseSummary: RunRecord.ParseSummary? {
        guard case .parsed(let diagnostics) = self,
              case let .decoded(modelReturned, kept, requestedIDs, badID, alreadyUsed, overMaxMemo, tooFewIDs)
                = diagnostics else {
            return nil
        }
        return RunRecord.ParseSummary(
            modelReturned: modelReturned,
            kept: kept,
            requestedIDs: requestedIDs,
            badID: badID,
            alreadyUsed: alreadyUsed,
            overMaxMemo: overMaxMemo,
            tooFewIDs: tooFewIDs
        )
    }
}

extension AIRunLog {
    /// 모델이 하나도 못 만들어 **룰이 대신한** 실행을 남긴다.
    ///
    /// 오래도록 이 기록이 없었다. 화면에는 추천이 떴는데 AI 실험실에는 아무것도 없어서,
    /// «모델이 실패했는데 사용자는 결과를 받았다» 는 상황이 통째로 안 보였다.
    /// 그래서 룰 추천이 얼마나 자주 쓰이는지도, 사용자가 그걸 실제로 채택하는지도 잰 적이 없다.
    ///
    /// `attempt` 는 모델 시도들 **뒤에** 오도록 넉넉히 잡는다. 폴백 사슬이 길어져도
    /// 룰이 항상 마지막에 오게 하려는 것이다.
    static func recordRuleFallback(
        runID: String,
        task: String,
        candidateCount: Int,
        suggestions: [AchievementGoalSuggestion]
    ) {
        let context = RunContext(
            runID: runID,
            task: task,
            candidateCount: candidateCount,
            // 실행 전략은 모델 얘기라 룰에는 뜻이 없다.
            variant: nil,
            attemptNumber: ruleFallbackAttempt
        )
        record(
            context.record(
                startedAt: Date(),
                provider: "rule",
                model: nil,
                outcome: suggestions.isEmpty ? "parsedEmpty" : "ok",
                outcomeDetail: suggestions.isEmpty ? "emptyList" : nil,
                titles: suggestions.map(\.title),
                selectedIDs: suggestions.flatMap { $0.cadence == .monthly ? $0.childGoalIDs : $0.memoIDs },
                // 어느 룰이 만들었나. 여러 룰이 섞이면 이름을 이어 붙인다 —
                // `recipe` 는 «어떤 기법을 켠 실행인가» 를 담는 자리다.
                recipe: ruleRecipe(from: suggestions)
            )
        )
    }

    /// 룰은 모델 시도 뒤에 온다. 지금 사슬이 최대 2단(공급자 → AFM)이라 그 다음 번호다.
    private static let ruleFallbackAttempt = 3

    private static func ruleRecipe(from suggestions: [AchievementGoalSuggestion]) -> String {
        let names = Set(suggestions.compactMap(\.ruleName)).sorted()
        return names.isEmpty ? "rule" : "rule:" + names.joined(separator: "+")
    }
}
