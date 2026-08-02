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
                        Self.downloadProgress(
                            credited: progress.completedUnitCount,
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

    /// 화면에 그릴 진행률. 라이브러리가 주는 값은 **파일 하나가 끝나야** 오른다 —
    /// 가중치가 4GB 짜리 한 덩어리면 작은 설정 파일들이 끝난 14MB 에서 몇 분씩 멈춰 있다가
    /// 마지막에 100% 로 튄다. 받는 중인 파일 크기를 직접 재서 그 사이를 메운다.
    private static func downloadProgress(credited: Int64, total: Int64) -> DownloadProgress {
        let received = credited + inFlightDownloadBytes()
        // 이 앱의 다른 다운로드(업데이트 등)가 섞여 들어와 총량을 넘어서지 않게 막는다.
        return DownloadProgress(
            received: total > 0 ? min(received, total) : received,
            total: total
        )
    }

    /// 지금 받는 중인 바이트. URLSession 은 내려받는 동안 이 프로세스의 임시 폴더에
    /// `CFNetworkDownload_*.tmp` 로 쓰고 다 받으면 캐시로 옮기므로, **방금 손댄** 임시 파일들의
    /// 크기 합이 곧 진행 중인 양이다. 시각으로 거르지 않으면 예전에 받다 만 찌꺼기까지 세게 된다.
    private static func inFlightDownloadBytes() -> Int64 {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        let cutoff = Date().addingTimeInterval(-5)
        return files.reduce(Int64(0)) { total, file in
            guard file.lastPathComponent.hasPrefix("CFNetworkDownload_") else { return total }
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            guard let modified = values?.contentModificationDate, modified > cutoff,
                  let size = values?.fileSize else { return total }
            return total + Int64(size)
        }
    }

    /// 한 번이라도 끝까지 준비된 적 있는 모델인지. 그렇다면 가중치가 디스크에 있다는 뜻이라
    /// 대화 중 자동으로 올려도 새로 내려받지 않는다.
    ///
    /// 기준은 언제나 디스크다. UserDefaults 기록은 캐시를 뒤지는 수고를 아끼는 힌트일 뿐이라,
    /// 파일이 사라졌는데 기록만 남아 있으면 그 기록을 걷어낸다. 기록을 그대로 믿으면
    /// «받음» 으로 보이는 모델이 실제로는 없어서, 답할 때가 되어서야 조용히 몇 GB 를 다시 받게 된다.
    static func isKnownPrepared(_ model: String) -> Bool {
        if hasCachedWeights(model) { return true }
        forgetPrepared(model)
        return false
    }

    /// HuggingFace 캐시 위치. 사용자가 환경변수로 옮겨 둔 경우까지 따라간다.
    private static var cacheRoot: URL {
        let environment = ProcessInfo.processInfo.environment
        if let hubCache = environment["HF_HUB_CACHE"], !hubCache.isEmpty {
            return URL(fileURLWithPath: hubCache)
        }
        if let home = environment["HF_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home).appendingPathComponent("hub")
        }
        return FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
    }

    /// 이 모델의 가중치가 담긴 캐시 폴더.
    static func cacheDirectory(for model: String) -> URL {
        cacheRoot.appendingPathComponent("models--" + model.replacingOccurrences(of: "/", with: "--"))
    }

    /// HuggingFace 캐시에 실제 가중치(.safetensors)가 있는지 본다.
    /// 설정 파일만 있고 가중치가 없는 "받다 만" 상태를 준비됨으로 오해하지 않기 위해 확장자까지 확인한다.
    private static func hasCachedWeights(_ model: String) -> Bool {
        let snapshots = cacheDirectory(for: model).appendingPathComponent("snapshots")
        guard let revisions = try? FileManager.default.contentsOfDirectory(
            at: snapshots, includingPropertiesForKeys: nil
        ) else { return false }
        return revisions.contains { revision in
            let files = (try? FileManager.default.contentsOfDirectory(atPath: revision.path)) ?? []
            return files.contains { $0.hasSuffix(".safetensors") }
        }
    }

    /// 받아 둔 가중치가 차지하는 크기. 지우기 전에 얼마나 비는지 보여주는 데 쓴다.
    ///
    /// `snapshots` 는 `blobs` 를 가리키는 심볼릭 링크라 따라가면 같은 파일을 두 번 센다. 실체인 `blobs` 만 잰다.
    static func cachedWeightsSize(for model: String) -> Int64? {
        let blobs = cacheDirectory(for: model).appendingPathComponent("blobs")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: blobs, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return nil }
        let total = files.reduce(Int64(0)) { partial, file in
            partial + Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total > 0 ? total : nil
    }

    /// 받아 둔 가중치를 지운다. 메모리에 올라와 있으면 먼저 내린다 —
    /// 쓰고 있는 파일을 밑에서 걷어내면 다음 응답이 어떻게 될지 알 수 없다.
    func removeCachedWeights(for model: String) throws {
        if loadedModel == model { unload() }
        let directory = Self.cacheDirectory(for: model)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        Self.forgetPrepared(model)
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

    private static func forgetPrepared(_ model: String) {
        var models = preparedModels()
        guard let index = models.firstIndex(of: model) else { return }
        models.remove(at: index)
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
