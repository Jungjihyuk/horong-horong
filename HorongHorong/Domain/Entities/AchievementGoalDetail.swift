import Foundation

/// 저장된 목표 한 건의 값 사본.
///
/// **`AchievementGoal` 과 다르다.** 그쪽은 진행률·색·묶인 할일까지 계산해 넣은 «화면이 볼
/// 모습»이고, 이쪽은 «저장된 그대로»다. 편집 화면은 저장된 값을 고쳐야 하므로 이걸 본다.
struct AchievementGoalDetail: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let emoji: String
    let cadence: String
    let rule: String
    let targetCount: Int
    let targetValueText: String?
    let periodText: String?
    let dueDate: Date?
    let rewardText: String
    let colorHex: String
    let roleName: String
    let vision: String
    let yearGoal: String?
    let quarterGoal: String?
    let monthGoal: String?
    let linkedMemoIDs: [UUID]
    let createdAt: Date
    let updatedAt: Date
    /// 달성한 **순간**. 아직이면 `nil`.
    let completedAt: Date?
    /// 못 이룬 채 **닫힌 순간**. 아직 열려 있으면 `nil`. `completedAt` 과 짝이다.
    let closedAt: Date?
    /// 왜 닫혔나. 패널티를 줄지 가른다.
    let closedReason: AchievementCloseReason?
}

/// 목표를 새로 만들 때 넘기는 값.
///
/// `AchievementGoalDetail` 과 나눈 이유: 만들기 전에는 `id`·`createdAt` 이 없다.
/// 그 둘을 옵셔널로 둔 한 타입을 쓰면 「지금 만드는 중인가」를 매번 되물어야 한다.
struct AchievementGoalDraft: Equatable, Sendable {
    var title: String
    var emoji: String
    var cadence: String
    var rule: String
    var targetCount: Int
    var targetValueText: String?
    var periodText: String?
    var dueDate: Date?
    var colorHex: String
    var roleName: String
    var vision: String
    var yearGoal: String?
    var monthGoal: String?
    var linkedMemoIDs: [UUID]
    /// 어느 추천 실행에서 왔나. 직접 만들었으면 `nil`.
    ///
    /// 이게 없으면 «AI 추천을 채택한 목표» 와 «직접 만든 목표» 를 가릴 수 없어
    /// 채택률·달성률을 낼 수 없다. **적용한 순간에만 알 수 있어 소급이 불가능하다.**
    var sourceRunID: String?
    var sourceSuggestionID: UUID?
}

/// 목표에 묶을 수 있는 할일 한 건의 값 사본.
struct AchievementMemoDetail: Identifiable, Equatable, Sendable {
    let id: UUID
    let content: String
    let icon: String?
    let startDate: Date?
    let deadline: Date?
    let updatedAt: Date
    let isCompleted: Bool

    /// 이 할일이 «언제 것» 인가. 마감이 있으면 마감, 없으면 시작, 둘 다 없으면 마지막 수정.
    var date: Date { deadline ?? startDate ?? updatedAt }
}
