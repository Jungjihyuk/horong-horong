import Foundation

/// 주간·월간 추천을 **동시에 돌릴지 하나씩 돌릴지**.
///
/// 기본값은 공급자가 정한다.
/// - 로컬 모델(Ollama·MLX)은 요청을 하나씩만 처리한다. 동시에 보내면 뒤엣것이 큐에서
///   기다리는데 60초 타임아웃은 **보낸 순간부터** 도므로 예산을 대기에 다 쓰고 죽는다
///   (실측 2026-08-19: 타임아웃 14건 중 11건이 이 모양)
/// - AFM 은 앱 밖에서 겹쳐 돌아 105건 중 타임아웃이 0건이었다
///
/// **다만 이 기본값은 관측에 기댄 추측이다.** 뒤집어 보고 재려고 덮어쓰기를 열어 둔다:
/// ```
/// defaults write com.horonghorong.app achievement.executionStrategy -string sequential
/// defaults delete com.horonghorong.app achievement.executionStrategy      # 기본으로 되돌리기
/// ```
/// 고른 값은 `RunRecord.variant` 에 남으므로, 같은 모델의 두 전략을 나란히 놓고 비교할 수 있다.
enum SuggestionExecutionStrategy: String {
    /// 주간·월간을 동시에 보낸다.
    case parallel
    /// 주간이 끝난 뒤 월간을 보낸다. 각자 타임아웃 예산을 온전히 쓴다.
    case sequential

    /// 설정에서 강제하지 않았으면 공급자가 정한다.
    ///
    /// - Parameter override: 알아볼 수 없는 값이면 **무시하고 기본으로 간다.** 오타 하나로
    ///   추천이 멈추면 안 된다 — 이건 개발용 손잡이지 기능 스위치가 아니다.
    static func resolved(
        provider: Constants.AchievementSuggestionProviderKind,
        override: String?
    ) -> SuggestionExecutionStrategy {
        if let override, let forced = SuggestionExecutionStrategy(rawValue: override) {
            return forced
        }
        return provider == .appleFoundation ? .parallel : .sequential
    }

    static func resolved(provider: Constants.AchievementSuggestionProviderKind) -> SuggestionExecutionStrategy {
        resolved(
            provider: provider,
            override: UserDefaults.standard.string(forKey: Constants.AppStorageKey.achievementExecutionStrategy)
        )
    }
}
