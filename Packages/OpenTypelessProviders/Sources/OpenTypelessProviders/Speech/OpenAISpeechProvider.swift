import Foundation
import OpenTypelessDomain

/// OpenAI 兼容音频转录配置（由组合根从仓储读取后构造）。
public struct OpenAISpeechConfiguration: Sendable, Equatable {
    /// 基础地址或完整转录端点。
    public var baseURL: String
    public var modelName: String
    public var apiKey: String?
    /// 自定义请求头；不得包含 Content-Length 等客户端维护的头。
    public var customHeaders: [String: String]
    /// 默认语言提示。
    public var defaultLanguageHint: SpeechLanguageHint
    public var timeoutSeconds: TimeInterval

    public init(
        baseURL: String,
        modelName: String,
        apiKey: String? = nil,
        customHeaders: [String: String] = [:],
        defaultLanguageHint: SpeechLanguageHint = .automatic,
        timeoutSeconds: TimeInterval = 60
    ) {
        self.baseURL = baseURL
        self.modelName = modelName
        self.apiKey = apiKey
        self.customHeaders = customHeaders
        self.defaultLanguageHint = defaultLanguageHint
        self.timeoutSeconds = timeoutSeconds
    }
}

/// OpenAI 兼容 `/audio/transcriptions` multipart 适配器。
///
/// 协议细节（PROVIDER_PROTOCOLS §3）：
/// - 默认端点按基础地址拼接 `/v1/audio/transcriptions`，完整端点不重复拼接；
/// - `Authorization: Bearer <key>` 鉴权；自定义头不得覆盖客户端维护的头；
/// - 词典以 `prompt` 字段注入（限长）；
/// - 接受标准 `{ "text": "..." }` 响应；缺 text、空文字、非 JSON 为坏响应；
/// - 错误按 §10 映射为统一类别。
public struct OpenAISpeechProvider: SpeechProvider {
    /// 词典提示词最大长度（稳定截断策略：超长截断到边界）。
    public static let maxPromptLength = 800
    /// 响应体上限（字节），防止无界累积。
    public static let maxResponseBytes = 4 * 1024 * 1024

    private let configuration: OpenAISpeechConfiguration
    private let transport: HTTPTransport

    public init(configuration: OpenAISpeechConfiguration, transport: HTTPTransport) {
        self.configuration = configuration
        self.transport = transport
    }

    public var capabilities: SpeechCapabilities {
        SpeechCapabilities(
            supportsFileUpload: true,
            supportsStreaming: false,
            supportsLanguageHint: true,
            supportsVocabularyPrompt: true,
            supportsTimestamps: false
        )
    }

    public func validate() async throws -> ValidationResult {
        // 连接测试使用程序生成的 0.1 秒静音 WAV，不含任何敏感内容。
        let started = Date()
        do {
            let endpoint = try EndpointBuilder.build(
                baseURL: configuration.baseURL,
                defaultPath: "/v1/audio/transcriptions"
            )
            let wav = Self.makeSilentWAV()
            let spec = try buildRequest(
                endpoint: endpoint,
                audioData: wav,
                filename: "opentypeless-connection-test.wav",
                mimeType: "audio/wav",
                languageHint: .automatic,
                vocabularyTerms: [],
                timeoutSeconds: configuration.timeoutSeconds
            )
            let response = try await transport.perform(spec)
            _ = try parseResponse(response)
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

    public func transcribe(_ request: SpeechRequest) async throws -> SpeechResult {
        let endpoint = try EndpointBuilder.build(
            baseURL: configuration.baseURL,
            defaultPath: "/v1/audio/transcriptions"
        )
        let audioData: Data
        do {
            audioData = try Data(contentsOf: request.audioFile)
        } catch {
            throw DictationError(
                category: .audioInvalid,
                userMessage: "无法读取录音文件",
                isRetryable: false
            )
        }
        let spec = try buildRequest(
            endpoint: endpoint,
            audioData: audioData,
            filename: request.audioFile.lastPathComponent,
            mimeType: request.mimeType,
            languageHint: request.languageHint,
            vocabularyTerms: request.vocabularyTerms,
            timeoutSeconds: max(request.timeoutSeconds, configuration.timeoutSeconds)
        )
        let response = try await transport.perform(spec)
        return try parseResponse(response)
    }

    // MARK: - 请求构建（内部可见以便契约测试断言）

    /// 客户端维护的头：用户自定义头不得覆盖。
    static let reservedHeaderNames: Set<String> = [
        "content-type", "content-length", "host", "authorization",
    ]

    func buildRequest(
        endpoint: URL,
        audioData: Data,
        filename: String,
        mimeType: String,
        languageHint: SpeechLanguageHint,
        vocabularyTerms: [String],
        timeoutSeconds: TimeInterval
    ) throws -> HTTPRequestSpec {
        let boundary = "OpenTypelessBoundary-\(UUID().uuidString)"
        var fields: [String: String] = [
            "model": configuration.modelName,
            "response_format": "json",
        ]
        let hint = languageHint != .automatic ? languageHint : configuration.defaultLanguageHint
        if hint != .automatic {
            fields["language"] = hint.rawValue
        }
        let prompt = Self.makePrompt(vocabularyTerms: vocabularyTerms)
        if let prompt {
            fields["prompt"] = prompt
        }

        var body = Data()
        for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
            body.append(Self.multipartField(boundary: boundary, name: name, value: value))
        }
        body.append(Self.multipartFileHeader(
            boundary: boundary,
            name: "file",
            filename: filename,
            mimeType: mimeType
        ))
        body.append(audioData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var headers: [String: String] = [
            "Content-Type": "multipart/form-data; boundary=\(boundary)",
        ]
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
            timeoutSeconds: timeoutSeconds
        )
    }

    /// 词典提示：有限长度，稳定截断（不中途截断词语，超长时丢弃尾部词语）。
    static func makePrompt(vocabularyTerms: [String]) -> String? {
        guard !vocabularyTerms.isEmpty else { return nil }
        var result = ""
        for term in vocabularyTerms {
            let candidate = result.isEmpty ? term : "\(result)、\(term)"
            guard candidate.count <= maxPromptLength else { break }
            result = candidate
        }
        return result.isEmpty ? nil : result
    }

    // MARK: - 响应解析与错误映射

    func parseResponse(_ response: HTTPResponseSummary) throws -> SpeechResult {
        guard response.body.count <= Self.maxResponseBytes else {
            throw DictationError(
                category: .providerBadResponse,
                userMessage: "服务响应超出大小限制"
            )
        }
        guard (200 ..< 300).contains(response.statusCode) else {
            throw Self.mapHTTPError(status: response.statusCode, body: response.body)
        }
        struct TranscriptionResponse: Decodable {
            let text: String?
        }
        guard let decoded = try? JSONDecoder().decode(TranscriptionResponse.self, from: response.body) else {
            throw DictationError(
                category: .providerBadResponse,
                userMessage: "服务响应不是预期的 JSON 格式"
            )
        }
        guard let text = decoded.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DictationError(
                category: .providerBadResponse,
                userMessage: "服务未返回有效转录文字"
            )
        }
        return SpeechResult(text: text, providerRequestID: response.requestID)
    }

    /// HTTP 状态 → 统一错误类别（PROVIDER_PROTOCOLS §10）。
    static func mapHTTPError(status: Int, body _: Data) -> DictationError {
        switch status {
        case 401, 403:
            DictationError(
                category: .authenticationFailed,
                userMessage: "鉴权失败，请检查 API 密钥",
                isRetryable: false
            )
        case 429:
            DictationError(category: .rateLimited, userMessage: "服务限流，请稍后重试")
        case 400, 404, 409, 422:
            DictationError(
                category: .providerRejected,
                userMessage: "服务拒绝了请求，请检查模型名称与参数配置",
                isRetryable: false
            )
        case 500 ... 599:
            DictationError(category: .providerRejected, userMessage: "服务端错误（\(status)），请稍后重试")
        default:
            DictationError(
                category: .providerRejected,
                userMessage: "服务返回异常状态（\(status)）",
                isRetryable: false
            )
        }
    }

    // MARK: - multipart 与测试音频

    static func multipartField(boundary: String, name: String, value: String) -> Data {
        Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8)
    }

    static func multipartFileHeader(boundary: String, name: String, filename: String, mimeType: String) -> Data {
        Data(
            "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(mimeType)\r\n\r\n"
                .utf8
        )
    }

    /// 生成 0.1 秒 8kHz 单声道静音 WAV（44 字节头 + 1600 字节数据）。
    static func makeSilentWAV() -> Data {
        let sampleRate: UInt32 = 8000
        let dataSize: UInt32 = 1600
        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        header.append(contentsOf: withUnsafeBytes(of: (36 + dataSize).littleEndian, Array.init))
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian, Array.init))
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian, Array.init)) // PCM
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian, Array.init)) // mono
        header.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian, Array.init))
        header.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian, Array.init)) // byte rate
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian, Array.init)) // block align
        header.append(contentsOf: withUnsafeBytes(of: UInt16(8).littleEndian, Array.init)) // bits
        header.append(contentsOf: "data".utf8)
        header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian, Array.init))
        header.append(Data(repeating: 0x80, count: Int(dataSize))) // 8-bit PCM 静音
        return header
    }
}
