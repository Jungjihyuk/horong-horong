import SwiftUI

/// 설정에 저장된 수면 축을 읽어 값으로 건네는 얇은 껍데기.
///
/// Domain 의 `DiarySleepAxis` 는 `UserDefaults` 를 모른다(R9). 저장소를 아는 일은 화면 쪽인
/// 여기 한 곳에만 두고, 아래로는 값만 흘려보낸다.
struct DiarySleepAxisStorage {
    @AppStorage(Constants.AppStorageKey.diarySleepAxisStartHour)
    private var startHour = DiarySleepAxis.default.startHour
    @AppStorage(Constants.AppStorageKey.diarySleepAxisEndHour)
    private var endHour = DiarySleepAxis.default.endHour
    @AppStorage(Constants.AppStorageKey.diarySleepAxisTickInterval)
    private var tickInterval = DiarySleepAxis.default.tickInterval

    var axis: DiarySleepAxis {
        DiarySleepAxis(startHour: startHour, endHour: endHour, tickInterval: tickInterval)
    }
}

@MainActor
enum DiarySleepAxisText {
    /// "21시" — 설정 메뉴와 축 라벨이 같은 표기를 쓴다.
    static func hour(_ value: Int) -> String { "\(value)시" }

    static func interval(_ hours: Int) -> String { "\(hours)시간마다" }

    /// "전날 21시 → 당일 12시 · 15시간"
    static func summary(_ axis: DiarySleepAxis) -> String {
        let prefix = axis.startHour >= axis.endHour ? "전날 " : ""
        return "\(prefix)\(hour(axis.startHour)) → 당일 \(hour(axis.endHour)) · \(Int(axis.hours))시간"
    }
}
