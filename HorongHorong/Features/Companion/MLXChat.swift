import Foundation

#if canImport(MLXLLM)
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// 앱 안에서 직접 도는 MLX 모델 보관소.
///
/// Ollama 는 모델이 남의 프로세스에 살아서 `keep_alive: 0` 한 줄로 내릴 수 있었다.
/// MLX 는 가중치가 이 앱의 메모리에 그대로 올라오므로, 올린 컨테이너를 여기 한 곳에만
/// 두고 직접 붙잡았다 놓는다. 놓을 때 MLX 가 잡아둔 버퍼 캐시까지 비워야 실제로 메모리가 준다.
actor MLXModelStore {
    static let shared = MLXModelStore()

    private var loadedModel: String?
    private var container: ModelContainer?
    /// 같은 모델을 동시에 두 번 내려받지 않도록 진행 중인 로드를 공유한다.
    private var loading: Task<ModelContainer, Error>?

    /// MLX 는 Metal GPU 백엔드로 돈다. Intel 맥에는 없다.
    static var isSupported: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    /// 내려받은 양. 비율만 주면 큰 파일 여러 개를 순서대로 받을 때 멈춘 것처럼 보여서
    /// 바이트를 그대로 넘긴다. 화면이 "3.3GB / 4.9GB" 와 속도를 직접 그린다.
    struct DownloadProgress: Sendable {
        let received: Int64
        let total: Int64
    }

    /// 이미 메모리에 올라와 있으면 그것만 돌려준다. 없으면 `nil` — **여기서는 내려받지 않는다.**
    /// 대화 도중에 수 GB 다운로드가 조용히 시작되는 걸 막는 관문이다.
    func loadedContainer(for model: String) -> ModelContainer? {
        loadedModel == model ? container : nil
    }

    /// 모델을 메모리에 올린다. 처음 쓰는 모델이면 가중치를 먼저 내려받는다.
    func container(
        for model: String,
        onProgress: @Sendable @escaping (DownloadProgress) -> Void = { _ in }
    ) async throws -> ModelContainer {
        guard Self.isSupported else { throw MLXChatError.unsupportedHardware }

        if loadedModel == model {
            if let container { return container }
            if let loading { return try await loading.value }
        } else {
            unload()
        }

        loadedModel = model
        let task = Task {
            // 레지스트리에 있는 모델은 EOS 토큰 같은 추가 설정을 함께 가져온다.
            try await #huggingFaceLoadModelContainer(
                configuration: LLMRegistry.shared.configuration(id: model),
                progressHandler: { progress in
                    onProgress(
                        DownloadProgress(
                            received: progress.completedUnitCount,
                            total: progress.totalUnitCount
                        )
                    )
                }
            )
        }
        loading = task

        do {
            let loaded = try await task.value
            loading = nil
            container = loaded
            Self.rememberPrepared(model)
            return loaded
        } catch {
            loading = nil
            loadedModel = nil
            throw error
        }
    }

    /// 한 번이라도 끝까지 준비된 적 있는 모델인지. 그렇다면 가중치가 디스크에 있다는 뜻이라
    /// 대화 중 자동으로 올려도 새로 내려받지 않는다.
    static func isKnownPrepared(_ model: String) -> Bool {
        preparedModels().contains(model)
    }

    private static func preparedModels() -> [String] {
        UserDefaults.standard.stringArray(forKey: Constants.AppStorageKey.companionMLXPreparedModels) ?? []
    }

    private static func rememberPrepared(_ model: String) {
        var models = preparedModels()
        guard !models.contains(model) else { return }
        models.append(model)
        UserDefaults.standard.set(models, forKey: Constants.AppStorageKey.companionMLXPreparedModels)
    }

    /// 받는 중인 것만 멈춘다. 이미 올라와 있는 모델은 그대로 둔다.
    ///
    /// 받다 만 가중치는 버려지지 않는다 — HuggingFace 쪽이 `.incomplete` 파일과 Range 요청으로
    /// 이어받기 때문에, 다시 시작하면 멈춘 지점부터 이어진다.
    func cancelLoading() {
        loading?.cancel()
        loading = nil
        if container == nil { loadedModel = nil }
    }

    /// 모델을 메모리에서 내린다. 컨테이너 참조를 놓기만 하면 MLX 가 잡아둔 버퍼가 남으므로
    /// 캐시까지 비운다.
    func unload() {
        loading?.cancel()
        loading = nil
        container = nil
        loadedModel = nil
        MLX.Memory.clearCache()
    }

    /// 지금 메모리에 올라와 있는 모델. 설정 화면 표시용.
    var residentModel: String? { container == nil ? nil : loadedModel }
}
#endif

enum MLXChatError: LocalizedError {
    case unsupportedHardware
    case notPrepared
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .unsupportedHardware:
            return "MLX 는 Apple Silicon 맥에서만 쓸 수 있습니다."
        case .notPrepared:
            return "모델이 아직 준비되지 않았습니다. 설정에서 먼저 내려받아 주세요."
        case .emptyResponse:
            return "MLX 모델이 빈 응답을 보냈습니다."
        }
    }
}
