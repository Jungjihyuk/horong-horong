import Foundation

/// 앱 사용 기록을 남긴다. 구현은 `Data/Repositories/` 에 있다.
///
/// **쓰기가 잦다.** 앱을 옮길 때마다 불리므로, 저장은 자동 저장을 끈 별도 컨텍스트에서
/// 한다(구현 주석 참고).
@MainActor
protocol AppUsageRepository {
    /// 사용자가 정한 분류 규칙. 분류기가 메모리에 올려 두고 쓴다.
    func userDefinedRules() -> [AppCategoryRuleSnapshot]

    /// 옛 이름으로 저장된 «생산성 관리» 갈래를 지금 이름으로 옮긴다.
    /// 규칙·세그먼트·일일 기록 전부를 훑으므로 규칙을 읽기 직전에 한 번만 부른다.
    func migrateLegacyProductivityManagementCategory()

    /// 그날 그 앱의 사용 시간을 더하거나 뺀다.
    func applyUsageDelta(
        bundleIdentifier: String,
        appName: String,
        category: String,
        date: Date,
        deltaSeconds: Int
    )

    /// 방금 머문 구간을 타임라인에 남긴다.
    ///
    /// **바로 앞 구간이 같은 앱·같은 갈래로 끝났으면 그것을 늘린다.** 5초 폴링마다
    /// 새 구간을 만들면 타임라인이 조각으로 뒤덮인다.
    /// 반환값은 실제로 기록했는지 — 너무 짧은 구간은 버린다.
    func recordSegment(
        appName: String,
        bundleIdentifier: String,
        category: String,
        from start: Date,
        to end: Date,
        minimumSeconds: TimeInterval
    ) -> Bool

    /// 자리를 비운 구간을 기록에서 덜어낸다.
    ///
    /// 일일 사용 시간에서 빼고, 그 시간과 겹치는 타임라인 구간을 잘라내거나 지운다.
    /// 자리를 비운 것이 구간 한가운데면 앞뒤로 쪼갠다.
    func subtractIdleTime(
        appName: String,
        bundleIdentifier: String,
        category: String,
        from idleStart: Date,
        to idleEnd: Date,
        minimumSeconds: TimeInterval
    )
}

/// 분류 규칙 한 줄의 값 사본.
struct AppCategoryRuleSnapshot: Equatable, Sendable {
    let bundleIdentifier: String
    let category: String
    /// 추적에서 아예 뺄 앱.
    let isExcluded: Bool
}
