import Foundation

/// 쌓인 활동 기록을 세고 지운다. 구현은 `Data/Repositories/` 에 있다.
///
/// **한 기간을 지우면 다섯 가지가 함께 사라진다** — 앱 사용 기록·타임라인 구간·집중 세션·
/// 주의 이벤트·하루 요약. 화면이 다섯 종류를 각각 알아야 할 이유가 없다.
@MainActor
protocol StatsRecordRepository {
    /// 이 기간에 지워질 기록이 몇 건인지. 확인 문구에 보여준다.
    func recordCount(start: Date, end: Date) -> Int

    /// 기간 안의 기록을 모두 지운다. 중간에 실패하면 전부 되돌린다.
    ///
    /// 집중 세션을 지우면 그 세션이 완료로 찍어 둔 할 일도 함께 정리된다.
    func deleteRecords(start: Date, end: Date) throws

    /// 개인화 학습에 쓸 표본을 분석한다. 설정 화면이 「얼마나 모였나」를 보여준다.
    func focusPersonalization(requiredFeedbackCount: Int) -> FocusPersonalizationAnalysis?

    /// 집중 점수 표본. 분류 설정 화면이 갈래별 분포를 보여줄 때 쓴다.
    func focusScoreSamples() -> [FocusScoreSample]

    /// 그 갈래로 칠해 둔 세션 색을 기본값으로 되돌린다. 갈래를 지울 때 부른다.
    /// 반환값은 되돌린 개수 — 0 이면 알릴 것이 없다.
    @discardableResult
    func resetSessionMarkerColors(for category: String) -> Int
}
