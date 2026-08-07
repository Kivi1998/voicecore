import Foundation
import VoiceCoreApplication
import VoiceCoreData
import VoiceCoreDomain
import VoiceCoreProviders

/// 提供商工厂实现（组合根）：从配置仓储读取默认配置与受限秘密，
/// 构造适配器并以重试装饰器包装（STT-003）。
///
/// 密钥只在此处经 `secrets(id:)` 流向适配器配置，不进入任何
/// 可观察状态、日志或快照。
struct StoreProviderFactory: ProviderFactory {
    let profiles: any ProviderProfileRepository
    let dictionary: any DictionaryRepository
    let transport: any HTTPTransport

    func makeSpeechProvider() async throws -> (any SpeechProvider, ProviderProfileSnapshot)? {
        guard let profile = try await profiles.defaultProfile(purpose: .speech),
              profile.isEnabled else { return nil }
        let secrets = try await profiles.secrets(id: profile.id)
        let provider: any SpeechProvider
        switch profile.protocolKind {
        case .openAIAudioTranscription:
            provider = OpenAISpeechProvider(
                configuration: OpenAISpeechConfiguration(
                    baseURL: profile.baseURL,
                    modelName: profile.modelName,
                    apiKey: secrets?.apiKey,
                    customHeaders: secrets?.customHeaders ?? [:],
                    timeoutSeconds: profile.timeoutSeconds
                ),
                transport: transport
            )
        case .qwenNative:
            provider = QwenSpeechProviderSkeleton()
        case .doubaoNative:
            provider = DoubaoSpeechProvider(
                configuration: doubaoConfiguration(profile: profile, apiKey: secrets?.apiKey),
                transport: transport
            )
        case .openAIChat, .anthropicMessages:
            // 语音用途配置成改写协议属于配置错误。
            throw DictationError(
                category: .configurationInvalid,
                userMessage: "语音模型配置的协议类型不正确，请重新配置",
                isRetryable: false
            )
        }
        return (RetryingSpeechProvider(wrapped: provider), snapshot(of: profile))
    }

    func makeRewriteProvider() async throws -> (any RewriteProvider, ProviderProfileSnapshot)? {
        guard let profile = try await profiles.defaultProfile(purpose: .rewrite),
              profile.isEnabled else { return nil }
        let secrets = try await profiles.secrets(id: profile.id)
        let provider: any RewriteProvider
        switch profile.protocolKind {
        case .openAIChat:
            provider = OpenAIRewriteProvider(
                configuration: OpenAIRewriteConfiguration(
                    baseURL: profile.baseURL,
                    modelName: profile.modelName,
                    apiKey: secrets?.apiKey,
                    customHeaders: secrets?.customHeaders ?? [:],
                    timeoutSeconds: profile.timeoutSeconds
                ),
                transport: transport
            )
        case .anthropicMessages:
            provider = AnthropicRewriteProvider(
                configuration: AnthropicRewriteConfiguration(
                    baseURL: profile.baseURL,
                    modelName: profile.modelName,
                    apiKey: secrets?.apiKey,
                    customHeaders: secrets?.customHeaders ?? [:],
                    timeoutSeconds: profile.timeoutSeconds
                ),
                transport: transport
            )
        case .openAIAudioTranscription, .qwenNative, .doubaoNative:
            throw DictationError(
                category: .configurationInvalid,
                userMessage: "改写模型配置的协议类型不正确，请重新配置",
                isRetryable: false
            )
        }
        return (RetryingRewriteProvider(wrapped: provider), snapshot(of: profile))
    }

    func vocabularyTerms() async throws -> [String] {
        try await dictionary.allTermStrings()
    }

    /// 脱敏快照：绝不包含密钥。
    private func snapshot(of profile: ProviderProfile) -> ProviderProfileSnapshot {
        ProviderProfileSnapshot(
            profileID: profile.id,
            name: profile.name,
            protocolKind: profile.protocolKind,
            baseURL: profile.baseURL,
            modelName: profile.modelName
        )
    }

    func doubaoConfiguration(profile: ProviderProfile, apiKey: String?) -> DoubaoSpeechConfiguration {
        let options = try? JSONDecoder().decode(DoubaoProfileOptions.self, from: Data(profile.optionsJSON.utf8))
        return DoubaoSpeechConfiguration(
            baseURL: profile.baseURL,
            modelName: profile.modelName,
            apiKey: apiKey,
            resourceID: options?.resourceID ?? "volc.bigasr.auc_turbo",
            timeoutSeconds: profile.timeoutSeconds
        )
    }
}

private struct DoubaoProfileOptions: Decodable {
    var resourceID: String?
    enum CodingKeys: String, CodingKey { case resourceID = "resource_id" }
}

/// 流水线选项实现：会话开始时从应用设置快照。
struct StorePipelineOptionsProvider: PipelineOptionsProvider {
    let settings: any AppSettingsRepository

    func currentOptions() async throws -> PipelineOptions {
        try await PipelineOptions(
            rewriteEnabled: settings.bool(forKey: .rewriteEnabled, default: true),
            autoInsert: settings.bool(forKey: .autoInsert, default: true),
            restoreClipboard: settings.bool(forKey: .restoreClipboard, default: true),
            languageHint: .automatic
        )
    }
}
