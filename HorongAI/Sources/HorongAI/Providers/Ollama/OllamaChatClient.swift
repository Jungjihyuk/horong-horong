import Foundation

/// Ollama 서버와 대화만 주고받는 최소 클라이언트.
///
/// 모델 설치·목록 조회는 뉴스 기능(`NewsPipelineService`)에 이미 있고 CLI 배관에 묶여 있어 그대로 둔다.
/// 여기서는 대화에 필요한 `/api/chat` 스트리밍과 서버 확인만 다룬다.
public struct OllamaChatClient: Sendable {
    public let endpoint: String
    public let model: String

    public init(endpoint: String, model: String) {
        self.endpoint = endpoint
        self.model = model
    }

    public struct Message: Codable, Sendable {
        public let role: String
        public let content: String

        public init(role: String, content: String) {
            self.role = role
            self.content = content
        }
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
        let stream: Bool
        /// qwen3 계열은 기본이 추론 모드라 생각하는 데 토큰을 다 쓰고 빈 답을 준다.
        let think: Bool
        let options: Options

        struct Options: Encodable {
            let temperature: Double
            let num_predict: Int
            let repeat_penalty: Double?
            let presence_penalty: Double?
            let frequency_penalty: Double?
        }
    }

    public struct Usage: Sendable, Equatable {
        public let promptTokens: Int?
        public let completionTokens: Int?

        public init(promptTokens: Int? = nil, completionTokens: Int? = nil) {
            self.promptTokens = promptTokens
            self.completionTokens = completionTokens
        }
    }

    public struct StreamUpdate: Sendable {
        public let text: String
        public let usage: Usage?
        public let isDone: Bool

        public init(text: String, usage: Usage? = nil, isDone: Bool = false) {
            self.text = text
            self.usage = usage
            self.isDone = isDone
        }
    }

    /// 스트리밍 응답 한 줄. 완료되면 `done` 이 true 다.
    private struct ChatChunk: Decodable {
        let message: Message?
        let done: Bool?
        let promptEvalCount: Int?
        let evalCount: Int?

        enum CodingKeys: String, CodingKey {
            case message
            case done
            case promptEvalCount = "prompt_eval_count"
            case evalCount = "eval_count"
        }
    }

    /// 서버가 떠 있는지. 꺼져 있으면 Apple 모델로 돌아가야 한다.
    public static func isReachable(endpoint: String) async -> Bool {
        guard let url = url(endpoint: endpoint, path: "/api/tags") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            return false
        }
        return (200..<300).contains(http.statusCode)
    }

    private struct UnloadRequest: Encodable {
        let model: String
        let keep_alive: Int
    }

    /// 모델을 메모리에서 즉시 내린다. `keep_alive: 0` 을 실어 보내면
    /// Ollama 가 유휴 타임아웃(기본 5분)을 기다리지 않고 바로 언로드한다.
    public static func unload(endpoint: String, model: String) async {
        guard let url = url(endpoint: endpoint, path: "/api/generate") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(UnloadRequest(model: model, keep_alive: 0))
        _ = try? await URLSession.shared.data(for: request)
    }

    private struct PreloadRequest: Encodable {
        let model: String
    }

    /// 모델을 미리 메모리에 올려둔다. `prompt` 없이 요청하면 텍스트를 만들지 않고 가중치만 로드한다.
    public static func preload(endpoint: String, model: String) async {
        guard let url = url(endpoint: endpoint, path: "/api/generate") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(PreloadRequest(model: model))
        _ = try? await URLSession.shared.data(for: request)
    }

    /// 말이 만들어지는 대로 누적 텍스트와 완료 시의 토큰 사용량(Usage)을 흘려보낸다.
    public func streamUpdates(
        messages: [Message],
        temperature: Double,
        maxTokens: Int,
        repeatPenalty: Double? = nil,
        presencePenalty: Double? = nil,
        frequencyPenalty: Double? = nil
    ) -> AsyncThrowingStream<StreamUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = Self.url(endpoint: endpoint, path: "/api/chat") else {
                        throw OllamaChatError.invalidEndpoint(endpoint)
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(
                        ChatRequest(
                            model: model,
                            messages: messages,
                            stream: true,
                            think: false,
                            options: .init(
                                temperature: temperature,
                                num_predict: maxTokens,
                                repeat_penalty: repeatPenalty,
                                presence_penalty: presencePenalty,
                                frequency_penalty: frequencyPenalty
                            )
                        )
                    )

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse,
                          (200..<300).contains(http.statusCode) else {
                        throw OllamaChatError.serverUnavailable
                    }

                    // 응답은 줄마다 하나의 JSON(NDJSON) 이다.
                    var accumulated = ""
                    var lastUsage: Usage? = nil
                    for try await line in bytes.lines {
                        guard !line.isEmpty,
                              let data = line.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(ChatChunk.self, from: data) else {
                            continue
                        }
                        if let piece = chunk.message?.content, !piece.isEmpty {
                            accumulated += piece
                            continuation.yield(StreamUpdate(text: accumulated, isDone: false))
                        }
                        if chunk.promptEvalCount != nil || chunk.evalCount != nil {
                            lastUsage = Usage(
                                promptTokens: chunk.promptEvalCount,
                                completionTokens: chunk.evalCount
                            )
                        }
                        if chunk.done == true {
                            continuation.yield(StreamUpdate(text: accumulated, usage: lastUsage, isDone: true))
                            break
                        }
                    }

                    guard !accumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw OllamaChatError.emptyResponse
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 말이 만들어지는 대로 누적 텍스트를 흘려보낸다.
    ///
    /// 콜백 대신 스트림을 돌려준다. 콜백은 백그라운드에서 불려 액터 경계를 넘어야 하는데,
    /// 스트림이면 받는 쪽이 자기 액터에서 그대로 소비할 수 있다.
    public func stream(
        messages: [Message],
        temperature: Double,
        maxTokens: Int,
        repeatPenalty: Double? = nil,
        presencePenalty: Double? = nil,
        frequencyPenalty: Double? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var lastYielded = ""
                    for try await update in self.streamUpdates(
                        messages: messages,
                        temperature: temperature,
                        maxTokens: maxTokens,
                        repeatPenalty: repeatPenalty,
                        presencePenalty: presencePenalty,
                        frequencyPenalty: frequencyPenalty
                    ) {
                        if update.text != lastYielded {
                            lastYielded = update.text
                            continuation.yield(update.text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public static func url(endpoint: String, path: String) -> URL? {
        let normalized = endpoint
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !normalized.isEmpty else { return nil }
        return URL(string: normalized + path)
    }
}

public enum OllamaChatError: LocalizedError {
    case invalidEndpoint(String)
    case serverUnavailable
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint(let endpoint):
            return "Ollama 주소가 올바르지 않습니다: \(endpoint)"
        case .serverUnavailable:
            return "Ollama 서버에 연결할 수 없습니다."
        case .emptyResponse:
            return "Ollama 가 빈 응답을 보냈습니다."
        }
    }
}
