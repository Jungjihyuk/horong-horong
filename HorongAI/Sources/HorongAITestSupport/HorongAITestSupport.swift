/// 제품에 포함되지 않는 테스트 지원. 패키지 테스트와 앱 테스트가 **함께** 쓴다.
///
/// Phase 2 S6 에서 `ScriptedCompanionChatProvider` 의 평가용 절반이 `ReplayProvider` 로 옮겨온다.
/// (제품 폴백 절반은 `HorongAI/Providers/Fallback/` 으로 간다 — 사용자가 보는 안내 문구다.)
public enum HorongAITestSupport {}
