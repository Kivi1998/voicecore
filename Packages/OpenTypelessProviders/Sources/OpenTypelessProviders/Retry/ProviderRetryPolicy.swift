import Foundation
import OpenTypelessDomain

/// 提供商调用的自动重试策略（STT-003）。
///
/// 规则：
/// - 仅对瞬态故障自动重试：网络不可用、提供商超时、服务端错误
///   （`providerRejected`）；限流（429）只重试一次；
/// - 认证失败、配置错误、请求被拒绝（4xx 非限流）、响应格式错误
///   与用户取消绝不自动重试；
/// - `CancellationError` 直接向上传播，不触发任何重试；
/// - 退避为指数递增（0.5s 起，倍增，封顶 4s），延迟可注入便于测试。
///
/// 用户级「重新转录/重新改写」不受本策略限制（由历史页面显式发起）。
public struct ProviderRetryPolicy: Sendable {
    /// 最大总尝试次数（含首次调用）。
    public var maxAttempts: Int
    /// 首次重试前的基础延迟（秒）。
    public var baseDelaySeconds: TimeInterval
    /// 延迟上限（秒）。
    public var maxDelaySeconds: TimeInterval
    /// 延迟函数（测试注入瞬即返回；生产为 Task.sleep）。
    public var sleep: @Sendable (TimeInterval) async throws -> Void

    public init(
        maxAttempts: Int = 3,
        baseDelaySeconds: TimeInterval = 0.5,
        maxDelaySeconds: TimeInterval = 4,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    ) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelaySeconds = baseDelaySeconds
        self.maxDelaySeconds = maxDelaySeconds
        self.sleep = sleep
    }

    /// 判断是否值得自动重试（取消永远不重试）。
    public func shouldRetry(_ error: DictationError, attemptIndex: Int) -> Bool {
        guard attemptIndex < maxAttempts - 1 else { return false }
        switch error.category {
        case .networkUnavailable, .providerTimeout, .providerRejected:
            return error.isRetryable
        case .rateLimited:
            // 限流只自动重试一次，避免放大供应商压力。
            return error.isRetryable && attemptIndex == 0
        default:
            return false
        }
    }

    /// 第 `attemptIndex` 次失败后的等待时长（指数退避，封顶）。
    public func delaySeconds(afterAttempt attemptIndex: Int) -> TimeInterval {
        let exponential = baseDelaySeconds * pow(2, Double(attemptIndex))
        return min(exponential, maxDelaySeconds)
    }

    /// 执行带自动重试的操作。
    /// - Throws: 最后一次失败的 `DictationError`；`CancellationError` 原样传播。
    public func execute<T: Sendable>(
        operation: @Sendable (Int) async throws -> T
    ) async throws -> T {
        var attempt = 0
        while true {
            do {
                try Task.checkCancellation()
                return try await operation(attempt)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as DictationError {
                guard shouldRetry(error, attemptIndex: attempt) else { throw error }
                try await sleep(delaySeconds(afterAttempt: attempt))
                attempt += 1
            }
        }
    }
}

/// 带自动重试的语音识别装饰器（组合根包装具体适配器；
/// 流水线与编排器无需感知重试存在）。
public struct RetryingSpeechProvider: SpeechProvider {
    private let wrapped: any SpeechProvider
    private let policy: ProviderRetryPolicy

    public init(wrapped: any SpeechProvider, policy: ProviderRetryPolicy = ProviderRetryPolicy()) {
        self.wrapped = wrapped
        self.policy = policy
    }

    public var capabilities: SpeechCapabilities { wrapped.capabilities }

    /// 连接测试是用户显式诊断操作，不做自动重试（需要即时反馈真实错误）。
    public func validate() async throws -> ValidationResult {
        try await wrapped.validate()
    }

    public func transcribe(_ request: SpeechRequest) async throws -> SpeechResult {
        try await policy.execute { _ in
            try await wrapped.transcribe(request)
        }
    }
}

/// 带自动重试的文字改写装饰器。
public struct RetryingRewriteProvider: RewriteProvider {
    private let wrapped: any RewriteProvider
    private let policy: ProviderRetryPolicy

    public init(wrapped: any RewriteProvider, policy: ProviderRetryPolicy = ProviderRetryPolicy()) {
        self.wrapped = wrapped
        self.policy = policy
    }

    public var capabilities: RewriteCapabilities { wrapped.capabilities }

    public func validate() async throws -> ValidationResult {
        try await wrapped.validate()
    }

    public func rewrite(_ request: RewriteRequest) async throws -> RewriteResult {
        try await policy.execute { _ in
            try await wrapped.rewrite(request)
        }
    }
}
