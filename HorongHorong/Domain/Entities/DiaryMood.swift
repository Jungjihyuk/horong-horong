import Foundation

/// 일기의 기분. `DiaryEntry.moodRaw` 로 저장된다.
enum DiaryMood: String, CaseIterable, Identifiable {
    case great = "최고"
    case good = "좋음"
    case ok = "보통"
    case low = "별로"
    case bad = "나쁨"

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .great: return "😄"
        case .good: return "🙂"
        case .ok: return "😐"
        case .low: return "😕"
        case .bad: return "😞"
        }
    }
}
