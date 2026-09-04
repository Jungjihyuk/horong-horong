import Foundation

/// 목표와 그에 묶인 할일을 읽고 쓴다. 구현은 `Data/Repositories/` 에 있다.
///
/// **경계를 넘는 것은 값 타입뿐이다** — `AchievementGoalRecord`·`Memo`(`@Model`)는
/// 이 프로토콜에 등장하지 않는다.
///
/// 진행률·색·묶인 할일을 채운 `AchievementGoal` 은 여기서 만들지 않는다. 그건 `Color` 를
/// 들고 있어 표현 계층의 타입이고, `AchievementDataBuilder` 가 이 값들로 조립한다.
@MainActor
protocol AchievementRepository {
    /// 저장된 목표 전부. 최근에 고친 순.
    func goals() -> [AchievementGoalDetail]

    /// 살아 있는 할일 전부(보관·최근 삭제 제외).
    func memos() -> [AchievementMemoDetail]

    /// 목표에 묶을 수 있는 할일 — Todo 섹션이면서 아직 안 끝낸 것.
    func linkableMemos() -> [AchievementMemoDetail]

    // MARK: - 목표 쓰기

    /// 목표를 만든다. 하위 목표를 이어붙이고, 제목만 적어둔 하위 목표는 여기서 실제로 만든다.
    @discardableResult
    func createGoal(
        _ draft: AchievementGoalDraft,
        childGoalIDs: Set<UUID>,
        newChildTitles: [String]
    ) throws -> AchievementGoalDetail

    /// 달성 시각을 찍는다. 이미 찍힌 것은 건드리지 않는다.
    ///
    /// **달성은 사건이지 상태가 아니다.** 달성 여부는 «묶인 할일이 다 끝났나» 로 계산되는데
    /// 그 값은 나중에 바뀐다(할일을 더 묶으면 풀린다). 몇 달 뒤에 같은 질문을 해도 같은
    /// 답이 나오려면 처음 참이 된 순간을 찍어 둬야 한다.
    func markCompleted(ids: [UUID], at date: Date)

    /// 못 이룬 채로 닫는다. 이미 닫혔거나 이미 이룬 목표는 건드리지 않는다.
    ///
    /// `markCompleted` 와 같은 규약이다 — **닫힘도 사건이라 한 번만 찍힌다.** 이 가드가
    /// 없으면 성취 창과 팝오버가 같은 틱에 정산할 때 패널티가 두 번 붙는다.
    func markFailed(ids: [UUID], at date: Date, reason: AchievementCloseReason)

    /// 닫은 것을 되돌려 다시 연다. 「되돌리기」가 쓴다.
    func reopen(ids: [UUID])

    /// 마감을 미룬다. 「이어서 도전」이 쓰며, 닫혀 있었다면 함께 다시 연다.
    func extendDueDate(id: UUID, to date: Date)

    func updateGoal(id: UUID, with edit: AchievementGoalEditDraft)
    func deleteGoal(id: UUID)

    /// 자식을 부모에서 뗀다. 자식 목표 자체는 남는다.
    func detachChild(id: UUID, fromParentID: UUID)

    /// 역할·비전을 만들거나 고친다.
    func savePersonaVision(_ draft: AchievementPersonaVisionDraft) throws

    // MARK: - 할일 쓰기

    /// 완료를 뒤집는다. 저장에 실패하면 건드린 값을 되돌리고 던진다.
    /// 반환값은 뒤집은 뒤의 완료 상태다.
    @discardableResult
    func toggleMemoCompletion(id: UUID) throws -> Bool

    /// 타임라인에서 다른 요일로 옮긴다. 시각은 유지한다.
    func moveMemo(id: UUID, to day: Date) throws

    /// 기한 지난 할일들을 주어진 날짜들에 돌아가며 배치한다.
    func rescheduleMemos(ids: [UUID], targetDays: [Date]) throws

    /// 미리알림에 연동된 것만 골라 그쪽에도 반영한다. 반환값은 **실패한 개수**다.
    ///
    /// 화면이 「N개는 동기화하지 못했습니다」를 만들 수 있게 개수만 준다 —
    /// 문구를 여기서 만들면 표현이 Data 계층에 눌러앉는다.
    func syncLinkedReminders(ids: [UUID]) async -> Int

    /// 미리알림에 연동된 할일이 하나라도 있는지. 동기화 안내를 띄울지 정할 때 쓴다.
    func hasLinkedReminders(ids: [UUID]) -> Bool
}
