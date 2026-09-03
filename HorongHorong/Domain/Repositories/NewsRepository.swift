import Foundation

/// 뉴스 리포트 색인과 실행 이력을 읽는다. 구현은 `Data/Repositories/` 에 있다.
///
/// **쓰기가 없다.** 색인과 실행 기록을 만드는 것은 파이프라인(`NewsPipelineService`)이고,
/// 화면은 결과를 보기만 한다. 나중에 「리포트 지우기」가 생기면 그때 여기에 더한다.
@MainActor
protocol NewsRepository {
    /// 최근 리포트. 팝오버는 5개만 보여주므로 상한을 반드시 말하게 한다.
    func recentReports(limit: Int) throws -> [NewsReport]

    /// 최근 실행. 소모량 예측에 쓰는 표본이라 상한이 곧 «얼마나 거슬러 볼지» 다.
    func recentJobs(limit: Int) throws -> [NewsJobRun]

    /// 색인된 리포트의 식별자 목록. 보관함이 「목록이 달라졌나」를 판단할 때만 쓴다.
    func reportIdentifiers() throws -> [String]
}
