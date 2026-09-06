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
    /// «하루(전반)» 칸의 감정·원인·강도.
    ///
    /// 이름에 슬롯이 안 붙은 이유: 하루에 한 칸뿐이던 시절의 필드를 그대로 물려받았다.
    /// 이름을 바꾸면 SwiftData 속성명이 바뀌어 옛 기록이 통째로 비어 버린다.
    var moodRaw: String?
    var causeRaw: String?
    var dayIntensity: Int?
    var morningMoodRaw: String?
    var morningCauseRaw: String?
    var morningIntensity: Int?
    var afternoonMoodRaw: String?
    var afternoonCauseRaw: String?
    var afternoonIntensity: Int?
    /// 수면 길이. `sleepStart`/`sleepEnd` 에서 나오는 값이지만, 시각 없이 길이만 적던
    /// 옛 기록이 그래프에서 사라지지 않도록 함께 저장한다.
    var sleepHours: Double?
    /// 취침·기상 시각. 옛 기록은 둘 다 `nil` 이다.
    var sleepStart: Date?
    var sleepEnd: Date?
    /// 과거 healthkit 또는 manual. 기존 healthkit 값은 호환을 위해 읽는다.
    var sleepSourceRaw: String?
    var stress: Int?
    var body: String
    var createdAt: Date
    var updatedAt: Date

    init(day: Date, calendar: Calendar = .current) {
        self.id = UUID()
        self.day = calendar.startOfDay(for: day)
        self.moodRaw = nil
        self.causeRaw = nil
        self.dayIntensity = nil
        self.morningMoodRaw = nil
        self.morningCauseRaw = nil
        self.morningIntensity = nil
        self.afternoonMoodRaw = nil
        self.afternoonCauseRaw = nil
        self.afternoonIntensity = nil
        self.sleepHours = nil
        self.sleepStart = nil
        self.sleepEnd = nil
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
        causeRaw: String? = nil,
        dayIntensity: Int? = nil,
        morningMoodRaw: String? = nil,
        morningCauseRaw: String? = nil,
        morningIntensity: Int? = nil,
        afternoonMoodRaw: String? = nil,
        afternoonCauseRaw: String? = nil,
        afternoonIntensity: Int? = nil,
        sleepHours: Double? = nil,
        sleepStart: Date? = nil,
        sleepEnd: Date? = nil,
        sleepSourceRaw: String? = nil,
        stress: Int? = nil,
        body: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.day = day
        self.moodRaw = moodRaw
        self.causeRaw = causeRaw
        self.dayIntensity = dayIntensity
        self.morningMoodRaw = morningMoodRaw
        self.morningCauseRaw = morningCauseRaw
        self.morningIntensity = morningIntensity
        self.afternoonMoodRaw = afternoonMoodRaw
        self.afternoonCauseRaw = afternoonCauseRaw
        self.afternoonIntensity = afternoonIntensity
        self.sleepHours = sleepHours
        self.sleepStart = sleepStart
        self.sleepEnd = sleepEnd
        self.sleepSourceRaw = sleepSourceRaw
        self.stress = stress
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 슬롯 하나를 값 타입으로 읽고 쓴다. 필드 세 쌍을 고르는 일이 여기 한 곳에만 있어야
    /// 저장소·이관·테스트가 저마다 «오전은 어느 필드였지» 를 다시 풀지 않는다.
    func mood(_ slot: DiaryMoodSlot) -> DiaryMood? {
        switch slot {
        case .morning: return morningMoodRaw.flatMap(DiaryMood.init(rawValue:))
        case .afternoon: return afternoonMoodRaw.flatMap(DiaryMood.init(rawValue:))
        case .wholeDay: return moodRaw.flatMap(DiaryMood.init(rawValue:))
        }
    }

    func cause(_ slot: DiaryMoodSlot) -> DiaryCause? {
        switch slot {
        case .morning: return morningCauseRaw.flatMap(DiaryCause.init(rawValue:))
        case .afternoon: return afternoonCauseRaw.flatMap(DiaryCause.init(rawValue:))
        case .wholeDay: return causeRaw.flatMap(DiaryCause.init(rawValue:))
        }
    }

    func intensity(_ slot: DiaryMoodSlot) -> Int? {
        switch slot {
        case .morning: return morningIntensity
        case .afternoon: return afternoonIntensity
        case .wholeDay: return dayIntensity
        }
    }

    func setMood(_ mood: DiaryMood?, in slot: DiaryMoodSlot) {
        switch slot {
        case .morning: morningMoodRaw = mood?.rawValue
        case .afternoon: afternoonMoodRaw = mood?.rawValue
        case .wholeDay: moodRaw = mood?.rawValue
        }
    }

    func setCause(_ cause: DiaryCause?, in slot: DiaryMoodSlot) {
        switch slot {
        case .morning: morningCauseRaw = cause?.rawValue
        case .afternoon: afternoonCauseRaw = cause?.rawValue
        case .wholeDay: causeRaw = cause?.rawValue
        }
    }

    func setIntensity(_ intensity: Int?, in slot: DiaryMoodSlot) {
        let value = DiaryMoodIntensity.normalized(intensity)
        switch slot {
        case .morning: morningIntensity = value
        case .afternoon: afternoonIntensity = value
        case .wholeDay: dayIntensity = value
        }
    }

    /// 적힌 칸만 슬롯 순으로. 감정이 없으면 원인·강도가 남아 있어도 기록으로 치지 않는다 —
    /// «무엇 때문이었는지만 있고 무엇이었는지는 없는» 기록은 읽을 수 없다.
    var moodRecords: [DiaryMoodRecord] {
        DiaryMoodSlot.allCases.compactMap { slot in
            guard let mood = mood(slot) else { return nil }
            return DiaryMoodRecord(
                slot: slot,
                mood: mood,
                cause: cause(slot),
                intensity: intensity(slot)
            )
        }
    }

    var sleepSource: DiarySleepSource? {
        get { sleepSourceRaw.flatMap(DiarySleepSource.init(rawValue:)) }
        set { sleepSourceRaw = newValue?.rawValue }
    }
}
