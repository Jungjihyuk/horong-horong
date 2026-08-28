import Foundation
import HorongAI
import HorongAIMLX

/// 목표 추천이 끝난 뒤 **유예 시간 안에 다음 요청이 없으면** 모델을 메모리에서 내린다.
///
/// 추천은 버튼을 누를 때만 도는데 가중치는 그 뒤로도 남는다. MLX 는 이 앱의 메모리를 그대로
/// 차지하고, Ollama 는 남의 프로세스에 살더라도 **서버 설정에 따라 몇 시간씩** 붙잡는다
/// (실측 2026-08-19: 올린 직후 만료가 18시간 뒤였다). 유휴 타임아웃에 기댈 수 없는 이유다.
///
/// 곧바로 내리지 않는 이유는 연달아 다시 누르는 일이 잦아서다. 다시 올리는 데 몇 초에서
/// 수십 초가 드니 짧은 유예를 두는 편이 낫다.
///
/// 공급자를 **바꿀 때** 내리는 일은 설정 화면(`SettingsRoot` 의 `AchievementPage`)이 맡는다.
/// 여기는 «안 쓰면 내린다», 저기는 «떠나면 내린다» 로 계기가 다르다.
actor SuggestionModelUnloader {
    static let shared = SuggestionModelUnloader()

    /// 마지막 추천이 끝난 뒤 모델을 남겨 둘 시간.
    static let idleGrace: Duration = .seconds(30)

    private var pending: Task<Void, Never>?

    /// 이번 실행이 **실제로 쓰는** 대상.
    private var target: Target?

    private struct Target {
        let provider: Constants.AchievementSuggestionProviderKind
        let model: String
        let endpoint: String
    }

    /// 추천이 시작됐다. 예약된 언로드를 취소하고, 이번에 쓸 대상을 붙잡아 둔다.
    ///
    /// 취소가 필요한 이유는 **지금 쓰려는 모델을 밑에서 걷어내면 안 되기** 때문이다.
    ///
    /// 대상을 여기서 붙잡는 이유는 따로 있다. 끝날 때 설정을 읽으면 **그사이 사용자가 바꾼 값**을
    /// 보게 된다 — Ollama 로 돌리는 중에 MLX 로 바꾸면, 정작 올라간 Ollama 모델은 대상에서
    /// 빠지고 올라가지도 않은 MLX 를 내리려 든다.
    func beginRun() {
        pending?.cancel()
        pending = nil
        let provider = AchievementFoundationGoalSuggestionProvider.selectedProvider
        target = Target(
            provider: provider,
            model: Self.selectedModel(for: provider),
            endpoint: Self.ollamaEndpoint
        )
    }

    /// 주간·월간이 **모두** 끝났다. 유예 시간 뒤에 내린다.
    /// 그 사이에 다시 추천이 시작되면 `beginRun()` 이 취소한다.
    ///
    /// 추천이 실패해 Apple 모델로 내려갔더라도 그 전에 가중치는 이미 올라갔을 수 있으므로
    /// 시작할 때 붙잡아 둔 대상을 그대로 내린다.
    func endRun() {
        pending?.cancel()
        guard let target else { return }
        pending = Task {
            try? await Task.sleep(for: Self.idleGrace)
            guard !Task.isCancelled else { return }
            await Self.unload(target)
        }
    }

    private static func selectedModel(
        for provider: Constants.AchievementSuggestionProviderKind
    ) -> String {
        switch provider {
        case .ollama:
            return UserDefaults.standard.string(forKey: Constants.AppStorageKey.achievementSuggestionOllamaModel)
                ?? Constants.defaultAchievementSuggestionOllamaModel
        case .mlx:
            return UserDefaults.standard.string(forKey: Constants.AppStorageKey.achievementSuggestionMLXModel)
                ?? Constants.defaultAchievementSuggestionMLXModel
        case .appleFoundation:
            return ""
        }
    }

    private static var ollamaEndpoint: String {
        let stored = UserDefaults.standard.string(forKey: Constants.NewsStorageKey.ollamaEndpoint) ?? ""
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Constants.defaultNewsOllamaEndpoint : trimmed
    }

    private static func unload(_ target: Target) async {
        switch target.provider {
        case .ollama:
            guard !target.model.isEmpty else { return }
            // 추론 중에 보내도 안전하다. 실측(2026-08-19): 진행 중인 요청은 끝까지 가고,
            // 끝나는 즉시 내려갔다.
            await OllamaChatClient.unload(endpoint: target.endpoint, model: target.model)
            achievementSuggestionLog.info("suggestion model unloaded=ollama idle=30s")
        case .mlx:
            #if canImport(MLXLLM)
            await MLXModelStore.shared.unload()
            achievementSuggestionLog.info("suggestion model unloaded=mlx idle=30s")
            #endif
        case .appleFoundation:
            // 시스템이 들고 있다. 앱이 내릴 수 있는 것이 없다.
            break
        }
    }
}
