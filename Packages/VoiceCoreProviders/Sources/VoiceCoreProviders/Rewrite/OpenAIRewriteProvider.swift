import Foundation
import VoiceCoreDomain

/// OpenAI 兼容 Chat Completions 改写配置。
public struct OpenAIRewriteConfiguration: Sendable, Equatable {
    public var baseURL: String
    public var modelName: String
    public var apiKey: String?
    public var customHeaders: [String: String]
    public var timeoutSeconds: TimeInterval

    public init(
        baseURL: String,
        modelName: String,
        apiKey: String? = nil,
        customHeaders: [String: String] = [:],
        timeoutSeconds: TimeInterval = 60
    ) {
        self.baseURL = baseURL
        self.modelName = modelName
        self.apiKey = apiKey
        self.customHeaders = customHeaders
        self.timeoutSeconds = timeoutSeconds
    }
}

/// OpenAI 兼容文字改写适配器（`POST /v1/chat/completions`）。
///
/// 首版不使用流式输出；响应解析只提取最终文本，
/// 不向领域层暴露 choices 等供应商结构。
public struct OpenAIRewriteProvider: RewriteProvider {
    public static let maxResponseBytes = 4 * 1024 * 1024

    private let configuration: OpenAIRewriteConfiguration
    private let transport: HTTPTransport

    public init(configuration: OpenAIRewriteConfiguration, transport: HTTPTransport) {
        self.configuration = configuration
        self.transport = transport
    }

    public var capabilities: RewriteCapabilities {
        RewriteCapabilities()
    }

    public func validate() async throws -> ValidationResult {
        // 连接测试使用固定无隐私短文本。
        let probe = RewriteRequest(
            originalText: "连接测试",
            recordID: UUID(),
            attemptID: UUID()
        )
        let started = Date()
        do {
            _ = try await rewrite(probe)
            return .success(latencyMs: Int64(Date().timeIntervalSince(started) * 1000))
        } catch let error as DictationError {
            return .failed(error, latencyMs: Int64(Date().timeIntervalSince(started) * 1000))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .failed(
                DictationError(category: .unknown, userMessage: "连接测试失败"),
                latencyMs: Int64(Date().timeIntervalSince(started) * 1000)
            )
        }
    }

    public func rewrite(_ request: RewriteRequest) async throws -> RewriteResult {
        guard !request.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DictationError(
                category: .configurationInvalid,
                userMessage: "原始文字为空，无法改写",
                isRetryable: false
            )
        }
        let endpoint = try EndpointBuilder.build(
            baseURL: configuration.baseURL,
            defaultPath: "/v1/chat/completions"
        )
        let spec = try buildRequest(endpoint: endpoint, request: request)
        let response = try await transport.perform(spec)
        return try parseResponse(response)
    }

    // MARK: - 请求构建

    static let reservedHeaderNames: Set<String> = [
        "content-type", "content-length", "host", "authorization"
    ]

    func buildRequest(endpoint: URL, request: RewriteRequest) throws -> HTTPRequestSpec {
        let payload = OpenAIChatRequest(
            model: configuration.modelName,
            messages: [
                OpenAIChatMessage(
                    role: "system",
                    content: RewritePromptBuilder.systemPrompt(
                        vocabularyTerms: request.vocabularyTerms,
                        userInstruction: request.userInstruction
                    )
                ),
                OpenAIChatMessage(
                    role: "user",
                    content: RewritePromptBuilder.userMessage(originalText: request.originalText)
                )
            ],
            maxTokens: request.maxOutputTokens,
            temperature: request.temperature
        )
        let body = try JSONEncoder().encode(payload)

        var headers = ["Content-Type": "application/json"]
        if let apiKey = configuration.apiKey, !apiKey.isEmpty {
            headers["Authorization"] = "Bearer \(apiKey)"
        }
        for (name, value) in configuration.customHeaders {
            guard !Self.reservedHeaderNames.contains(name.lowercased()) else { continue }
            headers[name] = value
        }
        return HTTPRequestSpec(
            method: "POST",
            url: endpoint,
            headers: headers,
            body: body,
            timeoutSeconds: max(request.timeoutSeconds, configuration.timeoutSeconds)
        )
    }

    // MARK: - 响应解析

    func parseResponse(_ response: HTTPResponseSummary) throws -> RewriteResult {
        guard response.body.count <= Self.maxResponseBytes else {
            throw DictationError(category: .providerBadResponse, userMessage: "服务响应超出大小限制")
        }
        guard (200 ..< 300).contains(response.statusCode) else {
            throw OpenAISpeechProvider.mapHTTPError(status: response.statusCode, body: response.body)
        }
        guard let decoded = try? JSONDecoder().decode(OpenAIChatResponse.self, from: response.body) else {
            throw DictationError(category: .providerBadResponse, userMessage: "服务响应不是预期的 JSON 格式")
        }
        guard let text = decoded.choices?.first?.message?.content,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw DictationError(category: .providerBadResponse, userMessage: "服务未返回有效文字")
        }
        let finishReason: RewriteFinishReason = switch decoded.choices?.first?.finishReason {
        case "stop": .completed
        case "length": .lengthLimited
        default: .unknown
        }
        return RewriteResult(
            finalText: text,
            providerRequestID: response.requestID,
            inputTokens: decoded.usage?.promptTokens,
            outputTokens: decoded.usage?.completionTokens,
            finishReason: finishReason
        )
    }
}

// MARK: - 线协议载荷

/// OpenAI Chat Completions 消息。
private struct OpenAIChatMessage: Encodable {
    let role: String
    let content: String
}

/// OpenAI Chat Completions 请求体；字段经 CodingKeys 映射为 API 的 snake_case 键。
private struct OpenAIChatRequest: Encodable {
    let model: String
    let messages: [OpenAIChatMessage]
    let maxTokens: Int
    let temperature: Double?

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
    }
}

/// OpenAI Chat Completions 响应体；仅声明所需字段，未知字段忽略。
private struct OpenAIChatResponse: Decodable {
    let choices: [OpenAIChoice]?
    let usage: OpenAIUsage?
}

/// 响应选项。
private struct OpenAIChoice: Decodable {
    let message: OpenAIChoiceMessage?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

/// 响应用量统计；字段经 CodingKeys 映射为 API 的 snake_case 键。
private struct OpenAIUsage: Decodable {
    let promptTokens: Int?
    let completionTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
    }
}

/// 响应选项中的消息体（独立声明以满足嵌套深度约束）。
private struct OpenAIChoiceMessage: Decodable {
    let content: String?
}
