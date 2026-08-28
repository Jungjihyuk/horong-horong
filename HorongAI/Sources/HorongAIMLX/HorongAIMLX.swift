/// MLX 공급자만 사는 자리. 소스를 내려받아 컴파일하는 의존(mlx-swift-lm)이 붙는 유일한 타깃이다.
///
/// 코어(`HorongAI`)는 이 타깃을 모른다. 앱이 시작할 때 `ProviderRegistry` 에 등록해 꽂는다.
/// Phase 2 S3 에서 MLXChat.swift 가 옮겨온다.
public enum HorongAIMLX {}
