import Foundation

/// 컴패니언 대화 응답을 만드는 공급자.
/// 지금은 고정 문구만 돌려주고, 로컬 모델(Foundation Models) 공급자가 같은 자리에 들어온다.
protocol CompanionChatResponder: Sendable {
    func reply(to message: String, character: CompanionCharacter) async -> String
}

/// 모델 연결 전에 쓰는 고정 응답. 대화 UI 자체를 먼저 확인하기 위한 자리다.
struct ScriptedCompanionChatResponder: CompanionChatResponder {
    func reply(to message: String, character: CompanionCharacter) async -> String {
        try? await Task.sleep(for: .milliseconds(400))
        return "아직 로컬 모델과 연결되기 전이라 제대로 답할 수 없어요. "
            + "말은 잘 들었어요 — 곧 진짜로 대답할게요!"
    }
}
