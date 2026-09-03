import Foundation

/// 대화에서 받아 적은 것을 저장한다. 구현은 `Data/Repositories/` 에 있다.
///
/// **섹션을 정하지 않는다.** 내용으로 판별한다 — 링크면 References, 날짜가 있으면 Todo,
/// 나머지는 Quick Note. 컴패니언은 「어디에 넣을지」를 묻지 않고 받아 적기만 한다.
@MainActor
protocol CompanionMemoRepository {
    /// 저장하고 만들어진 기록의 식별자를 준다.
    ///
    /// `startDate` 가 없고 «오늘 할 일» 이면 지금 시각으로 잡는다.
    @discardableResult
    func createMemo(
        content: String,
        icon: String,
        startDate: Date?,
        deadline: Date?
    ) throws -> UUID
}
