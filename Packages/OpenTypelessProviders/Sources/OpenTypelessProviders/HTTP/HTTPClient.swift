import Foundation
import OpenTypelessDomain

// HTTP 客户端基础：统一超时、取消、响应校验与敏感信息脱敏。
//
// 生产会话不使用全局 `URLSession.shared`；每个适配器持有注入的会话。
// 日志只记录阶段、耗时、状态码和请求标识，不记录密钥、鉴权头、
// 完整音频或文字内容。

/// HTTP 请求描述（适配器内部构建，测试可直接断言）。
public struct HTTPRequestSpec: Sendable, Equatable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?
    /// 请求超时（秒）。
    public var timeoutSeconds: TimeInterval

    public init(
        method: String,
        url: URL,
        headers: [String: String] = [:],
        body: Data? = nil,
        timeoutSeconds: TimeInterval = 60
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeoutSeconds = timeoutSeconds
    }
}

/// HTTP 响应摘要。
public struct HTTPResponseSummary: Sendable, Equatable {
    public var statusCode: Int
    public var body: Data
    /// 供应商请求标识（从响应头提取，可能为空）。
    public var requestID: String?

    public init(statusCode: Int, body: Data, requestID: String? = nil) {
        self.statusCode = statusCode
        self.body = body
        self.requestID = requestID
    }
}

/// 底层 HTTP 传输协议；测试用 URLProtocol 或替身注入。
public protocol HTTPTransport: Sendable {
    func perform(_ request: HTTPRequestSpec) async throws -> HTTPResponseSummary
}

/// URLSession 传输实现。
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession) {
        self.session = session
    }

    public func perform(_ spec: HTTPRequestSpec) async throws -> HTTPResponseSummary {
        var request = URLRequest(url: spec.url)
        request.httpMethod = spec.method
        request.timeoutInterval = spec.timeoutSeconds
        for (name, value) in spec.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let body = spec.body {
            request.httpBody = body
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw DictationError(
                    category: .providerBadResponse,
                    userMessage: "服务响应格式异常"
                )
            }
            let requestID = http.value(forHTTPHeaderField: "x-request-id")
                ?? http.value(forHTTPHeaderField: "X-Request-Id")
            return HTTPResponseSummary(statusCode: http.statusCode, body: data, requestID: requestID)
        } catch let error as URLError {
            throw Self.mapURLError(error)
        }
    }

    /// URLError → 标准化错误（不携带 URL 中的敏感参数）。
    public static func mapURLError(_ error: URLError) -> DictationError {
        switch error.code {
        case .cancelled:
            DictationError(
                category: .unknown,
                userMessage: "请求已取消",
                isRetryable: false
            )
        case .timedOut:
            DictationError(category: .providerTimeout, userMessage: "服务响应超时，请稍后重试")
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            DictationError(category: .networkUnavailable, userMessage: "网络不可用，请检查网络连接")
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            DictationError(
                category: .networkUnavailable,
                userMessage: "无法连接到服务地址，请检查基础地址配置"
            )
        case .secureConnectionFailed, .serverCertificateUntrusted, .appTransportSecurityRequiresSecureConnection:
            DictationError(
                category: .networkUnavailable,
                userMessage: "安全连接失败，请确认服务地址使用有效的 HTTPS"
            )
        default:
            DictationError(category: .networkUnavailable, userMessage: "网络请求失败，请稍后重试")
        }
    }
}

/// 端点拼接工具。
public enum EndpointBuilder {
    /// 按基础地址拼接默认路径；用户填写完整端点时不得重复拼接。
    /// 处理末尾斜杠（PROVIDER_PROTOCOLS §3.1）。
    /// - Parameters:
    ///   - baseURL: 用户配置的基础地址或完整端点。
    ///   - defaultPath: 默认路径，例如 `/v1/audio/transcriptions`。
    public static func build(baseURL: String, defaultPath: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DictationError(
                category: .configurationInvalid,
                userMessage: "基础地址不能为空",
                isRetryable: false
            )
        }
        // 已包含默认路径视为完整端点，直接解析。
        let normalizedPath = defaultPath.hasPrefix("/") ? defaultPath : "/" + defaultPath
        if trimmed.contains(normalizedPath) {
            guard let url = URL(string: trimmed) else {
                throw invalidURL(trimmed)
            }
            return url
        }
        let withoutTrailingSlash = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        guard let url = URL(string: withoutTrailingSlash + normalizedPath) else {
            throw invalidURL(trimmed)
        }
        return url
    }

    private static func invalidURL(_: String) -> DictationError {
        DictationError(
            category: .configurationInvalid,
            userMessage: "基础地址格式无效",
            isRetryable: false
        )
    }
}

/// 敏感信息脱敏工具。
public enum LogRedactor {
    /// 脱敏文本中的 Bearer 密钥与常见鉴权头值。
    public static func redact(_ text: String) -> String {
        var result = text
        // Bearer <token>
        result = result.replacingOccurrences(
            of: #"(?i)bearer\s+[A-Za-z0-9._\-]+"#,
            with: "Bearer •••",
            options: .regularExpression
        )
        // sk-xxx / xoxb-xxx 等常见密钥形态
        result = result.replacingOccurrences(
            of: #"[A-Za-z]{2,4}-[A-Za-z0-9]{8,}"#,
            with: "•••",
            options: .regularExpression
        )
        return result
    }

    /// 脱敏请求头字典（Authorization、x-api-key 等敏感头值替换为 •••）。
    public static func redactedHeaders(_ headers: [String: String]) -> [String: String] {
        let sensitiveNames: Set = [
            "authorization", "x-api-key", "api-key", "proxy-authorization", "x-auth-token"
        ]
        var result: [String: String] = [:]
        for (key, value) in headers {
            result[key] = sensitiveNames.contains(key.lowercased()) ? "•••" : value
        }
        return result
    }
}
