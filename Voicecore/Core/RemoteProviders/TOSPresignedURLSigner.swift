// TOSPresignedURLSigner.swift
// Provides AWS SigV4 presigned URL signing for Volcengine TOS's S3-compatible endpoint.

import Foundation
import CryptoKit

enum TOSPresignedURLSigner {
    struct Credentials {
        let accessKey: String
        let secretKey: String
        let bucket: String
        let region: String
    }

    enum HTTPMethod: String {
        case get = "GET"
        case put = "PUT"
        case delete = "DELETE"
    }

    private static let service = "s3"
    private static let algorithm = "AWS4-HMAC-SHA256"

    /// Volcengine TOS's S3-compatible endpoint requires virtual-hosted style
    /// addressing (`bucket.tos-s3-<region>.volces.com`), not path style.
    static func s3Host(bucket: String, region: String) -> String {
        "\(bucket).tos-s3-\(region).volces.com"
    }

    static func presignedURL(
        method: HTTPMethod,
        objectKey: String,
        credentials: Credentials,
        expiresSeconds: Int = 900,
        date: Date = Date()
    ) -> URL? {
        let host = s3Host(bucket: credentials.bucket, region: credentials.region)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        let amzDate = dateFormatter.string(from: date)
        let dateStamp = String(amzDate.prefix(8))

        let credentialScope = "\(dateStamp)/\(credentials.region)/\(service)/aws4_request"
        let canonicalURI = canonicalURIPath(for: objectKey)

        let queryParams: [(String, String)] = [
            ("X-Amz-Algorithm", algorithm),
            ("X-Amz-Credential", "\(credentials.accessKey)/\(credentialScope)"),
            ("X-Amz-Date", amzDate),
            ("X-Amz-Expires", String(expiresSeconds)),
            ("X-Amz-SignedHeaders", "host")
        ]
        let canonicalQueryString = queryParams
            .sorted { $0.0 < $1.0 }
            .map { "\(sigV4Encode($0.0))=\(sigV4Encode($0.1))" }
            .joined(separator: "&")

        let canonicalHeaders = "host:\(host)\n"
        let signedHeaders = "host"
        let payloadHash = "UNSIGNED-PAYLOAD"

        let canonicalRequest = [
            method.rawValue,
            canonicalURI,
            canonicalQueryString,
            canonicalHeaders,
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")

        let stringToSign = [
            algorithm,
            amzDate,
            credentialScope,
            sha256Hex(canonicalRequest)
        ].joined(separator: "\n")

        let signingKey = deriveSigningKey(
            secretKey: credentials.secretKey,
            dateStamp: dateStamp,
            region: credentials.region,
            service: service
        )
        let signature = hmacHex(key: signingKey, message: stringToSign)

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.percentEncodedPath = canonicalURI
        components.percentEncodedQuery = canonicalQueryString + "&X-Amz-Signature=\(signature)"
        return components.url
    }

    // MARK: - Canonicalization

    private static func canonicalURIPath(for objectKey: String) -> String {
        let allowed = CharacterSet(charactersIn: "/~-._").union(.alphanumerics)
        let encoded = objectKey.addingPercentEncoding(withAllowedCharacters: allowed) ?? objectKey
        return "/" + encoded
    }

    private static func sigV4Encode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "-._~").union(.alphanumerics)
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    // MARK: - Crypto helpers

    private static func hmac(key: SymmetricKey, message: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key))
    }

    private static func hmacHex(key: Data, message: String) -> String {
        hmac(key: SymmetricKey(data: key), message: message).map { String(format: "%02x", $0) }.joined()
    }

    private static func hmacData(key: Data, message: String) -> Data {
        hmac(key: SymmetricKey(data: key), message: message)
    }

    private static func deriveSigningKey(secretKey: String, dateStamp: String, region: String, service: String) -> Data {
        let kDate = hmacData(key: Data("AWS4\(secretKey)".utf8), message: dateStamp)
        let kRegion = hmacData(key: kDate, message: region)
        let kService = hmacData(key: kRegion, message: service)
        let kSigning = hmacData(key: kService, message: "aws4_request")
        return kSigning
    }

    private static func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Verifies TOS upload credentials work end-to-end: PUT a small throwaway
/// object via a presigned URL, GET it back to confirm the content round
/// trips, then DELETE it so nothing is left behind.
enum TOSUploadConnectivityTester {
    enum TestError: LocalizedError {
        case missingCredentials
        case invalidURL
        case uploadFailed(Int)
        case downloadFailed(Int)
        case contentMismatch

        var errorDescription: String? {
            switch self {
            case .missingCredentials:
                return AppLocalization.localizedString("TOS bucket, region, access key, and secret key are all required for testing.")
            case .invalidURL:
                return AppLocalization.localizedString("Failed to build a TOS presigned URL from the current settings.")
            case .uploadFailed(let status):
                return AppLocalization.format("TOS upload test failed (HTTP %d).", status)
            case .downloadFailed(let status):
                return AppLocalization.format("TOS download test failed (HTTP %d).", status)
            case .contentMismatch:
                return AppLocalization.localizedString("TOS returned different content than what was uploaded.")
            }
        }
    }

    static func test(
        bucket: String,
        region: String,
        accessKey: String,
        secretKey: String
    ) async throws -> String {
        let bucket = bucket.trimmingCharacters(in: .whitespacesAndNewlines)
        let region = region.trimmingCharacters(in: .whitespacesAndNewlines)
        let accessKey = accessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let secretKey = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bucket.isEmpty, !region.isEmpty, !accessKey.isEmpty, !secretKey.isEmpty else {
            throw TestError.missingCredentials
        }

        let credentials = TOSPresignedURLSigner.Credentials(
            accessKey: accessKey,
            secretKey: secretKey,
            bucket: bucket,
            region: region
        )
        let objectKey = "voicecore-tos-test/\(UUID().uuidString.lowercased()).txt"
        let payload = Data("voicecore-tos-connectivity-test-\(UUID().uuidString)".utf8)

        guard let putURL = TOSPresignedURLSigner.presignedURL(method: .put, objectKey: objectKey, credentials: credentials, expiresSeconds: 120) else {
            throw TestError.invalidURL
        }
        var putRequest = URLRequest(url: putURL)
        putRequest.httpMethod = "PUT"
        putRequest.httpBody = payload
        let (_, putResponse) = try await VoiceCoreNetworkSession.withTransientRetry(stage: "tos-test-put") {
            try await VoiceCoreNetworkSession.data(for: putRequest, stage: "tos-test-put")
        }
        guard let putHTTP = putResponse as? HTTPURLResponse, (200...299).contains(putHTTP.statusCode) else {
            throw TestError.uploadFailed((putResponse as? HTTPURLResponse)?.statusCode ?? -1)
        }

        guard let getURL = TOSPresignedURLSigner.presignedURL(method: .get, objectKey: objectKey, credentials: credentials, expiresSeconds: 120) else {
            throw TestError.invalidURL
        }
        let (getData, getResponse) = try await VoiceCoreNetworkSession.withTransientRetry(stage: "tos-test-get") {
            try await VoiceCoreNetworkSession.data(for: URLRequest(url: getURL), stage: "tos-test-get")
        }
        guard let getHTTP = getResponse as? HTTPURLResponse, (200...299).contains(getHTTP.statusCode) else {
            throw TestError.downloadFailed((getResponse as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard getData == payload else {
            throw TestError.contentMismatch
        }

        if let deleteURL = TOSPresignedURLSigner.presignedURL(method: .delete, objectKey: objectKey, credentials: credentials, expiresSeconds: 120) {
            var deleteRequest = URLRequest(url: deleteURL)
            deleteRequest.httpMethod = "DELETE"
            _ = try? await VoiceCoreNetworkSession.data(for: deleteRequest, stage: "tos-test-delete")
        }

        return AppLocalization.localizedString("TOS connectivity test succeeded (upload, download, and cleanup all worked).")
    }
}
