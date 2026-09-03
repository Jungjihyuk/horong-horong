import Foundation

/// 통계 상세 창(Stats Detail Window) 및 몰입 상세(Focus Detail)에 필요한 데이터를 읽고 쓴다.
/// 구현은 `Data/Repositories/SwiftDataStatsDetailRepository.swift` 에 있다.
@MainActor
protocol StatsDetailRepository {
    /// 주어진 기간과 선택 일자에 필요한 모든 통계 데이터를 한 번에 가져온다.
    func loadDetailSnapshot(
        mode: StatsViewMode,
        startDate: Date,
        endDate: Date,
        selectedDate: Date
    ) -> StatsDetailSnapshot

    /// 넛지와 몰입 흐름 카드를 새로고침한다.
    func refreshFocusCards(
        mode: StatsViewMode,
        selectedDate: Date
    ) -> (nudge: FocusNudgeSnapshot?, trend: HistoricalFocusTrendSnapshot?)

    /// 휴가 변경이나 편집창 닫힘 시 집계 캐시 무효화
    func invalidateAggregateCaches(containing date: Date)
    func invalidateAllAggregateCaches()

    /// 세션 마커 색상 변경
    func updateSessionMarkerColor(sessionID: UUID, colorKey: String?) throws

    /// 포모도로 세션에 연결된 할 일(Memo) 수정 또는 해제
    func updateTaskLink(sessionID: UUID, memoID: UUID?) throws

    /// 회고 수정 및 할 일 완료 상태 동기화
    func updatePomodoroReflection(
        focusSessionID: UUID,
        focusExperience: PomodoroFocusExperience,
        progressResult: PomodoroProgressResult,
        incompleteReason: PomodoroIncompleteReason?
    ) throws

    /// 회고 삭제 및 완료 상태 롤백
    func deletePomodoroReflection(focusSessionID: UUID) throws

    /// 세션에 연결된 활성 메모가 존재하는지 여부
    func hasLinkedMemo(id: UUID) -> Bool
}
