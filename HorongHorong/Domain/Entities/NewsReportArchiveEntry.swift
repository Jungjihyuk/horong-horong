import Foundation

/// 보관함에 늘어놓을 리포트 한 편.
///
/// **`NewsReport`(색인)와 다른 타입인 이유**: 이쪽은 «디스크에 실제로 있는 파일» 이 근거다.
/// 색인에 없어도 파일이 있으면 보이고, 색인에 있어도 파일이 지워졌으면 안 보인다.
/// `id` 가 파일 경로인 것도 그래서다.
struct NewsReportArchiveEntry: Identifiable, Equatable {
    let id: String
    let jobId: String
    let reportDate: Date
    let reportURL: URL
    let metaURL: URL
    let topTitle: String
    let itemCount: Int
    let createdAt: Date
}
