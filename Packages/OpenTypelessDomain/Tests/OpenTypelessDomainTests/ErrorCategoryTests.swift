import XCTest
@testable import OpenTypelessDomain

final class ErrorCategoryTests: XCTestCase {
    /// 错误类别取值必须与 docs/DATA_MODEL.md §3.4 一一对应。
    func testRawValuesMatchDataModel() {
        let expected: [ErrorCategory: String] = [
            .permissionDenied: "permission_denied",
            .deviceUnavailable: "device_unavailable",
            .audioWriteFailed: "audio_write_failed",
            .audioInvalid: "audio_invalid",
            .configurationInvalid: "configuration_invalid",
            .authenticationFailed: "authentication_failed",
            .rateLimited: "rate_limited",
            .networkUnavailable: "network_unavailable",
            .providerTimeout: "provider_timeout",
            .providerRejected: "provider_rejected",
            .providerBadResponse: "provider_bad_response",
            .rewriteFailed: "rewrite_failed",
            .injectionPermissionDenied: "injection_permission_denied",
            .injectionTargetUnavailable: "injection_target_unavailable",
            .appInterrupted: "app_interrupted",
            .unknown: "unknown",
        ]
        XCTAssertEqual(ErrorCategory.allCases.count, expected.count)
        for (category, raw) in expected {
            XCTAssertEqual(category.rawValue, raw)
        }
    }

    func testRetryableDefaults() {
        XCTAssertFalse(ErrorCategory.permissionDenied.isRetryableByUser)
        XCTAssertFalse(ErrorCategory.configurationInvalid.isRetryableByUser)
        XCTAssertTrue(ErrorCategory.networkUnavailable.isRetryableByUser)
        XCTAssertTrue(ErrorCategory.rateLimited.isRetryableByUser)
    }

    func testDictationErrorDefaults() {
        let error = DictationError(category: .rateLimited, userMessage: "服务限流")
        XCTAssertTrue(error.isRetryable)
        let overridden = DictationError(category: .rateLimited, userMessage: "x", isRetryable: false)
        XCTAssertFalse(overridden.isRetryable)
    }
}
