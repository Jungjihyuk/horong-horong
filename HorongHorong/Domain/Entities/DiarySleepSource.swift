import Foundation

/// 수면 시간을 어디서 얻었는지. 예전 건강 앱 기록도 읽을 수 있도록 raw 값을 유지한다.
enum DiarySleepSource: String {
    case healthKit = "healthkit"
    case manual = "manual"
}
