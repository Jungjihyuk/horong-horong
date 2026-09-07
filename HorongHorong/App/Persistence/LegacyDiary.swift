import Foundation
import SwiftData

/// V3~V4 가 **디스크에 남긴** `Diary` 의 모양. 얼려 둔 사본이다.
///
/// ⚠️ **이 파일은 고치지 않는다.**
///
/// `LegacyAchievementGoalRecord.swift` 가 적어 둔 것과 같은 이유다 — `HorongHorongSchemaV3`·`V4`
/// 가 살아 있는 `Diary` 를 가리키면, 그 타입에 필드를 더하는 순간 **선언된 모든 버전의 모양이
/// 함께 바뀐다.** 새 버전을 하나 더 만들어도 옛 버전과 checksum 이 같아져
/// `Duplicate version checksums detected` 로 저장소 열기가 통째로 거부된다.
///
/// 그래서 옛 버전은 그때의 모양을 가리켜야 한다. 엔티티가 이어지도록 타입 이름은 `Diary` 로
/// 두고 이름공간만 다르게 둔다.
///
/// 여기 없는 것: `causeRaw`, `sleepStart`, `sleepEnd`. 셋 다 V5 에서 더해졌다.
enum LegacyDiarySchema {
    @Model
    final class Diary {
        var id: UUID
        /// 그날의 시작 시각. 하루 한 장.
        var day: Date
        var moodRaw: String?
        var sleepHours: Double?
        /// healthkit 또는 manual. nil 이면 아직 수면 출처가 없다.
        var sleepSourceRaw: String?
        var stress: Int?
        var body: String
        var createdAt: Date
        var updatedAt: Date

        init(
            id: UUID = UUID(),
            day: Date,
            moodRaw: String? = nil,
            sleepHours: Double? = nil,
            sleepSourceRaw: String? = nil,
            stress: Int? = nil,
            body: String = "",
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.day = day
            self.moodRaw = moodRaw
            self.sleepHours = sleepHours
            self.sleepSourceRaw = sleepSourceRaw
            self.stress = stress
            self.body = body
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }
}
