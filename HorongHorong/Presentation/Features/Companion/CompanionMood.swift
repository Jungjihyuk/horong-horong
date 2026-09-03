import Foundation

/// 대화에서 읽어낸 컴패니언의 감정.
///
/// 로컬 모델이 답과 함께 골라준다. 자유 텍스트로 태그를 붙이게 하면 이 크기의 모델은 자주 어기므로,
/// 구조화 출력(`@Generable`)으로 값을 강제한다. 모델 쪽 표현은 `FoundationModelsCompanionChat` 에 따로 둔다.
enum CompanionMood: String, CaseIterable, Sendable {
    case cheerful
    case playful
    case calm
    case encouraging
    case concerned

    /// 이 감정일 때 보여줄 동작.
    var animation: CompanionAnimation {
        switch self {
        case .cheerful, .playful:
            return .jumping
        case .calm:
            return .idle
        case .encouraging:
            return .waving
        case .concerned:
            return .failed
        }
    }

    /// 모델이 정의에 없는 값을 주더라도 대화가 끊기지 않게 한다.
    init?(modelValue: String) {
        self.init(rawValue: modelValue.lowercased())
    }
}

/// 대화 한 번의 결과. 감정은 스트리밍 마지막에 확정되므로 옵셔널이다.
struct CompanionChatReply: Equatable, Sendable {
    var text: String
    var mood: CompanionMood?

    static let empty = CompanionChatReply(text: "", mood: nil)
}
