import Foundation

/// 이 공급자가 감당할 수 있는 한계.
///
/// 지금은 `Constants.achievementPromptCharacterBudget(for: .mlx)` 처럼 **태스크 쪽이 공급자 종류를
/// 알고 분기한다.** 그러면 새 AI 를 추가할 때 `Providers/` 밖도 고쳐야 한다. 한계는 공급자만 아는
/// 것이므로 계약으로 흘러나와야 한다.
///
/// AFM 은 약 4k 에서 추론이 거부되고 MLX 는 훨씬 넓다 — 그 차이가 이 값이다.
public struct ProviderCapabilities: Sendable, Equatable {
    /// 프롬프트에 넣을 수 있는 문자 수 상한.
    public let maxPromptCharacters: Int

    public init(maxPromptCharacters: Int) {
        self.maxPromptCharacters = maxPromptCharacters
    }
}

/// 어느 AI 에게 물을 것인가. 공급자가 늘어도 이 약속은 바뀌지 않는다.
///
/// 새 AI 를 추가할 때 `Providers/` 밖의 파일을 고쳐야 한다면 이 계약이 부족한 것이다.
@MainActor
public protocol LLMProvider {
    /// 설정값·기록에 쓰는 안정된 식별자 (`"ollama"` · `"mlx"` · `"appleFoundation"`).
    var id: String { get }
    /// 설정 화면에 보여줄 이름.
    var displayName: String { get }
    /// 지금 이 기기에서 실제로 답을 만들 수 있는지.
    ///
    /// 물어봐야 아는 것(서버가 떠 있나, 모델을 받았나)은 아직 이 계약에 없다.
    /// 지금은 호출하는 쪽이 미리 확인해 넣어 준다(`make(ollamaReachable:)`).
    /// 그 로직을 옮길 때 비동기 확인을 계약에 넣는다.
    var isAvailable: Bool { get }
    var capabilities: ProviderCapabilities { get }

    func makeSession(_ setup: SessionSetup) -> LLMSession
}
