import Foundation

/// 한 칸에 적은 감정 한 건.
struct DiaryMoodRecord: Identifiable, Equatable, Sendable {
    let slot: DiaryMoodSlot
    let mood: DiaryMood
    let cause: DiaryCause?
    /// 1…5. **적지 않아도 된다** — 옛 기록에는 아예 없고, 감정을 고른 뒤 강도까지 묻는 것이
    /// 또 하나의 문턱이 될 수 있다. 없는 값을 «보통» 으로 채우지 않는다.
    let intensity: Int?

    var id: DiaryMoodSlot { slot }

    init(slot: DiaryMoodSlot, mood: DiaryMood, cause: DiaryCause? = nil, intensity: Int? = nil) {
        self.slot = slot
        self.mood = mood
        self.cause = cause
        self.intensity = DiaryMoodIntensity.normalized(intensity)
    }
}

/// 감정의 세기. **좋고 나쁨이 아니라 얼마나 강했는가**를 잰다.
///
/// 예전 `trendScore` 는 밝음 +3 · 화남 −2 처럼 감정에 등급을 매겼다. 그건 기록이 아니라 평가였다.
enum DiaryMoodIntensity {
    static let range = 1...5

    static func title(_ value: Int) -> String {
        switch value {
        case 1: return "아주 약함"
        case 2: return "약함"
        case 3: return "보통"
        case 4: return "강함"
        default: return "아주 강함"
        }
    }

    /// 범위를 벗어난 값은 버린다. 저장소에 남은 옛 값이나 잘못된 입력이 축을 늘리지 않게 한다.
    static func normalized(_ value: Int?) -> Int? {
        guard let value, range.contains(value) else { return nil }
        return value
    }
}
