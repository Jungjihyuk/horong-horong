import Foundation

/// 컴패니언이 메모에서 읽고 쓰는 데이터를 다룬다. 구현은 `Data/Repositories/` 에 있다.
///
/// **섹션을 정하지 않는다.** 내용으로 판별한다 — 링크면 References, 날짜가 있으면 Todo,
/// 나머지는 Quick Note. 컴패니언은 「어디에 넣을지」를 묻지 않고 받아 적기만 한다.
@MainActor
protocol CompanionRepository {
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

    /// 온보딩을 자동으로 시작할지 판단하는 데 필요한 저장 건수.
    func onboardingCounts() -> CompanionOnboardingCounts

    /// 브리핑과 할 일 질문에 쓰는, 삭제되지 않은 메모의 최소 정보.
    func briefingMemos() -> [CompanionMemoSummary]
}

struct CompanionOnboardingCounts: Equatable, Sendable {
    let memoCount: Int
    let focusSessionCount: Int
    let achievementGoalCount: Int
}

struct CompanionMemoSummary: Equatable, Sendable {
    let title: String
    let isCompleted: Bool
    let startDate: Date?
    let deadline: Date?
}
