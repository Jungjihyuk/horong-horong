import Foundation

/// 수면 시간을 어디서 얻었는지. `DiaryEntry.sleepSourceRaw` 로 저장된다.
enum DiarySleepSource: String {
    case healthKit = "healthkit"
    case manual = "manual"
}
