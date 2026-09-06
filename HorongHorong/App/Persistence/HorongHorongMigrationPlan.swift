import Foundation
import SwiftData

/// 스키마 버전 사이를 잇는 계획.
///
/// 지금은 V1 하나뿐이라 옮길 단계가 없다. **뼈대를 미리 두는 것이 목적**이다 —
/// 모델 이름이나 타입을 바꾸는 시점에 가서 인프라부터 만들려 하면,
/// 이미 그 변경으로 기존 저장소를 못 읽는 상태가 되어 있다.
///
/// V2 를 추가할 때:
/// 1. `HorongHorongSchemaV2` 를 새 파일로 만든다 (V1 은 그대로 둔다)
/// 2. `schemas` 에 V2 를 더하고 `stages` 에 V1→V2 단계를 넣는다
/// 3. **실사용 저장소 복사본으로 열어 본다** — 합성 데이터로는 옛 앱이 남긴 파일을 재현할 수 없다
enum HorongHorongMigrationPlan: SchemaMigrationPlan {
    nonisolated static var schemas: [any VersionedSchema.Type] {
        [
            HorongHorongSchemaV1.self,
            HorongHorongSchemaV2.self,
            HorongHorongSchemaV3.self,
            HorongHorongSchemaV4.self,
            HorongHorongSchemaV5.self,
            HorongHorongSchemaV6.self,
            HorongHorongSchemaV7.self,
            HorongHorongSchemaV8.self,
        ]
    }

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: HorongHorongSchemaV1.self,
        toVersion: HorongHorongSchemaV2.self
    )

    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: HorongHorongSchemaV2.self,
        toVersion: HorongHorongSchemaV3.self
    )

    /// 목표에 `closedAt`·`closedReasonRaw` 를 더한다. 둘 다 Optional 이라 추론으로 충분하다.
    static let migrateV3toV4 = MigrationStage.lightweight(
        fromVersion: HorongHorongSchemaV3.self,
        toVersion: HorongHorongSchemaV4.self
    )

    /// 일기 수면에 `sleepStart`·`sleepEnd` 를 더한다. 둘 다 Optional 이라 추론으로 충분하다.
    static let migrateV4toV5 = MigrationStage.lightweight(
        fromVersion: HorongHorongSchemaV4.self,
        toVersion: HorongHorongSchemaV5.self
    )

    /// 참고 자료에 갈래·제목·주소·쪽지 색·위젯 상태를 더한다. 전부 Optional 이라 추론으로 충분하다.
    static let migrateV5toV6 = MigrationStage.lightweight(
        fromVersion: HorongHorongSchemaV5.self,
        toVersion: HorongHorongSchemaV6.self
    )

    /// 쪽지 위젯 창의 크기와 접힘 상태를 더한다. 전부 Optional 이라 추론으로 충분하다.
    static let migrateV6toV7 = MigrationStage.lightweight(
        fromVersion: HorongHorongSchemaV6.self,
        toVersion: HorongHorongSchemaV7.self
    )

    /// 쪽지 위젯의 앞뒤 순서를 더한다. Optional 이라 추론으로 충분하다.
    static let migrateV7toV8 = MigrationStage.lightweight(
        fromVersion: HorongHorongSchemaV7.self,
        toVersion: HorongHorongSchemaV8.self
    )

    nonisolated static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4, migrateV4toV5,
         migrateV5toV6, migrateV6toV7, migrateV7toV8]
    }
}
