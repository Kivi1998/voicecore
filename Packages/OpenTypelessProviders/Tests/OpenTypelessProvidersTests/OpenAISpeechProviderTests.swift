import Foundation
import OpenTypelessDomain
import XCTest
@testable import OpenTypelessProviders

/// 捕获请求并返回预设响应的传输替身（不依赖真实网络与密钥）。
final class MockTransport: HTTPTransport, @unchecked Sendable {
    private(set) var lastRequest: HTTPRequestSpec?
    var response: HTTPResponseSummary
    var error: DictationError?

    init(response: HTTPResponseSummary = HTTPResponseSummary(
        statusCode: 200,
        body: Data(#"{"text":"你好"}"#.utf8)
    )) {
        self.response = response
    }

    func perform(_ request: HTTPRequestSpec) async throws -> HTTPResponseSummary {
        lastRequest = request
        if let error {
            throw error
        }
        return response
    }
}

final class OpenAISpeechProviderTests: XCTestCase {
    private func makeProvider(
        transport: HTTPTransport,
        apiKey: String? = "sk-test-secret-0001",
        customHeaders: [String: String] = [:]
    ) -> OpenAISpeechProvider {
        OpenAISpeechProvider(
            configuration: OpenAISpeechConfiguration(
                baseURL: "https://api.example.com",
                modelName: "whisper-1",
                apiKey: apiKey,
                customHeaders: customHeaders
            ),
            transport: transport
        )
    }

    private func makeRequest(vocabulary: [String] = ["通义千问"]) throws -> SpeechRequest {
        let audio = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).m4a")
        try Data(repeating: 0x01, count: 64).write(to: audio)
        return SpeechRequest(
            audioFile: audio,
            mimeType: "audio/mp4",
            durationMs: 1000,
            vocabularyTerms: vocabulary,
            recordID: UUID(),
            attemptID: UUID()
        )
    }

    // MARK: 端点拼接

    func testEndpointAppendsDefaultPath() throws {
        let url = try EndpointBuilder.build(
            baseURL: "https://api.example.com",
            defaultPath: "/v1/audio/transcriptions"
        )
        XCTAssertEqual(url.absoluteString, "https://api.example.com/v1/audio/transcriptions")
    }

    func testEndpointHandlesTrailingSlash() throws {
        let url = try EndpointBuilder.build(
            baseURL: "https://api.example.com/",
            defaultPath: "/v1/audio/transcriptions"
        )
        XCTAssertEqual(url.absoluteString, "https://api.example.com/v1/audio/transcriptions")
    }

    func testEndpointKeepsFullEndpointWithoutDoubleAppend() throws {
        let url = try EndpointBuilder.build(
            baseURL: "https://proxy.example.com/v1/audio/transcriptions",
            defaultPath: "/v1/audio/transcriptions"
        )
        XCTAssertEqual(url.absoluteString, "https://proxy.example.com/v1/audio/transcriptions")
    }

    // MARK: 请求构造

    func testRequestContainsAuthMultipartAndPrompt() async throws {
        let mock = MockTransport()
        let provider = makeProvider(transport: mock)
        _ = try await provider.transcribe(makeRequest())

        let spec = try XCTUnwrap(mock.lastRequest)
        XCTAssertEqual(spec.method, "POST")
        XCTAssertEqual(spec.headers["Authorization"], "Bearer sk-test-secret-0001")
        XCTAssertTrue(spec.headers["Content-Type"]?.hasPrefix("multipart/form-data; boundary=") ?? false)

        let body = try String(decoding: XCTUnwrap(spec.body), as: UTF8.self)
        XCTAssertTrue(body.contains(#"name="model""#))
        XCTAssertTrue(body.contains("whisper-1"))
        XCTAssertTrue(body.contains(#"name="file"; filename="#))
        XCTAssertTrue(body.contains("audio/mp4"))
        XCTAssertTrue(body.contains(#"name="prompt""#))
        XCTAssertTrue(body.contains("通义千问"))
        XCTAssertTrue(body.contains(#"name="response_format""#))
    }

    func testCustomHeadersMergedAndReservedBlocked() async throws {
        let mock = MockTransport()
        let provider = makeProvider(
            transport: mock,
            customHeaders: [
                "X-Team": "alpha",
                "Content-Length": "999",
                "Authorization": "Bearer evil",
            ]
        )
        _ = try await provider.transcribe(makeRequest())
        let spec = try XCTUnwrap(mock.lastRequest)
        XCTAssertEqual(spec.headers["X-Team"], "alpha")
        XCTAssertNil(spec.headers["Content-Length"], "用户不得自定义 Content-Length")
        XCTAssertEqual(spec.headers["Authorization"], "Bearer sk-test-secret-0001", "用户头不得覆盖鉴权")
    }

    func testLanguageHintIncluded() async throws {
        let mock = MockTransport()
        let provider = makeProvider(transport: mock)
        var request = try makeRequest(vocabulary: [])
        request.languageHint = .chinese
        _ = try await provider.transcribe(request)
        let body = try String(decoding: XCTUnwrap(mock.lastRequest?.body), as: UTF8.self)
        XCTAssertTrue(body.contains(#"name="language""#))
        XCTAssertTrue(body.contains("zh"))
    }

    // MARK: 响应解析与错误映射

    func testSuccessfulResponseParsed() async throws {
        let mock = MockTransport(response: HTTPResponseSummary(
            statusCode: 200,
            body: Data(#"{"text":"你好，世界"}"#.utf8),
            requestID: "req-abc"
        ))
        let result = try await makeProvider(transport: mock).transcribe(makeRequest())
        XCTAssertEqual(result.text, "你好，世界")
        XCTAssertEqual(result.providerRequestID, "req-abc")
    }

    func testMissingTextIsBadResponse() async {
        let mock = MockTransport(response: HTTPResponseSummary(statusCode: 200, body: Data(#"{"foo":1}"#.utf8)))
        await assertError(mock, category: .providerBadResponse)
    }

    func testEmptyTextIsBadResponse() async {
        let mock = MockTransport(response: HTTPResponseSummary(statusCode: 200, body: Data(#"{"text":"  "}"#.utf8)))
        await assertError(mock, category: .providerBadResponse)
    }

    func testNonJSONSuccessIsBadResponse() async {
        let mock = MockTransport(response: HTTPResponseSummary(statusCode: 200, body: Data("ok".utf8)))
        await assertError(mock, category: .providerBadResponse)
    }

    func testUnauthorized() async {
        await assertError(
            MockTransport(response: HTTPResponseSummary(statusCode: 401, body: Data())),
            category: .authenticationFailed,
            retryable: false
        )
    }

    func testForbidden() async {
        await assertError(
            MockTransport(response: HTTPResponseSummary(statusCode: 403, body: Data())),
            category: .authenticationFailed,
            retryable: false
        )
    }

    func testRateLimited() async {
        await assertError(
            MockTransport(response: HTTPResponseSummary(statusCode: 429, body: Data())),
            category: .rateLimited,
            retryable: true
        )
    }

    func testModelRejected() async {
        await assertError(
            MockTransport(response: HTTPResponseSummary(statusCode: 404, body: Data())),
            category: .providerRejected,
            retryable: false
        )
    }

    func testServerError() async {
        await assertError(
            MockTransport(response: HTTPResponseSummary(statusCode: 503, body: Data())),
            category: .providerRejected,
            retryable: true
        )
    }

    func testTimeoutMapping() async {
        await assertError(
            MockTransport(response: HTTPResponseSummary(statusCode: 0, body: Data()), error: DictationError(
                category: .providerTimeout,
                userMessage: "超时"
            )),
            category: .providerTimeout
        )
    }

    private func assertError(
        _ mock: MockTransport,
        category: ErrorCategory,
        retryable: Bool? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await makeProvider(transport: mock).transcribe(makeRequest())
            XCTFail("应抛出错误", file: file, line: line)
        } catch let error as DictationError {
            XCTAssertEqual(error.category, category, file: file, line: line)
            if let retryable {
                XCTAssertEqual(error.isRetryable, retryable, file: file, line: line)
            }
        } catch {
            XCTFail("错误类型不符: \(error)", file: file, line: line)
        }
    }

    // MARK: 连接测试

    func testValidateSuccess() async throws {
        let mock = MockTransport()
        let result = try await makeProvider(transport: mock).validate()
        XCTAssertEqual(result.outcome, .success)
        // 连接测试发送的是内置静音 WAV，不涉及用户音频。
        let body = try String(decoding: XCTUnwrap(mock.lastRequest?.body), as: UTF8.self)
        XCTAssertTrue(body.contains("opentypeless-connection-test.wav"))
    }

    func testValidateFailureReturnsStructuredResult() async throws {
        let mock = MockTransport(response: HTTPResponseSummary(statusCode: 401, body: Data()))
        let result = try await makeProvider(transport: mock).validate()
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertEqual(result.error?.category, .authenticationFailed)
        XCTAssertGreaterThanOrEqual(result.latencyMs, 0)
    }

    // MARK: 词典提示截断

    func testPromptTruncatesAtTermBoundary() {
        let terms = (0 ..< 200).map { "词语\($0)-" + String(repeating: "长", count: 10) }
        let prompt = OpenAISpeechProvider.makePrompt(vocabularyTerms: terms)
        XCTAssertNotNil(prompt)
        XCTAssertLessThanOrEqual(prompt?.count ?? 0, OpenAISpeechProvider.maxPromptLength)
    }

    func testEmptyVocabularyProducesNoPrompt() {
        XCTAssertNil(OpenAISpeechProvider.makePrompt(vocabularyTerms: []))
    }

    // MARK: 脱敏

    func testLogRedactorMasksBearerToken() {
        let text = "请求失败 Authorization: Bearer sk-abcdef123456789 拒绝"
        let redacted = LogRedactor.redact(text)
        XCTAssertFalse(redacted.contains("sk-abcdef123456789"))
        XCTAssertTrue(redacted.contains("Bearer •••"))
    }

    func testRedactedHeaders() {
        let headers = ["Authorization": "Bearer secret", "X-Team": "alpha", "x-api-key": "key123"]
        let redacted = LogRedactor.redactedHeaders(headers)
        XCTAssertEqual(redacted["Authorization"], "•••")
        XCTAssertEqual(redacted["x-api-key"], "•••")
        XCTAssertEqual(redacted["X-Team"], "alpha")
    }

    // MARK: WAV 生成

    func testSilentWAVFormat() {
        let wav = OpenAISpeechProvider.makeSilentWAV()
        XCTAssertEqual(wav.count, 44 + 1600)
        XCTAssertEqual(String(decoding: wav.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: wav[8 ..< 12], as: UTF8.self), "WAVE")
    }

    // MARK: URLError 映射

    func testURLErrorMapping() {
        XCTAssertEqual(URLSessionTransport.mapURLError(URLError(.timedOut)).category, .providerTimeout)
        XCTAssertEqual(URLSessionTransport.mapURLError(URLError(.notConnectedToInternet)).category, .networkUnavailable)
        XCTAssertEqual(URLSessionTransport.mapURLError(URLError(.cannotFindHost)).category, .networkUnavailable)
        XCTAssertFalse(URLSessionTransport.mapURLError(URLError(.cancelled)).isRetryable)
    }
}

extension MockTransport {
    convenience init(response: HTTPResponseSummary, error: DictationError) {
        self.init(response: response)
        self.error = error
    }
}
