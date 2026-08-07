@testable import VoiceCoreProviders
import XCTest

/// 日志脱敏规则测试（FND-004 验收：脱敏规则有自动测试）。
final class LogRedactorTests: XCTestCase {
    func testRedactBearerToken() {
        let input = "请求失败：Authorization: Bearer sk-abc123def456ghi789"
        let output = LogRedactor.redact(input)
        XCTAssertFalse(output.contains("sk-abc123def456ghi789"))
        XCTAssertTrue(output.contains("Bearer •••"))
    }

    func testRedactBearerCaseInsensitive() {
        let output = LogRedactor.redact("bearer TOKENVALUE123")
        XCTAssertFalse(output.contains("TOKENVALUE123"))
    }

    func testRedactCommonKeyShapes() {
        let output = LogRedactor.redact("key=sk-projAbcd1234Efgh5678 end")
        XCTAssertFalse(output.contains("sk-projAbcd1234Efgh5678"))
        XCTAssertTrue(output.contains("•••"))
    }

    func testRedactKeepsOrdinaryText() {
        let input = "转录完成，耗时 1200ms，状态码 200"
        XCTAssertEqual(LogRedactor.redact(input), input)
    }

    func testRedactedHeadersMasksSensitiveValues() {
        let headers = [
            "Authorization": "Bearer sk-secret-value-123456",
            "x-api-key": "anthropic-key-abcdefgh",
            "Content-Type": "application/json",
            "anthropic-version": "2023-06-01"
        ]
        let redacted = LogRedactor.redactedHeaders(headers)
        XCTAssertEqual(redacted["Authorization"], "•••")
        XCTAssertEqual(redacted["x-api-key"], "•••")
        XCTAssertEqual(redacted["Content-Type"], "application/json")
        XCTAssertEqual(redacted["anthropic-version"], "2023-06-01")
    }

    func testRedactedHeadersIsCaseInsensitiveForNames() {
        let redacted = LogRedactor.redactedHeaders(["AUTHORIZATION": "secret-value-123456"])
        XCTAssertEqual(redacted["AUTHORIZATION"], "•••")
    }
}
