import Foundation

/// 마감 정산이 **처음 켜진 순간**을 기억한다.
///
/// 왜 필요한가 — 마감일을 안 넣은 주간 목표의 암묵적 마감은 «만든 주의 끝» 이다. 그래서 이
/// 기능을 켜는 순간, 여태 이월돼 있던 못 끝낸 목표가 **한꺼번에** 유예 만료 상태가 된다.
/// 그대로 두면 사용자는 고를 틈도 없이 목표 여러 개를 잃고 잔액이 0 으로 쓸려나간다.
///
/// 이 시각보다 **앞서 마감된 목표는 자동으로 닫지 않는다.** 배너에는 그대로 올라오므로
/// 사용자가 직접 실패로 마감하거나 접으면 된다 — 그때는 사용자가 고른 것이라 벌해도 된다.
enum AchievementSettlementEpoch {
    /// 저장된 시작선. 아직 없으면 `now` 를 찍고 그 값을 돌려준다.
    ///
    /// **처음 읽는 순간에 찍는다.** 설치 시각이나 빌드 날짜를 쓰면 이 기능을 못 본 채로
    /// 지나간 기간까지 정산 대상이 된다.
    static func resolve(now: Date = Date(), defaults: UserDefaults = .standard) -> Date {
        let key = Constants.AppStorageKey.achievementSettlementEpoch
        let stored = defaults.double(forKey: key)
        guard stored > 0 else {
            defaults.set(now.timeIntervalSince1970, forKey: key)
            return now
        }
        return Date(timeIntervalSince1970: stored)
    }
}
