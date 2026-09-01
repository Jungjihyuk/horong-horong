import XCTest
@testable import 호롱호롱

/// 기능 이름을 «기록(PersonalRecord)» 으로 바꾸면서 저장 키도 `secondBrain.*` →
/// `personalRecord.*` 로 옮겼다. 그냥 바꾸면 사용자가 고른 vault 경로가 사라진다.
/// `AppDelegate` 가 `@MainActor` 라 그 정적 메서드도 격리돼 있다.
@MainActor
final class PersonalRecordDefaultsMigrationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "personal-record-migration-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private var legacyPath: String { Constants.AppStorageKey.legacySecondBrainVaultPath }
    private var currentPath: String { Constants.AppStorageKey.personalRecordVaultPath }
    private var legacySection: String { Constants.AppStorageKey.legacySecondBrainSection }
    private var currentSection: String { Constants.AppStorageKey.personalRecordSection }

    func testLegacyValuesMoveToNewKeys() {
        defaults.set("/Users/someone/MY_BRAIN", forKey: legacyPath)
        defaults.set("diary", forKey: legacySection)

        AppDelegate.migratePersonalRecordDefaults(in: defaults)

        XCTAssertEqual(defaults.string(forKey: currentPath), "/Users/someone/MY_BRAIN")
        XCTAssertEqual(defaults.string(forKey: currentSection), "diary")
    }

    /// 옛 키를 지우지 않는다 — 이전 버전으로 되돌렸을 때 설정이 남아 있어야 한다.
    func testLegacyKeysAreKept() {
        defaults.set("/Users/someone/MY_BRAIN", forKey: legacyPath)

        AppDelegate.migratePersonalRecordDefaults(in: defaults)

        XCTAssertEqual(defaults.string(forKey: legacyPath), "/Users/someone/MY_BRAIN")
    }

    /// 이미 새 키에 값이 있으면 덮어쓰지 않는다. 실행할 때마다 도는 코드라
    /// 두 번째 실행이 사용자가 나중에 바꾼 값을 옛 값으로 되돌리면 안 된다.
    func testExistingNewValueIsNotOverwritten() {
        defaults.set("/old", forKey: legacyPath)
        defaults.set("/new", forKey: currentPath)

        AppDelegate.migratePersonalRecordDefaults(in: defaults)

        XCTAssertEqual(defaults.string(forKey: currentPath), "/new")
    }

    func testNothingToMigrateIsHarmless() {
        AppDelegate.migratePersonalRecordDefaults(in: defaults)

        XCTAssertNil(defaults.string(forKey: currentPath))
        XCTAssertNil(defaults.string(forKey: currentSection))
    }
}
