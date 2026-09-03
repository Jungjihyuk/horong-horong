import XCTest
@testable import 호롱호롱

/// 저장 키 이름이 두 번 바뀌었다: `secondBrain.*` → `personalRecord.*` → `mind.*`.
/// 그냥 바꾸면 사용자가 고른 vault 경로가 기본값으로 돌아가고,
/// 남의 컴퓨터에는 없는 경로를 가리켜 "vault를 찾지 못했습니다" 가 뜬다.
@MainActor
final class MindDefaultsMigrationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "mind-migration-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private var current: String { Constants.AppStorageKey.mindVaultPath }
    private var previous: String { Constants.AppStorageKey.legacyMindVaultPathKeys[0] }   // personalRecord.*
    private var oldest: String { Constants.AppStorageKey.legacyMindVaultPathKeys[1] }     // secondBrain.*

    /// 바로 직전 버전에서 올라온 경우.
    func testMigratesFromPreviousName() {
        defaults.set("/Users/someone/A", forKey: previous)

        AppDelegate.migrateMindDefaults(in: defaults)

        XCTAssertEqual(defaults.string(forKey: current), "/Users/someone/A")
    }

    /// **건너뛰어 올라온 경우.** `secondBrain` 시절 앱을 쓰다 최신으로 바로 올라오면
    /// 중간 키(`personalRecord.*`)에는 값이 없다. 체인으로 거슬러 찾아야 한다.
    func testMigratesFromOldestNameWhenIntermediateIsMissing() {
        defaults.set("/Users/someone/B", forKey: oldest)

        AppDelegate.migrateMindDefaults(in: defaults)

        XCTAssertEqual(defaults.string(forKey: current), "/Users/someone/B")
    }

    /// 둘 다 있으면 **최근 것**을 쓴다. 사용자가 나중에 고친 값이 이기도록.
    func testPrefersMostRecentLegacyValue() {
        defaults.set("/Users/someone/old", forKey: oldest)
        defaults.set("/Users/someone/new", forKey: previous)

        AppDelegate.migrateMindDefaults(in: defaults)

        XCTAssertEqual(defaults.string(forKey: current), "/Users/someone/new")
    }

    /// 옛 키를 지우지 않는다 — 이전 버전으로 되돌렸을 때 설정이 남아 있어야 한다.
    func testLegacyKeysAreKept() {
        defaults.set("/Users/someone/A", forKey: previous)

        AppDelegate.migrateMindDefaults(in: defaults)

        XCTAssertEqual(defaults.string(forKey: previous), "/Users/someone/A")
    }

    /// 매 실행 도는 코드라, 두 번째 실행이 사용자가 나중에 바꾼 값을 되돌리면 안 된다.
    func testExistingCurrentValueIsNotOverwritten() {
        defaults.set("/Users/someone/legacy", forKey: previous)
        defaults.set("/Users/someone/chosen", forKey: current)

        AppDelegate.migrateMindDefaults(in: defaults)

        XCTAssertEqual(defaults.string(forKey: current), "/Users/someone/chosen")
    }

    func testNothingToMigrateIsHarmless() {
        AppDelegate.migrateMindDefaults(in: defaults)

        XCTAssertNil(defaults.string(forKey: current))
        XCTAssertNil(defaults.string(forKey: Constants.AppStorageKey.mindSection))
    }

    /// 섹션 키도 같은 체인을 탄다.
    func testSectionKeyUsesSameChain() {
        defaults.set("diary", forKey: Constants.AppStorageKey.legacyMindSectionKeys[1])

        AppDelegate.migrateMindDefaults(in: defaults)

        XCTAssertEqual(defaults.string(forKey: Constants.AppStorageKey.mindSection), "diary")
    }
}
