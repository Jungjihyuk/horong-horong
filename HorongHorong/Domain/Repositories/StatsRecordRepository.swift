import Foundation

/// 쌓인 활동 기록을 세고 지운다. 구현은 `Data/Repositories/` 에 있다.
///
/// **한 기간을 지우면 다섯 가지가 함께 사라진다** — 앱 사용 기록·타임라인 구간·집중 세션·
/// 주의 이벤트·하루 요약. 화면이 다섯 종류를 각각 알아야 할 이유가 없다.
@MainActor
protocol StatsRecordRepository {
    /// 이 기간에 지워질 기록이 몇 건인지. 확인 문구에 보여준다.
    ///
    /// **부르는 곳은 설정 → 통계 → 「휴가 기간 추가」 하나뿐이다.** 별도 삭제 메뉴가 아니라,
    /// 휴가로 등록할 기간에 기록이 남아 있을 때 「N건 있어요」를 띄우기 위한 것이다.
    func recordCount(start: Date, end: Date) -> Int

    /// 기간 안의 기록을 모두 지운다. 중간에 실패하면 전부 되돌린다.
    ///
    /// 휴가를 등록하면서 「기존 기록 삭제」를 고른 경우에만 불린다.
    ///
    /// 집중 세션을 지우면 그 세션이 완료로 찍어 둔 할 일도 함께 정리된다.
    func deleteRecords(start: Date, end: Date) throws

    /// 개인화 학습에 쓸 표본을 분석한다. 설정 화면이 「얼마나 모였나」를 보여준다.
    func focusPersonalization(requiredFeedbackCount: Int) -> FocusPersonalizationAnalysis?

    /// 집중 점수 표본. 분류 설정 화면이 카테고리별 분포를 보여줄 때 쓴다.
    func focusScoreSamples() -> [FocusScoreSample]

    /// 최근 `days` 일의 집중 점수 표본. 추세 카드가 쓴다.
    func focusScoreSamples(days: Int) -> [FocusScoreSample]

    /// 최근 `days` 일에 띄운 넛지 시각들. 빠른 순.
    func nudgeFiredDates(days: Int) -> [Date]

    /// 그 카테고리로 칠해 둔 세션 색을 기본값으로 되돌린다. 카테고리를 지울 때 부른다.
    /// 반환값은 되돌린 개수 — 0 이면 알릴 것이 없다.
    @discardableResult
    func resetSessionMarkerColors(for category: String) -> Int
}
