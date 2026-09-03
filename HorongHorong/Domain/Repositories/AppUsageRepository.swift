import Foundation

/// 앱 사용 기록을 남긴다. 구현은 `Data/Repositories/` 에 있다.
///
/// **쓰기가 잦다.** 앱을 옮길 때마다 불리므로, 저장은 자동 저장을 끈 별도 컨텍스트에서
/// 한다(구현 주석 참고).
@MainActor
protocol AppUsageRepository {
    /// 사용자가 정한 분류 규칙. 분류기가 메모리에 올려 두고 쓴다.
    func userDefinedRules() -> [AppCategoryRuleSnapshot]

    /// 설정 화면이 보여줄 전체 규칙. 카테고리 → 앱 이름 순.
    func allRules() -> [AppCategoryRuleDetail]

    /// 아직 카테고리를 못 정한 앱들.
    func unclassifiedApps() -> [UnclassifiedAppUsage]

    /// 기본 규칙 중 빠진 것을 채워 넣는다.
    func reconcileDefaultRules()

    /// 규칙을 새로 만든다. 그 앱의 «미분류» 기록도 이 카테고리로 다시 매긴다.
    func addRule(bundleIdentifier: String, appName: String, category: String) throws

    /// 규칙의 카테고리를 바꾼다.
    ///
    /// - Parameter includeExistingUsage: 이미 쌓인 기록도 다시 매길지.
    ///   `false` 면 앞으로 기록되는 것에만 적용된다.
    ///   **사용자가 직접 고친 세션은 어느 쪽이든 건드리지 않는다.**
    func changeRuleCategory(
        bundleIdentifier: String,
        to category: String,
        replacementAppName: String?,
        includeExistingUsage: Bool
    ) throws

    /// 추적에서 뺀다.
    func excludeRule(bundleIdentifier: String, appName: String) throws

    /// 규칙을 지운다. 기본 규칙이었으면 다시 나타나지 않게 숨김 표시도 남긴다.
    func deleteRule(bundleIdentifier: String)

    /// 미분류 앱에 카테고리를 매긴다.
    func classifyUnclassified(_ app: UnclassifiedAppUsage, as category: String) throws

    /// 카테고리 이름을 바꾼다. 기록·규칙·세션에 남은 옛 이름을 전부 옮긴다.
    ///
    /// - Parameter movesBehaviorConditions: 그 카테고리에 걸린 행동 조건도 따라 옮길지.
    ///   `false` 면 조건은 지운다(카테고리를 없애는 경우).
    func renameCategory(from oldName: String, to newName: String, movesBehaviorConditions: Bool) throws

    /// 저장하지 않은 변경이 남아 있는가. 카테고리 이름 변경 전에 확인한다 —
    /// 도중에 실패하면 되돌릴 범위가 뒤섞인다.
    var hasPendingChanges: Bool { get }

    /// 옛 이름으로 저장된 «생산성 관리» 카테고리를 지금 이름으로 옮긴다.
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
    /// **바로 앞 구간이 같은 앱·같은 카테고리로 끝났으면 그것을 늘린다.** 5초 폴링마다
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

/// 설정 화면이 보여주는 규칙 한 줄.
struct AppCategoryRuleDetail: Identifiable, Equatable, Sendable {
    let bundleIdentifier: String
    let appName: String
    let category: String
    /// 사용자가 손댄 규칙. 기본값과 같아지면 다시 `false` 가 된다.
    let isUserDefined: Bool
    let isExcluded: Bool

    var id: String { bundleIdentifier }
}

/// 분류에 필요한 최소한. 분류기가 메모리에 올려 두는 형태다.
struct AppCategoryRuleSnapshot: Equatable, Sendable {
    let bundleIdentifier: String
    let category: String
    /// 추적에서 아예 뺄 앱.
    let isExcluded: Bool
}
