import Foundation
import SwiftData

/// 일기(Diary) 영속 모델.
///
/// SQLite 테이블: `ZDIARY`
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

    init(day: Date, calendar: Calendar = .current) {
        self.id = UUID()
        self.day = calendar.startOfDay(for: day)
        self.moodRaw = nil
        self.sleepHours = nil
        self.sleepSourceRaw = nil
        self.stress = nil
        self.body = ""
        self.createdAt = Date()
        self.updatedAt = Date()
    }

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

    var mood: DiaryMood? {
        get { moodRaw.flatMap(DiaryMood.init(rawValue:)) }
        set { moodRaw = newValue?.rawValue }
    }

    var sleepSource: DiarySleepSource? {
        get { sleepSourceRaw.flatMap(DiarySleepSource.init(rawValue:)) }
        set { sleepSourceRaw = newValue?.rawValue }
    }
}
