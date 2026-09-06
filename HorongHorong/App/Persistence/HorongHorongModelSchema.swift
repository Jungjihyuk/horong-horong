import Foundation
import SwiftData

/// 앱이 지금 쓰는 스키마. 컨테이너를 만드는 모든 곳이 여기를 거친다.
///
/// 버전이 올라가면 이 함수가 가리키는 대상만 바꾼다 — 호출부는 손대지 않는다.
enum HorongHorongModelSchema {
    static func make() -> Schema {
        Schema(versionedSchema: HorongHorongSchemaV8.self)
    }

    /// 버전 관리 도입 전 배포본의 저장소도 현재 스키마로 끌어올린다.
    ///
    /// staged migration은 계획에 선언된 정확한 모델 해시만 시작점으로 인정한다. Diary 도입 전처럼
    /// V1과 모델 수가 다른 무버전 저장소는 Core Data가 경량 마이그레이션할 수 있어도 시작 전에
    /// `unknown model version`으로 거부한다. 현재 단계는 모두 lightweight이고 데이터 복사는 앱 시작
    /// 마이그레이션이 담당하므로, 기존 파일에 한해 SwiftData의 자동 경량 마이그레이션으로 복구한다.
    static func makeContainer(storeURL: URL) throws -> ModelContainer {
        let schema = make()
        let configuration = ModelConfiguration(schema: schema, url: storeURL)

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: HorongHorongMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            guard FileManager.default.fileExists(atPath: storeURL.path) else { throw error }
            return try ModelContainer(for: schema, configurations: [configuration])
        }
    }
}
