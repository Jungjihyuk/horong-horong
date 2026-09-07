import Foundation

/// 그날의 감정에 영향을 준 원인. `DiaryEntry.causeRaw` 로 저장된다.
enum DiaryCause: String, CaseIterable, Identifiable, Sendable {
    case work = "일"
    case study = "공부"
    case partner = "연인"
    case friend = "친구"
    case family = "가족"
    case health = "건강"
    case money = "돈"
    case future = "미래"
    case selfCause = "나 자신"
    case unknown = "잘 모르겠어요"

    var id: String { rawValue }
}
