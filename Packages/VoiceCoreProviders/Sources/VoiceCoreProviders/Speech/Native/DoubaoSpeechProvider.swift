import Foundation
import VoiceCoreAudio
import VoiceCoreDomain

/// 火山引擎豆包“录音文件极速版”原生协议配置。
public struct DoubaoSpeechConfiguration: Sendable, Equatable {
    public var baseURL: String
    public var modelName: String
    public var apiKey: String?
    public var resourceID: String
    public var timeoutSeconds: TimeInterval

    public init(
        baseURL: String,
        modelName: String = "bigmodel",
        apiKey: String? = nil,
        resourceID: String = "volc.bigasr.auc_turbo",
        timeoutSeconds: TimeInterval = 60
    ) {
        self.baseURL = baseURL
        self.modelName = modelName
        self.apiKey = apiKey
        self.resourceID = resourceID
        self.timeoutSeconds = timeoutSeconds
    }
}

/// 豆包录音文件极速版适配器。
///
/// 官方协议使用 `X-Api-*` 请求头和 JSON Base64 音频。VoiceCore 原始录音为
/// AAC/M4A，发送前在本机转为 16 kHz 单声道 PCM WAV。
public struct DoubaoSpeechProvider: SpeechProvider {
    public static let defaultPath = "/api/v3/auc/bigmodel/recognize/flash"
    public static let maxResponseBytes = 4 * 1024 * 1024

    private let configuration: DoubaoSpeechConfiguration
    private let transport: any HTTPTransport
    private let transcoder: WAVAudioTranscoder

    public init(
        configuration: DoubaoSpeechConfiguration,
        transport: any HTTPTransport,
        transcoder: WAVAudioTranscoder = WAVAudioTranscoder()
    ) {
        self.configuration = configuration
        self.transport = transport
        self.transcoder = transcoder
    }

    public var capabilities: SpeechCapabilities {
        SpeechCapabilities(
            supportsFileUpload: true,
            supportsStreaming: false,
            supportsLanguageHint: false,
            supportsVocabularyPrompt: false,
            supportsTimestamps: false
        )
    }

    public func validate() async throws -> ValidationResult {
        let started = Date()
        do {
            let request = try buildRequest(
                audioData: Self.makeTestWAV(),
                uid: "voicecore-connection-test",
                timeoutSeconds: configuration.timeoutSeconds
            )
            let response = try await transport.perform(request)
            let serviceCode = try checkResponseStatus(response)
            // 静音/短音频无识别结果仍证明地址、资源与密钥均有效。
            guard serviceCode == "20000000" || serviceCode == "20000003" else {
                throw Self.mapServiceError(code: serviceCode)
            }
            return .success(latencyMs: Self.elapsed(since: started))
        } catch let error as DictationError {
            return .failed(error, latencyMs: Self.elapsed(since: started))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .failed(
                DictationError(category: .unknown, userMessage: "豆包连接测试失败"),
                latencyMs: Self.elapsed(since: started)
            )
        }
    }

    public func transcribe(_ request: SpeechRequest) async throws -> SpeechResult {
        let audio = try transcoder.wavData(from: request.audioFile)
        let spec = try buildRequest(
            audioData: audio,
            uid: request.recordID.uuidString.lowercased(),
            timeoutSeconds: max(request.timeoutSeconds, configuration.timeoutSeconds)
        )
        return try parseResponse(await transport.perform(spec))
    }

    func buildRequest(audioData: Data, uid: String, timeoutSeconds: TimeInterval) throws -> HTTPRequestSpec {
        guard let key = configuration.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else {
            throw DictationError(
                category: .configurationInvalid,
                userMessage: "请先填写豆包 API Key",
                isRetryable: false
            )
        }
        let endpoint = try EndpointBuilder.build(
            baseURL: configuration.baseURL,
            defaultPath: Self.defaultPath
        )
        let requestID = UUID().uuidString
        let body = RequestBody(
            user: DoubaoRequestUser(uid: uid),
            audio: DoubaoRequestAudio(data: audioData.base64EncodedString()),
            request: DoubaoRequestOptions(
                modelName: configuration.modelName.isEmpty ? "bigmodel" : configuration.modelName
            )
        )
        let encoded: Data
        do {
            encoded = try JSONEncoder().encode(body)
        } catch {
            throw DictationError(category: .unknown, userMessage: "无法构建豆包请求")
        }
        return HTTPRequestSpec(
            method: "POST",
            url: endpoint,
            headers: [
                "Content-Type": "application/json",
                "X-Api-Key": key,
                "X-Api-Resource-Id": configuration.resourceID,
                "X-Api-Request-Id": requestID,
                "X-Api-Sequence": "-1"
            ],
            body: encoded,
            timeoutSeconds: timeoutSeconds
        )
    }

    func parseResponse(_ response: HTTPResponseSummary) throws -> SpeechResult {
        guard response.body.count <= Self.maxResponseBytes else {
            throw DictationError(category: .providerBadResponse, userMessage: "豆包响应超出大小限制")
        }
        let code = try checkResponseStatus(response)
        guard code == "20000000" else {
            throw Self.mapServiceError(code: code)
        }
        let decoded: ResponseBody
        do {
            decoded = try JSONDecoder().decode(ResponseBody.self, from: response.body)
        } catch {
            throw DictationError(category: .providerBadResponse, userMessage: "豆包响应格式异常")
        }
        guard let text = decoded.result?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw DictationError(category: .providerBadResponse, userMessage: "豆包未返回有效转录文字")
        }
        return SpeechResult(
            text: text,
            providerRequestID: response.requestID,
            reportedDurationMs: decoded.audioInfo?.duration
        )
    }

    private func checkResponseStatus(_ response: HTTPResponseSummary) throws -> String {
        guard (200 ..< 300).contains(response.statusCode) else {
            throw OpenAISpeechProvider.mapHTTPError(status: response.statusCode, body: response.body)
        }
        return response.headers["x-api-status-code"] ?? "20000000"
    }

    static func mapServiceError(code: String) -> DictationError {
        switch code {
        case "20000003":
            DictationError(category: .audioInvalid, userMessage: "录音中未检测到可识别语音", isRetryable: false)
        case "45000001", "45000002", "45000151":
            DictationError(category: .audioInvalid, userMessage: "豆包无法识别该录音格式或内容", isRetryable: false)
        case let value where value.hasPrefix("55"):
            DictationError(category: .providerRejected, userMessage: "豆包服务暂时繁忙，请稍后重试")
        default:
            DictationError(
                category: .providerRejected,
                userMessage: "豆包拒绝了请求（\(code)），请检查资源权限与模型配置",
                isRetryable: false
            )
        }
    }

    private static func elapsed(since date: Date) -> Int64 {
        Int64(Date().timeIntervalSince(date) * 1000)
    }

    /// 0.2 秒 16 kHz 单声道 PCM16 测试音频，不包含用户内容。
    static func makeTestWAV() -> Data {
        let sampleRate: UInt32 = 16000
        let samples = 3200
        var pcm = Data(capacity: samples * 2)
        for index in 0 ..< samples {
            let value = Int16(sin(Double(index) * 2 * .pi * 440 / Double(sampleRate)) * 2000)
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { pcm.append(contentsOf: $0) }
        }
        var data = Data("RIFF".utf8)
        var riffSize = UInt32(36 + pcm.count).littleEndian
        withUnsafeBytes(of: &riffSize) { data.append(contentsOf: $0) }
        data.append(Data("WAVEfmt ".utf8))
        for var value in [UInt32(16), UInt32(1) | (UInt32(1) << 16), sampleRate, sampleRate * 2] {
            value = value.littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        var blockAndBits = (UInt32(16) << 16) | UInt32(2)
        blockAndBits = blockAndBits.littleEndian
        withUnsafeBytes(of: &blockAndBits) { data.append(contentsOf: $0) }
        data.append(Data("data".utf8))
        var dataSize = UInt32(pcm.count).littleEndian
        withUnsafeBytes(of: &dataSize) { data.append(contentsOf: $0) }
        data.append(pcm)
        return data
    }
}

private struct RequestBody: Encodable {
    let user: DoubaoRequestUser
    let audio: DoubaoRequestAudio
    let request: DoubaoRequestOptions
}

private struct DoubaoRequestUser: Encodable { let uid: String }
private struct DoubaoRequestAudio: Encodable { let data: String }
private struct DoubaoRequestOptions: Encodable {
    let modelName: String
    enum CodingKeys: String, CodingKey { case modelName = "model_name" }
}

private struct ResponseBody: Decodable {
    let result: DoubaoResponseResult?
    let audioInfo: DoubaoResponseAudioInfo?

    enum CodingKeys: String, CodingKey {
        case result
        case audioInfo = "audio_info"
    }
}

private struct DoubaoResponseResult: Decodable { let text: String? }
private struct DoubaoResponseAudioInfo: Decodable { let duration: Int64? }
