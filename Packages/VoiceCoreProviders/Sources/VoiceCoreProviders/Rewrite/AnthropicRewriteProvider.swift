import Foundation
import VoiceCoreDomain

/// Anthropic Messages 改写配置。
public struct AnthropicRewriteConfiguration: Sendable, Equatable {
    public var baseURL: String
    public var modelName: String
    public var apiKey: String?
    /// `anthropic-version` 头；有明确默认值且可配置，不散落在业务代码中。
    public var anthropicVersion: String
    public var customHeaders: [String: String]
    public var timeoutSeconds: TimeInterval

    public static let defaultAnthropicVersion = "2023-06-01"

    public init(
        baseURL: String,
        modelName: String,
        apiKey: String? = nil,
        anthropicVersion: String = AnthropicRewriteConfiguration.defaultAnthropicVersion,
        customHeaders: [String: String] = [:],
        timeoutSeconds: TimeInterval = 60
    ) {
        self.baseURL = baseURL
        self.modelName = modelName
        self.apiKey = apiKey
        self.anthropicVersion = anthropicVersion
        self.customHeaders = customHeaders
        self.timeoutSeconds = timeoutSeconds
    }
}

/// Anthropic 兼容文字改写适配器（`POST /v1/messages`）。
///
/// 系统提示使用协议的 `system` 字段，原始转录放入用户消息；
/// 按顺序拼接文本内容块，忽略未知但合法的非文本块；
/// 完全没有文本块时返回标准坏响应错误（PROVIDER_PROTOCOLS §7）。
public struct AnthropicRewriteProvider: RewriteProvider {
    public static let maxResponseBytes = 4 * 1024 * 1024

    private let configuration: AnthropicRewriteConfiguration
    private let transport: HTTPTransport

    public init(configuration: AnthropicRewriteConfiguration, transport: HTTPTransport) {
        self.configuration = configuration
        self.transport = transport
    }

    public var capabilities: RewriteCapabilities {
        RewriteCapabilities(supportsSystemPrompt: true, supportsMaxOutputTokens: true, supportsTemperature: true)
    }

    public func validate() async throws -> ValidationResult {
        let probe = RewriteRequest(originalText: "连接测试", recordID: UUID(), attemptID: UUID())
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
            defaultPath: "/v1/messages"
        )
        let spec = try buildRequest(endpoint: endpoint, request: request)
        let response = try await transport.perform(spec)
        return try parseResponse(response)
    }

    // MARK: - 请求构建

    static let reservedHeaderNames: Set<String> = [
        "content-type", "content-length", "host", "x-api-key", "anthropic-version"
    ]

    func buildRequest(endpoint: URL, request: RewriteRequest) throws -> HTTPRequestSpec {
        let payload = AnthropicMessagesRequest(
            model: configuration.modelName,
            maxTokens: request.maxOutputTokens,
            system: RewritePromptBuilder.systemPrompt(
                vocabularyTerms: request.vocabularyTerms,
                userInstruction: request.userInstruction
            ),
            messages: [
                AnthropicMessage(
                    role: "user",
                    content: RewritePromptBuilder.userMessage(originalText: request.originalText)
                )
            ],
            temperature: request.temperature
        )
        let body = try JSONEncoder().encode(payload)

        var headers: [String: String] = [
            "Content-Type": "application/json",
            "anthropic-version": configuration.anthropicVersion
        ]
        if let apiKey = configuration.apiKey, !apiKey.isEmpty {
            headers["x-api-key"] = apiKey
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
        guard let decoded = try? JSONDecoder().decode(AnthropicMessagesResponse.self, from: response.body) else {
            throw DictationError(category: .providerBadResponse, userMessage: "服务响应不是预期的 JSON 格式")
        }
        // 按顺序拼接文本块，忽略未知但合法的非文本块。
        let text = (decoded.content ?? [])
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DictationError(category: .providerBadResponse, userMessage: "服务未返回有效文字")
        }
        let finishReason: RewriteFinishReason = switch decoded.stopReason {
        case "end_turn", "stop_sequence": .completed
        case "max_tokens": .lengthLimited
        default: .unknown
        }
        return RewriteResult(
            finalText: text,
            providerRequestID: response.requestID,
            inputTokens: decoded.usage?.inputTokens,
            outputTokens: decoded.usage?.outputTokens,
            finishReason: finishReason
        )
    }
}

// MARK: - 线协议载荷

/// Anthropic Messages 请求消息。
private struct AnthropicMessage: Encodable {
    let role: String
    let content: String
}

/// Anthropic Messages 请求体；字段经 CodingKeys 映射为 API 的 snake_case 键。
private struct AnthropicMessagesRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [AnthropicMessage]
    let temperature: Double?

    enum CodingKeys: String, CodingKey {
        case model, system, messages, temperature
        case maxTokens = "max_tokens"
    }
}

/// Anthropic Messages 响应体；仅声明所需字段，未知字段忽略。
private struct AnthropicMessagesResponse: Decodable {
    let content: [AnthropicContentBlock]?
    let stopReason: String?
    let usage: AnthropicUsage?

    enum CodingKeys: String, CodingKey {
        case content, usage
        case stopReason = "stop_reason"
    }
}

/// 响应内容块。
private struct AnthropicContentBlock: Decodable {
    let type: String
    let text: String?
}

/// 响应用量统计；字段经 CodingKeys 映射为 API 的 snake_case 键。
private struct AnthropicUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}
