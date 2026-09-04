import Foundation

enum RewardRedeemError: Error, Equatable {
    /// 이 월간 목표로 이미 보상을 골랐다.
    case alreadyRedeemed
    /// 아직 달성하지 않은 목표.
    case goalNotComplete
    /// 잔액이 모자란다. 얼마나 모자라는지 담는다.
    case insufficientBalance(shortBy: Int)

    var message: String {
        switch self {
        case .alreadyRedeemed:
            return "이 목표의 보상은 이미 받았어요."
        case .goalNotComplete:
            return "아직 달성하지 않은 목표예요."
        case .insufficientBalance(let shortBy):
            return "\(shortBy)P가 더 필요해요."
        }
    }
}

enum RewardRevokeError: Error, Equatable {
    /// 이 목표로 받은 적이 없다.
    case notClaimed
    /// 이미 그 포인트로 보상을 받아 되돌릴 수 없다.
    case alreadySpent(shortBy: Int)

    var message: String {
        switch self {
        case .notClaimed:
            return "이 목표로 받은 포인트가 없어요."
        case .alreadySpent(let shortBy):
            return "이미 이 포인트로 보상을 받아서 되돌릴 수 없어요. (\(shortBy)P 모자람)"
        }
    }
}

/// 원장을 읽고 쓰는 자리. 계산은 전부 `RewardLedger`에 맡기고 여기서는 저장만 다룬다.

/// 포인트 원장과 보상 목록을 읽고 쓴다. 구현은 `Data/Repositories/` 에 있다.
///
/// **잔액을 따로 저장하지 않는다.** 원장 합계가 잔액이다 — 캐시를 두면 원장과 어긋날
/// 여지만 생기고, 건수가 주당 몇 개 수준이라 합계 비용이 없다.
///
/// 적립·사용에 «이미 받았는지» 검사가 들어 있는 이유: 버튼이 안 보이는 상태에서도
/// 불릴 수 있어서 저장 직전에 한 번 더 막는다.
@MainActor
protocol RewardRepository {
    func entries() -> [RewardEntry]
    func catalogItems() -> [RewardItem]
    func balance() -> Int
    func hasClaimed(goalID: UUID) -> Bool
    func hasRedeemed(goalID: UUID) -> Bool
    /// 이 목표로 이미 패널티를 받았는지. **목표 하나당 차감도 평생 한 번이다.**
    func hasPenalized(goalID: UUID) -> Bool

    /// 주간 목표 달성 포인트를 적립한다. 미완료거나 이미 받은 목표면 아무것도 하지 않는다.
    @discardableResult
    func claim(_ goal: RewardClaimableGoal, policy: RewardPointPolicy) -> Int?

    /// 적립을 되돌린다. 할 일을 잘못 체크해 목표가 잠깐 달성 상태가 됐을 때 쓴다.
    func revokeClaim(goalID: UUID) -> Result<Int, RewardRevokeError>

    /// 실패로 마감한 목표의 포인트를 깎는다. 깎을 게 없으면 `nil`.
    ///
    /// **잔액은 0 에서 바닥이다** — 명목만큼 다 못 깎으면 깎은 만큼만 적고 그 사정을 `note` 에 남긴다.
    /// 이미 적립했거나 이미 깎은 목표는 건드리지 않는다.
    @discardableResult
    func penalize(goalID: UUID, nominalPoints: Int, note: String, at date: Date) -> RewardPenaltyResult?

    /// 패널티를 되돌린다. 돌려준 포인트를 반환하고, 깎인 적이 없으면 `nil`.
    @discardableResult
    func revokePenalty(goalID: UUID) -> Int?

    /// 월간 목표 달성 보상을 고른다. 잔액에서 항목 가격만큼 뺀다.
    func redeem(itemID: UUID, forMonthlyGoal goal: RewardClaimableGoal) -> Result<RewardEntry, RewardRedeemError>

    @discardableResult
    func addCatalogItem(title: String, emoji: String, costPoints: Int, note: String) -> RewardItem
    func updateCatalogItem(id: UUID, title: String, emoji: String, costPoints: Int, note: String)
    /// 보상 항목을 지운다. 이미 쓴 이력은 `note` 스냅샷으로 남으므로 원장은 건드리지 않는다.
    func deleteCatalogItem(id: UUID)
}
