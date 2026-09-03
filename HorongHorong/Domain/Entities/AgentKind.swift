import Foundation

/// 실험 프롬프트를 넘길 외부 CLI Agent.
///
/// **실제 명령어(`codex`·`claude` …)는 여기 없다.** 그건 Data 쪽 `CLIAgentAdapter` 가 안다 —
/// Agent 를 하나 더 지원하는 일과 「어느 Agent 를 골랐나」는 서로 다른 관심사다.
///
/// `rawValue` 가 화면에 보이는 이름이자 `AppStorage` 에 저장된 값이다.
enum AgentKind: String, CaseIterable, Identifiable, Sendable {
    case codex = "Codex"
    case claude = "Claude"
    case antigravity = "Antigravity"
    case opencode = "Opencode"
    case hermes = "Hermes"

    var id: String { rawValue }
}
