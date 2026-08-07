import SwiftUI
import VoiceCoreDomain
import VoiceCoreProviders

/// 模型配置视图模型（SET-002/SET-003）。
///
/// 密钥安全：编辑时密钥字段留空表示保持原值（nil 更新语义），
/// 输入新值才覆盖；视图状态永不持有完整密钥（只有用户正在输入的
/// 草稿，保存后立即清空）。
@MainActor
final class ProviderSettingsViewModel: ObservableObject {
    @Published var speechProfiles: [ProviderProfile] = []
    @Published var rewriteProfiles: [ProviderProfile] = []
    @Published var rewriteEnabled = true
    @Published var editingDraft: ProfileDraft?
    @Published var statusMessage: String?
    @Published private(set) var testingProfileID: UUID?
    @Published var testResult: String?

    private let profiles: any ProviderProfileRepository
    private let settings: any AppSettingsRepository
    private let factory: StoreProviderFactory

    init(composition: AppComposition) {
        profiles = composition.profiles
        settings = composition.settings
        factory = StoreProviderFactory(
            profiles: composition.profiles,
            dictionary: composition.dictionary,
            transport: URLSessionTransport(session: .shared)
        )
    }

    func load() async {
        speechProfiles = await (try? profiles.list(purpose: .speech)) ?? []
        rewriteProfiles = await (try? profiles.list(purpose: .rewrite)) ?? []
        rewriteEnabled = await (try? settings.bool(forKey: .rewriteEnabled, default: true)) ?? true
    }

    func setRewriteEnabled(_ value: Bool) async {
        rewriteEnabled = value
        try? await settings.setBool(value, forKey: .rewriteEnabled)
    }

    func setDefault(_ profile: ProviderProfile) async {
        try? await profiles.setDefault(id: profile.id)
        await load()
    }

    func delete(_ profile: ProviderProfile) async {
        do {
            try await profiles.delete(id: profile.id)
            statusMessage = nil
            await load()
        } catch let error as DictationError {
            statusMessage = error.userMessage
        } catch {
            statusMessage = "删除失败：该配置可能正被历史记录引用。"
        }
    }

    // MARK: - 编辑

    func beginAdd(purpose: ProviderPurpose) {
        editingDraft = ProfileDraft(
            purpose: purpose,
            protocolKind: purpose == .speech ? .openAIAudioTranscription : .openAIChat
        )
        testResult = nil
    }

    func beginEdit(_ profile: ProviderProfile) {
        editingDraft = ProfileDraft(profile: profile)
        testResult = nil
    }

    func saveDraft() async {
        guard let draft = editingDraft else { return }
        do {
            let repositoryDraft = draft.toRepositoryDraft()
            if let editingID = draft.editingID {
                try await profiles.update(id: editingID, draft: repositoryDraft)
            } else {
                _ = try await profiles.create(repositoryDraft)
            }
            editingDraft = nil
            statusMessage = nil
            await load()
        } catch let error as DictationError {
            statusMessage = error.userMessage
        } catch {
            statusMessage = "保存失败，请检查必填项。"
        }
    }

    // MARK: - 连接测试（STT-004）

    /// 测试草稿配置：先保存（或临时构造），显示进行中/成功/失败。
    func testConnection() async {
        guard let draft = editingDraft else { return }
        testingProfileID = draft.editingID ?? UUID()
        testResult = nil
        defer { testingProfileID = nil }

        // 未保存的新配置先落库再测试（连接测试不产生历史记录）。
        if draft.editingID == nil {
            await saveDraft()
            testResult = "配置已保存，请选中后再次测试连接。"
            return
        }
        guard let editingID = draft.editingID,
              let profile = try? await profiles.get(id: editingID)
        else {
            testResult = "配置读取失败。"
            return
        }
        do {
            let result = try await Self.makeValidator(
                profile: profile,
                profiles: profiles,
                factory: factory
            ).validate()
            switch result.outcome {
            case .success:
                testResult = "连接成功（\(result.latencyMs) ms）"
            case .failed:
                testResult = result.error?.userMessage ?? "连接失败"
            }
        } catch is CancellationError {
            testResult = "测试已取消"
        } catch {
            testResult = "连接测试失败"
        }
    }

    private static func makeValidator(
        profile: ProviderProfile,
        profiles: any ProviderProfileRepository,
        factory: StoreProviderFactory
    ) async throws -> any ProviderValidating {
        let secrets = try await profiles.secrets(id: profile.id)
        switch (profile.purpose, profile.protocolKind) {
        case (.speech, .openAIAudioTranscription):
            return OpenAISpeechProvider(
                configuration: OpenAISpeechConfiguration(
                    baseURL: profile.baseURL,
                    modelName: profile.modelName,
                    apiKey: secrets?.apiKey,
                    customHeaders: secrets?.customHeaders ?? [:],
                    timeoutSeconds: profile.timeoutSeconds
                ),
                transport: factory.transport
            )
        case (.rewrite, .openAIChat):
            return OpenAIRewriteProvider(
                configuration: OpenAIRewriteConfiguration(
                    baseURL: profile.baseURL,
                    modelName: profile.modelName,
                    apiKey: secrets?.apiKey,
                    customHeaders: secrets?.customHeaders ?? [:],
                    timeoutSeconds: profile.timeoutSeconds
                ),
                transport: factory.transport
            )
        case (.rewrite, .anthropicMessages):
            return AnthropicRewriteProvider(
                configuration: AnthropicRewriteConfiguration(
                    baseURL: profile.baseURL,
                    modelName: profile.modelName,
                    apiKey: secrets?.apiKey,
                    customHeaders: secrets?.customHeaders ?? [:],
                    timeoutSeconds: profile.timeoutSeconds
                ),
                transport: factory.transport
            )
        case (.speech, .qwenNative):
            return QwenSpeechProviderSkeleton()
        case (.speech, .doubaoNative):
            return DoubaoSpeechProvider(
                configuration: factory.doubaoConfiguration(profile: profile, apiKey: secrets?.apiKey),
                transport: factory.transport
            )
        default:
            throw DictationError(
                category: .configurationInvalid,
                userMessage: "协议与用途不匹配",
                isRetryable: false
            )
        }
    }
}

/// 可校验协议（适配器公共子集）。
protocol ProviderValidating: Sendable {
    func validate() async throws -> ValidationResult
}

extension OpenAISpeechProvider: ProviderValidating {}
extension OpenAIRewriteProvider: ProviderValidating {}
extension AnthropicRewriteProvider: ProviderValidating {}
extension QwenSpeechProviderSkeleton: ProviderValidating {}
extension DoubaoSpeechProvider: ProviderValidating {}

/// 配置编辑草稿（密钥留空＝保持原值）。
struct ProfileDraft: Identifiable {
    var id = UUID()
    var editingID: UUID?
    var purpose: ProviderPurpose
    var name = ""
    var protocolKind: ProviderProtocolKind
    var baseURL = ""
    var modelName = ""
    var apiKeyInput = ""
    var timeoutSeconds: Double = 60

    init(purpose: ProviderPurpose, protocolKind: ProviderProtocolKind) {
        self.purpose = purpose
        self.protocolKind = protocolKind
    }

    init(profile: ProviderProfile) {
        editingID = profile.id
        purpose = profile.purpose
        name = profile.name
        protocolKind = profile.protocolKind
        baseURL = profile.baseURL
        modelName = profile.modelName
        timeoutSeconds = profile.timeoutSeconds
        apiKeyInput = "" // 密钥不回填；留空保持原值
    }

    func toRepositoryDraft() -> ProviderProfileDraft {
        ProviderProfileDraft(
            name: name,
            purpose: purpose,
            protocolKind: protocolKind,
            baseURL: baseURL,
            modelName: modelName,
            apiKeyUpdate: apiKeyInput.isEmpty ? nil : apiKeyInput,
            customHeadersUpdate: nil,
            optionsJSON: "{}",
            timeoutSeconds: timeoutSeconds,
            isEnabled: true
        )
    }
}
