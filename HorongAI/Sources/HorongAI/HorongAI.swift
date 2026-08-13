/// 호롱호롱의 AI 커널. 앱 화면과 데이터 모델을 모른다.
///
/// 폴더는 책임 단위로 나뉜다 — Providers · Tasks · Retrieval · Routing · Guardrails · Logging · Evaluation.
/// 나눈 근거는 `docs/5. 운영/프로젝트 운영/12. 기술 문서/Architecture/horongai-folder-structure-decisions.md`.
///
/// Phase 2 S1 의 자리표시자다. 코드가 옮겨오면 지운다.
public enum HorongAI {
    public static let version = "0.1.0-dev"
}
