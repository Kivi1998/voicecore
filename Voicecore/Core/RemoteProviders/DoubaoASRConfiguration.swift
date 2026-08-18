// DoubaoASRConfiguration.swift
// Provides Doubao ASRConfiguration for remote provider configuration.

import Foundation

enum RemoteASRTextSanitizer {
    nonisolated static func isLikelyIdentifierText(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let uuidPattern = #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#
        if trimmed.range(of: uuidPattern, options: .regularExpression) != nil {
            return true
        }

        let compactIDPattern = #"^[0-9a-fA-F_-]{16,}$"#
        if trimmed.range(of: compactIDPattern, options: .regularExpression) != nil,
           trimmed.rangeOfCharacter(from: .letters) != nil,
           trimmed.rangeOfCharacter(from: .decimalDigits) != nil {
            return true
        }

        let compact = trimmed.replacingOccurrences(of: "-", with: "")
        if compact.count >= 24,
           compact.allSatisfy({ $0.isHexDigit }) {
            return true
        }

        return false
    }
}

enum DoubaoASRConfiguration {
    nonisolated enum CaptureRoute: Equatable, Sendable {
        case realtimeStreaming
        case flashFileRecognition
    }

    static let modelV2 = "volc.seedasr.sauc.duration"
    static let modelV1 = "volc.bigasr.sauc.duration"
    static let flashRecognitionModelTurbo = "volc.bigasr.auc_turbo"
    static let flashRecognitionModelV2 = "volc.seedasr.auc"
    static let flashRecognitionModelV1 = "volc.bigasr.auc"
    static let defaultNostreamEndpoint = "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream"
    static let defaultStreamingEndpointV1 = "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel"
    static let defaultStreamingEndpointV2 = "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async"
    static let defaultFlashRecognitionEndpoint = "https://openspeech.bytedance.com/api/v3/auc/bigmodel/recognize/flash"
    static let standardFileRecognitionSubmitEndpoint = "https://openspeech.bytedance.com/api/v3/auc/bigmodel/submit"
    static let standardFileRecognitionQueryEndpoint = "https://openspeech.bytedance.com/api/v3/auc/bigmodel/query"
    static let requestAudioFormat = "wav"
    static let streamingAudioFormat = "pcm"
    static let requestAudioCodec = "raw"
    static let streamingSampleRate = 16_000
    static let streamingBitsPerSample = 16
    static let streamingChannelCount = 1
    static let recommendedStreamingPacketBytes =
        (streamingSampleRate * streamingBitsPerSample * streamingChannelCount / 8) / 5

    static func captureRoute(realtimeTranscriptionEnabled: Bool) -> CaptureRoute {
        realtimeTranscriptionEnabled ? .realtimeStreaming : .flashFileRecognition
    }

    static func flashRecognitionRequest(
        url: URL,
        appID: String,
        accessToken: String,
        requestID: String
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(appID, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(flashRecognitionModelTurbo, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(requestID, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue("-1", forHTTPHeaderField: "X-Api-Sequence")
        return request
    }

    static func standardFileRecognitionSubmitRequest(
        appID: String,
        accessToken: String,
        requestID: String,
        resourceID: String = flashRecognitionModelV2
    ) -> URLRequest {
        var request = URLRequest(url: URL(string: standardFileRecognitionSubmitEndpoint)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(appID, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(requestID, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue("-1", forHTTPHeaderField: "X-Api-Sequence")
        return request
    }

    static func standardFileRecognitionQueryRequest(
        appID: String,
        accessToken: String,
        requestID: String,
        resourceID: String = flashRecognitionModelV2
    ) -> URLRequest {
        var request = URLRequest(url: URL(string: standardFileRecognitionQueryEndpoint)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(appID, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(requestID, forHTTPHeaderField: "X-Api-Request-Id")
        // Doubao rejects a truly empty body with HTTP 400; the docs require a
        // literal empty JSON object.
        request.httpBody = Data("{}".utf8)
        return request
    }

    /// Body for the standard (submit/query) file recognition endpoint. Unlike
    /// `flashRecognitionRequest`, the audio must be reachable at `audioURL`
    /// (Doubao's servers fetch it) rather than embedded as base64 — see
    /// docs/DoubaoASRFileRecognitionV2API.zh-CN.md for why.
    static func standardFileRecognitionSubmitPayload(
        userID: String,
        audioURL: String,
        audioFormat: String = requestAudioFormat,
        enablePunc: Bool = true,
        enableSpeakerInfo: Bool = false,
        showUtterances: Bool = true,
        dictionaryPayload: DoubaoDictionaryRequestPayload = .init()
    ) -> [String: Any] {
        var requestObject: [String: Any] = [
            "model_name": "bigmodel",
            "enable_itn": true,
            "enable_punc": enablePunc,
            "enable_speaker_info": enableSpeakerInfo,
            "show_utterances": showUtterances
        ]

        if !dictionaryPayload.hotwords.isEmpty || !dictionaryPayload.correctWords.isEmpty {
            var corpusObject: [String: Any] = [:]
            var contextObject: [String: Any] = [:]
            if !dictionaryPayload.hotwords.isEmpty {
                contextObject["hotwords"] = dictionaryPayload.hotwords.map { ["word": $0] }
            }
            if !dictionaryPayload.correctWords.isEmpty {
                contextObject["correct_words"] = dictionaryPayload.correctWords
            }
            if let contextData = try? JSONSerialization.data(withJSONObject: contextObject),
               let contextString = String(data: contextData, encoding: .utf8) {
                corpusObject["context"] = contextString
                requestObject["corpus"] = corpusObject
            }
        }

        return [
            "user": [
                "uid": userID
            ],
            "audio": [
                "url": audioURL,
                "format": audioFormat
            ],
            "request": requestObject
        ]
    }

    static func popRecommendedStreamingChunk(
        from buffer: inout Data,
        includeTrailingPartial: Bool
    ) -> Data? {
        guard buffer.count >= recommendedStreamingPacketBytes || (includeTrailingPartial && !buffer.isEmpty) else {
            return nil
        }

        let chunkSize = min(buffer.count, recommendedStreamingPacketBytes)
        let payload = Data(buffer.prefix(chunkSize))
        buffer.removeSubrange(0..<chunkSize)
        return payload
    }

    static func finalStreamingSequence(nextAudioSequence: Int32) -> Int32 {
        -max(2, nextAudioSequence)
    }

    static func resolvedEndpoint(_ endpoint: String, model: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            if let url = URL(string: trimmed) {
                let normalizedPath = url.path.lowercased()
                if normalizedPath.hasSuffix("/api/v3/sauc/bigmodel_async") {
                    return trimmed.replacingOccurrences(of: "/api/v3/sauc/bigmodel_async", with: "/api/v3/sauc/bigmodel_nostream")
                }
                if normalizedPath.hasSuffix("/api/v3/sauc/bigmodel") {
                    return trimmed.replacingOccurrences(of: "/api/v3/sauc/bigmodel", with: "/api/v3/sauc/bigmodel_nostream")
                }
            }
            return trimmed
        }

        return defaultNostreamEndpoint
    }

    static func resolvedStreamingEndpoint(_ endpoint: String, model: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        switch resolvedResourceID(model) {
        case modelV2:
            return defaultStreamingEndpointV2
        case modelV1:
            return defaultStreamingEndpointV1
        default:
            return defaultStreamingEndpointV2
        }
    }

    static func resolvedResourceID(_ model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? modelV2 : trimmed
    }

    static func isFlashRecognitionModel(_ model: String) -> Bool {
        resolvedResourceID(model) == flashRecognitionModelTurbo
    }

    static func canonicalFlashRecognitionModel(_ model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed {
        case "", modelV1, modelV2, flashRecognitionModelV1, flashRecognitionModelV2:
            return flashRecognitionModelTurbo
        default:
            return trimmed
        }
    }

    static func resolvedFlashRecognitionEndpoint(_ endpoint: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultFlashRecognitionEndpoint }
        guard var components = URLComponents(string: trimmed) else { return trimmed }
        if components.scheme == "wss" {
            components.scheme = "https"
        } else if components.scheme == "ws" {
            components.scheme = "http"
        }
        let path = components.path.lowercased()
        if path.hasSuffix("/api/v3/auc/bigmodel/recognize/flash") {
            return components.string ?? trimmed
        }
        if path.hasSuffix("/api/v3/auc/bigmodel/query") {
            components.path = components.path.replacingOccurrences(of: "/api/v3/auc/bigmodel/query", with: "/api/v3/auc/bigmodel/recognize/flash", options: [.caseInsensitive])
            return components.string ?? trimmed
        }
        if path.hasSuffix("/api/v3/auc/bigmodel/submit") {
            components.path = components.path.replacingOccurrences(of: "/api/v3/auc/bigmodel/submit", with: "/api/v3/auc/bigmodel/recognize/flash", options: [.caseInsensitive])
            return components.string ?? trimmed
        }
        if path.hasSuffix("/api/v3/sauc/bigmodel_nostream") {
            components.path = components.path.replacingOccurrences(of: "/api/v3/sauc/bigmodel_nostream", with: "/api/v3/auc/bigmodel/recognize/flash", options: [.caseInsensitive])
            return components.string ?? trimmed
        }
        if path.hasSuffix("/api/v3/sauc/bigmodel_async") {
            components.path = components.path.replacingOccurrences(of: "/api/v3/sauc/bigmodel_async", with: "/api/v3/auc/bigmodel/recognize/flash", options: [.caseInsensitive])
            return components.string ?? trimmed
        }
        if path.hasSuffix("/api/v3/sauc/bigmodel") {
            components.path = components.path.replacingOccurrences(of: "/api/v3/sauc/bigmodel", with: "/api/v3/auc/bigmodel/recognize/flash", options: [.caseInsensitive])
            return components.string ?? trimmed
        }
        return components.string ?? trimmed
    }

    static func fullRequestPayload(
        requestID: String,
        userID: String,
        language: String?,
        chineseOutputVariant: String?,
        audioFormat: String = requestAudioFormat,
        enableNonstream: Bool = false,
        dictionaryPayload: DoubaoDictionaryRequestPayload = .init()
    ) -> [String: Any] {
        var requestObject: [String: Any] = [
            "reqid": requestID,
            "model_name": "bigmodel",
            "enable_itn": true,
            "enable_punc": true,
            "enable_ddc": true,
            "show_utterances": true,
            "enable_nonstream": enableNonstream
        ]
        if let chineseOutputVariant {
            requestObject["output_zh_variant"] = chineseOutputVariant
        }
        var audioObject: [String: Any] = [
            "format": audioFormat,
            "codec": requestAudioCodec,
            "rate": streamingSampleRate,
            "bits": streamingBitsPerSample,
            "channel": streamingChannelCount
        ]
        if let language,
           !language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            audioObject["language"] = language
        }

        if !dictionaryPayload.hotwords.isEmpty || !dictionaryPayload.correctWords.isEmpty {
            var corpusObject = requestObject["corpus"] as? [String: Any] ?? [:]
            var contextObject: [String: Any] = [:]
            if !dictionaryPayload.hotwords.isEmpty {
                contextObject["hotwords"] = dictionaryPayload.hotwords.map { ["word": $0] }
            }
            if !dictionaryPayload.correctWords.isEmpty {
                contextObject["correct_words"] = dictionaryPayload.correctWords
            }
            if let contextData = try? JSONSerialization.data(withJSONObject: contextObject),
               let contextString = String(data: contextData, encoding: .utf8) {
                corpusObject["context"] = contextString
                requestObject["corpus"] = corpusObject
            }
        }

        return [
            "user": [
                "uid": userID
            ],
            "audio": audioObject,
            "request": requestObject
        ]
    }
}
