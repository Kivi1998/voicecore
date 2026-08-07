import Foundation
import VoiceCoreDomain
@testable import VoiceCoreProviders
import XCTest

private actor DoubaoMockTransport: HTTPTransport {
    let response: HTTPResponseSummary
    private(set) var lastRequest: HTTPRequestSpec?

    init(response: HTTPResponseSummary) {
        self.response = response
    }

    func perform(_ request: HTTPRequestSpec) async throws -> HTTPResponseSummary {
        lastRequest = request
        return response
    }
}

final class DoubaoSpeechProviderTests: XCTestCase {
    private func provider(transport: any HTTPTransport) -> DoubaoSpeechProvider {
        DoubaoSpeechProvider(
            configuration: DoubaoSpeechConfiguration(
                baseURL: "https://openspeech.bytedance.com",
                modelName: "bigmodel",
                apiKey: "test-key"
            ),
            transport: transport
        )
    }

    func testBuildsOfficialHeadersAndJSONBody() throws {
        let adapter = provider(transport: DoubaoMockTransport(response: .init(statusCode: 200, body: Data())))
        let spec = try adapter.buildRequest(audioData: Data([1, 2, 3]), uid: "record-id", timeoutSeconds: 42)

        XCTAssertEqual(spec.method, "POST")
        XCTAssertEqual(spec.url.absoluteString, "https://openspeech.bytedance.com/api/v3/auc/bigmodel/recognize/flash")
        XCTAssertEqual(spec.headers["X-Api-Key"], "test-key")
        XCTAssertEqual(spec.headers["X-Api-Resource-Id"], "volc.bigasr.auc_turbo")
        XCTAssertEqual(spec.headers["X-Api-Sequence"], "-1")
        XCTAssertNil(spec.headers["Authorization"])
        XCTAssertEqual(spec.timeoutSeconds, 42)

        let body = try XCTUnwrap(spec.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual((json["user"] as? [String: Any])?["uid"] as? String, "record-id")
        XCTAssertEqual((json["audio"] as? [String: Any])?["data"] as? String, "AQID")
        XCTAssertEqual((json["request"] as? [String: Any])?["model_name"] as? String, "bigmodel")
    }

    func testParsesSuccessfulResponseAndHeaders() throws {
        let body = Data(#"{"audio_info":{"duration":2499},"result":{"text":"  中英 mixed text  "}}"#.utf8)
        let result = try provider(transport: DoubaoMockTransport(response: .init(statusCode: 200, body: Data())))
            .parseResponse(.init(
                statusCode: 200,
                body: body,
                requestID: "log-id",
                headers: ["x-api-status-code": "20000000"]
            ))

        XCTAssertEqual(result.text, "中英 mixed text")
        XCTAssertEqual(result.reportedDurationMs, 2499)
        XCTAssertEqual(result.providerRequestID, "log-id")
    }

    func testSilentAudioMapsToNonRetryableAudioError() throws {
        XCTAssertThrowsError(try provider(transport: DoubaoMockTransport(response: .init(
            statusCode: 200,
            body: Data()
        )))
        .parseResponse(.init(
            statusCode: 200,
            body: Data(#"{}"#.utf8),
            headers: ["x-api-status-code": "20000003"]
        ))) { error in
            let dictation = error as? DictationError
            XCTAssertEqual(dictation?.category, .audioInvalid)
            XCTAssertEqual(dictation?.isRetryable, false)
        }
    }

    func testBusyServiceIsRetryable() throws {
        XCTAssertThrowsError(try provider(transport: DoubaoMockTransport(response: .init(
            statusCode: 200,
            body: Data()
        )))
        .parseResponse(.init(
            statusCode: 200,
            body: Data(#"{}"#.utf8),
            headers: ["x-api-status-code": "55000031"]
        ))) { error in
            let dictation = error as? DictationError
            XCTAssertEqual(dictation?.category, .providerRejected)
            XCTAssertEqual(dictation?.isRetryable, true)
        }
    }

    func testValidateAcceptsRecognizedConnection() async throws {
        let transport = DoubaoMockTransport(response: .init(
            statusCode: 200,
            body: Data(#"{"result":{"text":"test"}}"#.utf8),
            headers: ["x-api-status-code": "20000000"]
        ))
        let validation = try await provider(transport: transport).validate()

        XCTAssertEqual(validation.outcome, .success)
        let request = await transport.lastRequest
        XCTAssertGreaterThan(request?.body?.count ?? 0, 1000)
    }
}
