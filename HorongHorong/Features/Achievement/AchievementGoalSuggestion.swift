import AppKit
import HorongAI
import HorongAIMLX
import OSLog
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if canImport(FoundationModels)
import FoundationModels
#endif

/*
 목표 추천의 입력·출력 값 타입.
 
  추천을 만드는 규칙은 `AchievementGoalSuggestionBuilder`, 모델 호출은 각 공급자 타입에 있다.

 원래 `AchievementViews.swift`(9,854줄) 한 파일에 있었다. 2026-09-03 분할.
 */

enum AchievementGoalSuggestionSource: String, Sendable {
    case rule = "룰 기반"
    case foundationModel = "Apple 모델"
    case mlx = "MLX"
    case ollama = "Ollama"
}

let achievementSuggestionLog = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "HorongHorong",
    category: "goal-suggestion"
)

/// 모델 추천이 후보를 내지 못한 이유. 전부 빈 배열로 끝나므로 구분해 두지 않으면 원인을 알 수 없다.
enum AchievementSuggestionModelFailure: String, Sendable {
    case modelUnavailable
    case inferenceFailed
    case parsedEmpty
}

/// 추론 실패 원인을 로그에 남길 문자열.
/// 릴리스에서는 타입 이름만 남겨 프롬프트 내용이 새지 않게 하고, 디버그에서는 전문을 남긴다.
func achievementModelErrorDescription(_ error: Error) -> String {
    #if DEBUG
    return String(describing: error)
    #else
    return String(describing: type(of: error))
    #endif
}

/// AFM이 한 번에 받아들이는 프롬프트 상한. 이 이상은 추론 자체가 거부된다.
/// 측정값: 3,424자 통과 / 5,203자 실패. 실패 하한과 1,200자 여유를 둔 값이다.
/// 이 중 약 1,671자는 지시문 템플릿이 고정으로 쓰므로 메모에 남는 공간은 그만큼 적다.
let achievementPromptCharacterBudget = Constants.achievementPromptCharacterBudget(for: .appleFoundation)

/// 월간 응답의 토큰 상한.
///
/// 900 이던 시절 실측(2026-08-20)에서 응답이 2,000자를 넘겨 잘렸다 — 최근 20건 중 2건이
/// `decodeFailed/truncated` 였고 **둘 다 월간**이었다. 모델이 `reason`·`scheduleText` 를
/// 프롬프트 예시(18자)보다 네 배씩 길게 쓴다.
///
/// 주간은 `scheduleText`·`criterion` 을 응답에서 받지 않아 훨씬 짧고 잘린 적이 없다.
/// 그래서 **월간만** 올린다 — 상한을 올리면 실패했을 때 그만큼 더 오래 기다린다.
let achievementMonthlyMaxTokens = 1_800

/// 필터 단계에서 후보가 탈락한 이유
enum AchievementSuggestionRejection {
    case shortTitle
    case toolNameTitle
    case insufficientIDs
}

/// `mergeSuggestions` 한 번의 단계별 탈락/통과 개수. 어디서 후보를 잃는지 추적한다.
struct AchievementSuggestionFilterStats {
    var shortTitle = 0
    var toolNameTitle = 0
    var insufficientIDs = 0
    var dismissed = 0
    var duplicate = 0
    /// 필터를 통과했지만 `displayLimit` 정원을 넘어 잘린 수. 탈락이 아니라 정원 컷이므로 분리한다.
    var overflow = 0
    var shown = 0

    var summary: String {
        "short=\(shortTitle) tool=\(toolNameTitle) singleID=\(insufficientIDs)"
            + " dismissed=\(dismissed) dup=\(duplicate) overflow=\(overflow) shown=\(shown)"
    }
}

/// 추천 후보의 목표 타입. 주간 목표 초안인지 월간 목표 초안인지를 구분한다.
/// 모델이 정하는 값이 아니라 응답을 파싱하는 코드가 직접 붙인다.
enum AchievementGoalCadence: String, Sendable {
    case weekly = "주간목표"
    case monthly = "월간목표"

    /// 저장 모델 `AchievementGoalRecord.cadence`에 들어가는 값
    var levelName: String {
        switch self {
        case .weekly: return "주간"
        case .monthly: return "월간"
        }
    }

    var periodText: String {
        switch self {
        case .weekly: return "이번 주"
        case .monthly: return "이번 달"
        }
    }
}

struct AchievementMemoSnapshot: Identifiable, Hashable, Sendable {
    let id: UUID
    let content: String
    let icon: String?
    let date: Date
    let startDate: Date?
    let deadline: Date?
    let isCompleted: Bool
}

struct AchievementGoalSnapshot: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let emoji: String
    let rule: String
    let done: Int
    let total: Int
    let sourceMemoIDs: [UUID]
    let roleName: String
    let vision: String
    let monthGoal: String?
}

struct AchievementGoalSuggestion: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let reason: String
    let memoIDs: [UUID]
    let childGoalIDs: [UUID]
    let scheduleText: String
    let criterion: String
    let targetValueText: String
    let emoji: String
    /// 목표 타입 (주간 목표 / 월간 목표)
    let cadence: AchievementGoalCadence
    let source: AchievementGoalSuggestionSource
    /// 룰 기반이면 **어느 룰**이 만들었나(`context` · `keyword` · `fallback`). 모델 결과는 `nil`.
    ///
    /// 룰 폴백은 오래도록 기록에 한 줄도 안 남았다 — 화면에는 뜨는데 AI 실험실에는 없었다.
    /// 어느 룰이 얼마나 쓰이는지 재려면 이름이 필요하다.
    let ruleName: String?
    /// 이 카드를 만든 **추천 실행**. 사용자가 채택하면 목표에 그대로 옮겨 심는다.
    ///
    /// 카드가 자기 출처를 모르면 «이 목표가 어느 추천에서 왔나» 를 이을 수 없고,
    /// 그러면 채택률을 낼 수 없다(→ 평가 문서 [4]).
    let runID: String?

    init(
        id: UUID = UUID(),
        title: String,
        reason: String,
        memoIDs: [UUID],
        childGoalIDs: [UUID] = [],
        scheduleText: String,
        criterion: String,
        targetValueText: String,
        emoji: String,
        cadence: AchievementGoalCadence = .weekly,
        source: AchievementGoalSuggestionSource,
        ruleName: String? = nil,
        runID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.reason = reason
        self.memoIDs = Array(Set(memoIDs))
        self.childGoalIDs = Array(Set(childGoalIDs))
        self.scheduleText = scheduleText
        self.criterion = criterion
        self.targetValueText = targetValueText
        self.emoji = emoji
        self.cadence = cadence
        self.source = source
        self.ruleName = ruleName
        self.runID = runID
    }

    /// 파서를 AFM 경로와 공유하므로 MLX 결과도 `.foundationModel` 로 붙는다.
    /// 폴백 비율 집계가 어긋나지 않도록 실제 공급자로 다시 태깅한다.
    func retagged(as source: AchievementGoalSuggestionSource) -> AchievementGoalSuggestion {
        AchievementGoalSuggestion(
            id: id,
            title: title,
            reason: reason,
            memoIDs: memoIDs,
            childGoalIDs: childGoalIDs,
            scheduleText: scheduleText,
            criterion: criterion,
            targetValueText: targetValueText,
            emoji: emoji,
            cadence: cadence,
            source: source,
            ruleName: ruleName,
            runID: runID
        )
    }
}

/// 화면·실험실·골든셋 실행기가 함께 소비하는 추천 결과.
///
/// 빈 배열만 반환하면 `guidance`와 모델 실패가 구분되지 않아, 안내를 규칙 기반 추천으로
/// 덮어쓰게 된다. 공급자 경계에서 이 타입을 끝까지 유지한다.
enum AchievementGoalRecommendationResult: Sendable {
    case suggestions([AchievementGoalSuggestion])
    case guidance([GoalRecommendationGuidance])
    case noSuggestion
    /// 공급자·전송·파싱 실패. `noSuggestion`과 달리 다음 공급자로 내려갈 수 있다.
    case failure(reason: String?)

    var suggestions: [AchievementGoalSuggestion] {
        guard case .suggestions(let suggestions) = self else { return [] }
        return suggestions
    }

    var guidance: [GoalRecommendationGuidance] {
        guard case .guidance(let guidance) = self else { return [] }
        return guidance
    }

    /// 폴백을 멈춰야 하는 유효한 모델 결과인가.
    var hasModelResult: Bool {
        switch self {
        case .suggestions(let suggestions): return !suggestions.isEmpty
        case .guidance(let guidance): return !guidance.isEmpty
        case .noSuggestion, .failure(_): return false
        }
    }

    var shouldFallbackToNextProvider: Bool {
        if case .failure(_) = self { return true }
        return false
    }

    /// `guidance`와 `noSuggestion`은 모델이 정상적으로 내린 결론이다. 실행 실패처럼
    /// 기록하면 AI 실험실의 실패율과 골든셋 결과가 왜곡된다.
    var recordedOutcome: String {
        switch self {
        case .suggestions(let suggestions): return suggestions.isEmpty ? "noSuggestion" : "ok"
        case .guidance: return "guidance"
        case .noSuggestion: return "noSuggestion"
        case .failure(let reason):
            if reason == "modelUnavailable" || reason == "serverUnavailable" { return reason! }
            if reason == "noJSON" || reason == "malformed" { return "decodeFailed" }
            return "generationFailed"
        }
    }

    /// 생성 자체가 시작되지 못했거나 실패했을 때의 구체적 이유.
    /// 골든셋은 이 값을 `outcome_detail`로 남겨, 0점과 인프라 실패를 구분한다.
    var outcomeDetail: String? {
        guard case let .failure(reason) = self else { return nil }
        return reason
    }

    static func from(
        _ result: GoalRecommendationResult,
        cadence: AchievementGoalCadence,
        source: AchievementGoalSuggestionSource,
        runID: String
    ) -> AchievementGoalRecommendationResult {
        switch result {
        case .suggestions(let drafts):
            return .suggestions(
                drafts.map { $0.suggestion(cadence: cadence, runID: runID).retagged(as: source) }
            )
        case .guidance(let guidance):
            return .guidance(guidance)
        case .noSuggestion:
            return .noSuggestion
        }
    }
}
