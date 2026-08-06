import Foundation
import XCTest
@testable import OpenTypelessProviders
import OpenTypelessDomain

/// 提供商自动重试策略测试（STT-003）。
final class ProviderRetryPolicyTests: XCTestCase {
    /// 无延迟的策略（测试瞬即完成）。
    private func makePolicy(maxAttempts: Int = 3) -> ProviderRetryPolicy {
        ProviderRetryPolicy(maxAttempts: maxAttempts, sleep: { _ in })
    }

    func testTransientNetworkErrorRetriesUntilSuccess() async throws {
        let policy = makePolicy()
        let counter = Counter()
        let value: String = try await policy.execute { attempt in
            await counter.increment()
            if attempt < 2 {
                throw DictationError(category: .networkUnavailable, userMessage: "网络不可用")
            }
            return "ok"
        }
        XCTAssertEqual(value, "ok")
        XCTAssertEqual(await counter.value, 3)
    }

    func testTimeoutRetriesWithExponentialBackoff() async throws {
        var delays: [TimeInterval] = []
        let policy = ProviderRetryPolicy(
            maxAttempts: 4,
            baseDelaySeconds: 0.5,
            maxDelaySeconds: 4,
            sleep: { delays.append($0) }
        )
        do {
            let _: String = try await policy.execute { _ in
                throw DictationError(category: .providerTimeout, userMessage: "超时")
            }
            XCTFail("应抛出超时错误")
        } catch let error as DictationError {
            XCTAssertEqual(error.category, .providerTimeout)
        }
        XCTAssertEqual(delays, [0.5, 1.0, 2.0])
    }

    func testRateLimitedRetriesOnlyOnce() async throws {
        let policy = makePolicy(maxAttempts: 5)
        let counter = Counter()
        do {
            let _: String = try await policy.execute { _ in
                await counter.increment()
                throw DictationError(category: .rateLimited, userMessage: "限流")
            }
            XCTFail("应抛出限流错误")
        } catch let error as DictationError {
            XCTAssertEqual(error.category, .rateLimited)
        }
        // 首次 + 一次自动重试。
        XCTAssertEqual(await counter.value, 2)
    }

    func testAuthAndConfigErrorsNeverRetry() async throws {
        for category in [ErrorCategory.authenticationFailed, .configurationInvalid, .providerBadResponse, .permissionDenied] {
            let policy = makePolicy()
            let counter = Counter()
            do {
                let _: String = try await policy.execute { _ in
                    await counter.increment()
                    throw DictationError(category: category, userMessage: "不可重试")
                }
                XCTFail("\(category) 应直接抛出")
            } catch let error as DictationError {
                XCTAssertEqual(error.category, category)
            }
            XCTAssertEqual(await counter.value, 1, "\(category) 不应重试")
        }
    }

    func testCancellationDoesNotRetry() async throws {
        let policy = makePolicy()
        let counter = Counter()
        do {
            let _: String = try await policy.execute { _ in
                await counter.increment()
                throw CancellationError()
            }
            XCTFail("应传播取消")
        } catch is CancellationError {
            // 预期
        }
        XCTAssertEqual(await counter.value, 1)
    }

    func testNonRetryableFlagSuppressesRetry() async throws {
        let policy = makePolicy()
        let counter = Counter()
        do {
            let _: String = try await policy.execute { _ in
                await counter.increment()
                throw DictationError(category: .networkUnavailable, userMessage: "不可重试", isRetryable: false)
            }
            XCTFail("应抛出错误")
        } catch let error as DictationError {
            XCTAssertEqual(error.category, .networkUnavailable)
        }
        XCTAssertEqual(await counter.value, 1)
    }

    // MARK: - 装饰器

    func testRetryingSpeechProviderRetriesTransientFailure() async throws {
        let stub = StubSpeechProvider(results: [
            .failure(DictationError(category: .networkUnavailable, userMessage: "网络不可用")),
            .success(SpeechResult(text: "转录成功")),
        ])
        let provider = RetryingSpeechProvider(wrapped: stub, policy: makePolicy())

        let result = try await provider.transcribe(makeSpeechRequest())
        XCTAssertEqual(result.text, "转录成功")
        XCTAssertEqual(stub.callCount, 2)
    }

    func testRetryingSpeechProviderValidateDoesNotRetry() async throws {
        let stub = StubSpeechProvider(validationError: DictationError(
            category: .authenticationFailed,
            userMessage: "密钥无效"
        ))
        let provider = RetryingSpeechProvider(wrapped: stub, policy: makePolicy())

        let validation = try await provider.validate()
        XCTAssertEqual(validation.outcome, .failed)
        XCTAssertEqual(validation.error?.category, .authenticationFailed)
        XCTAssertEqual(stub.validateCount, 1)
    }

    func testRetryingRewriteProviderRetriesThenSucceeds() async throws {
        let stub = StubRewriteProvider(results: [
            .failure(DictationError(category: .providerRejected, userMessage: "服务端错误")),
            .success(RewriteResult(finalText: "改写成功")),
        ])
        let provider = RetryingRewriteProvider(wrapped: stub, policy: makePolicy())

        let result = try await provider.rewrite(RewriteRequest(
            originalText: "原文",
            vocabularyTerms: [],
            recordID: UUID(),
            attemptID: UUID()
        ))
        XCTAssertEqual(result.finalText, "改写成功")
        XCTAssertEqual(stub.callCount, 2)
    }

    // MARK: - 工具

    private func makeSpeechRequest() -> SpeechRequest {
        SpeechRequest(
            audioFile: URL(fileURLWithPath: "/tmp/test.m4a"),
            mimeType: "audio/mp4",
            durationMs: 1_000,
            recordID: UUID(),
            attemptID: UUID()
        )
    }
}

// MARK: - 替身

private actor Counter {
    var value = 0
    func increment() { value += 1 }
}

private final class StubSpeechProvider: SpeechProvider, @unchecked Sendable {
    var results: [Result<SpeechResult, DictationError>]
    var validationError: DictationError?
    private(set) var callCount = 0
    private(set) var validateCount = 0

    init(results: [Result<SpeechResult, DictationError>] = [], validationError: DictationError? = nil) {
        self.results = results
        self.validationError = validationError
    }

    var capabilities: SpeechCapabilities { SpeechCapabilities(supportsFileUpload: true) }

    func validate() async throws -> ValidationResult {
        validateCount += 1
        if let validationError { return .failed(validationError, latencyMs: 1) }
        return .success(latencyMs: 1)
    }

    func transcribe(_ request: SpeechRequest) async throws -> SpeechResult {
        let index = callCount
        callCount += 1
        guard index < results.count else {
            throw DictationError(category: .unknown, userMessage: "超出替身结果数量")
        }
        return try results[index].get()
    }
}

private final class StubRewriteProvider: RewriteProvider, @unchecked Sendable {
    var results: [Result<RewriteResult, DictationError>]
    private(set) var callCount = 0

    init(results: [Result<RewriteResult, DictationError>]) {
        self.results = results
    }

    var capabilities: RewriteCapabilities { RewriteCapabilities() }

    func validate() async throws -> ValidationResult { .success(latencyMs: 1) }

    func rewrite(_ request: RewriteRequest) async throws -> RewriteResult {
        let index = callCount
        callCount += 1
        guard index < results.count else {
            throw DictationError(category: .unknown, userMessage: "超出替身结果数量")
        }
        return try results[index].get()
    }
}
