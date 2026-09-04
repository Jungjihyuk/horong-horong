import Foundation
import SwiftData

/// 앱이 지금 쓰는 스키마. 컨테이너를 만드는 모든 곳이 여기를 거친다.
///
/// 버전이 올라가면 이 함수가 가리키는 대상만 바꾼다 — 호출부는 손대지 않는다.
enum HorongHorongModelSchema {
    static func make() -> Schema {
        Schema(versionedSchema: HorongHorongSchemaV4.self)
    }
}
