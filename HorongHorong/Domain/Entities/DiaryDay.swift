import Foundation

/// 하루치 일기.
///
/// **값 타입이다.** 저장은 `DiaryEntry`(`@Model`)가 하지만 그건 Data 계층에 남는다.
///
/// `id` 가 `day` 인 이유: **하루에 한 장**이라 날짜가 곧 신원이다. 저장 쪽 `UUID` 를
/// 그대로 쓰면 중복 행이 생겼을 때 화면이 둘을 다른 날로 취급한다.
struct DiaryDay: Identifiable, Equatable, Sendable {
    let day: Date
    let body: String
    let mood: DiaryMood?
    let stress: Int?
    let sleepHours: Double?
    let sleepSource: DiarySleepSource?

    var id: Date { day }
}
