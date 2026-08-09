// ModelSettingsView.swift
// Provides Model Settings View for configuring remote ASR/LLM API providers.

import SwiftUI

private func localized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

struct ModelSettingsView: View {
    let customLLMManager: CustomLLMModelManager

    @AppStorage(AppPreferenceKey.remoteASRProviderConfigurations) private var remoteASRProviderConfigurationsRaw = ""
    @AppStorage(AppPreferenceKey.remoteLLMProviderConfigurations) private var remoteLLMProviderConfigurationsRaw = ""
    @AppStorage(AppPreferenceKey.userMainLanguageCodes) private var userMainLanguageCodesRaw = UserMainLanguageOption.defaultStoredSelectionValue
    @AppStorage(AppPreferenceKey.interfaceLanguage) private var interfaceLanguageRaw = AppInterfaceLanguage.system.rawValue
    @AppStorage(AppPreferenceKey.featureSettings) private var featureSettingsRaw = ""

    @State private var catalogTab: ModelCatalogTab = .asr
    @State private var selectedTags = Set<String>()
    @State private var cachedFeatureSettings = FeatureSettingsStore.load()
    @State private var catalogSnapshot = ModelSettingsCatalogSnapshot.empty
    @State private var missingConfigurationIssues: [ModelConfigurationIssue] = []
    @State private var editingASRProvider: RemoteASRProvider?
    @State private var editingLLMProvider: RemoteLLMProvider?
    @State private var modelOperationToastMessage = ""
    @State private var modelOperationToastDismissTask: Task<Void, Never>?

    private var remoteASRConfigurations: [String: RemoteProviderConfiguration] {
        RemoteModelConfigurationStore.loadConfigurations(
            from: remoteASRProviderConfigurationsRaw,
            sensitiveValueLoading: .metadataOnly
        )
    }

    private var remoteLLMConfigurations: [String: RemoteProviderConfiguration] {
        RemoteModelConfigurationStore.loadConfigurations(
            from: remoteLLMProviderConfigurationsRaw,
            sensitiveValueLoading: .metadataOnly
        )
    }

    private var selectedUserLanguageCodes: [String] {
        UserMainLanguageOption.storedSelection(from: userMainLanguageCodesRaw)
    }

    private var catalogBuilder: ModelCatalogBuilder {
        ModelCatalogBuilder(
            remoteASRConfigurations: remoteASRConfigurations,
            remoteLLMConfigurations: remoteLLMConfigurations,
            featureSettings: cachedFeatureSettings,
            hasIssue: hasIssue(for:),
            remoteASRStatusText: { provider, configuration in
                remoteASRStatusText(for: provider, configuration: configuration)
            },
            remoteLLMBadgeText: remoteLLMBadgeText(for:),
            primaryUserLanguageCode: selectedUserLanguageCodes.first,
            configureASRProvider: { editingASRProvider = $0 },
            configureLLMProvider: { editingLLMProvider = $0 }
        )
    }

    private var filteredEntries: [ModelCatalogEntry] {
        catalogSnapshot.filteredEntries
    }

    private var availableTags: [String] {
        catalogSnapshot.availableTags
    }

    private var availableTagGroups: [[String]] {
        catalogSnapshot.availableTagGroups
    }

    private var displayItems: [ModelCatalogDisplayItem] {
        catalogSnapshot.displayItems
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            modelTabHeader
            tagFilterBar
            modelCatalogContent
        }
        .overlay(alignment: .top) {
            if !modelOperationToastMessage.isEmpty {
                ModelDebugToast(message: modelOperationToastMessage) {
                    dismissModelOperationToast()
                }
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.16), value: modelOperationToastMessage)
        .id(interfaceLanguageRaw)
        .onAppear {
            reloadCachedState()
            refreshCatalogSnapshot()
        }
        .onChange(of: catalogTab) { _, _ in
            pruneSelectedTags()
            refreshCatalogSnapshot()
        }
        .onChange(of: selectedTags) { _, _ in
            refreshCatalogSnapshot()
        }
        .onChange(of: featureSettingsRaw) { _, _ in
            reloadCachedState()
            refreshCatalogSnapshot()
        }
        .onChange(of: remoteASRProviderConfigurationsRaw) { _, _ in
            refreshCatalogSnapshot()
        }
        .onChange(of: remoteLLMProviderConfigurationsRaw) { _, _ in
            refreshCatalogSnapshot()
        }
        .sheet(item: $editingASRProvider) { provider in
            RemoteProviderConfigurationSheet(
                providerTitle: provider.title,
                credentialHint: asrCredentialHint(for: provider),
                showsDoubaoFields: provider == .doubaoASR,
                testTarget: .asr(provider),
                configuration: RemoteModelConfigurationStore.resolvedASRConfiguration(
                    provider: provider,
                    from: remoteASRProviderConfigurationsRaw
                )
            ) { updated in
                let result = saveRemoteASRConfiguration(updated)
                if case .success = result {
                    showModelOperationToast(String(format: AppLocalization.localizedString("Configuration saved for %@."), provider.title))
                }
                return result
            }
        }
        .sheet(item: $editingLLMProvider) { provider in
            RemoteProviderConfigurationSheet(
                providerTitle: provider.title,
                credentialHint: nil,
                showsDoubaoFields: false,
                testTarget: .llm(provider),
                configuration: RemoteModelConfigurationStore.resolvedLLMConfiguration(
                    provider: provider,
                    from: remoteLLMProviderConfigurationsRaw
                )
            ) { updated in
                let result = saveRemoteLLMConfiguration(updated)
                if case .success = result {
                    showModelOperationToast(String(format: AppLocalization.localizedString("Configuration saved for %@."), provider.title))
                }
                return result
            }
        }
    }

    private var modelTabHeader: some View {
        HStack(spacing: 10) {
            ModelCatalogTabPicker(selectedTab: $catalogTab)

            Spacer(minLength: 0)

            if !missingConfigurationIssues.isEmpty {
                missingConfigurationMenu
            }

            Text(String(format: AppLocalization.localizedString("%d items"), filteredEntries.count))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var missingConfigurationMenu: some View {
        Menu {
            ForEach(missingConfigurationIssueDescriptions, id: \.self) { description in
                Text(description)
            }
        } label: {
            missingConfigurationMenuLabel
        }
        .menuStyle(.borderlessButton)
        .help(missingConfigurationIssueDescriptions.joined(separator: "\n"))
    }

    private var missingConfigurationMenuLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(missingConfigurationIssueCountLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.orange.opacity(0.18), lineWidth: 1)
        )
    }

    private var missingConfigurationIssueCountLabel: String {
        missingConfigurationIssues.count == 1
            ? localized("1 model needs setup")
            : String(format: AppLocalization.localizedString("%d models need setup"), missingConfigurationIssues.count)
    }

    private var missingConfigurationIssueDescriptions: [String] {
        missingConfigurationIssues.map(missingConfigurationIssueDescription(for:))
    }

    private func missingConfigurationIssueDescription(
        for issue: ModelConfigurationIssue
    ) -> String {
        switch issue.scope {
        case let .remoteASRProvider(provider):
            return String(format: AppLocalization.localizedString("%@ %@: %@"), provider.title, localized("ASR"), issue.message)
        case let .remoteLLMProvider(provider):
            return String(format: AppLocalization.localizedString("%@ %@: %@"), provider.title, localized("LLM"), issue.message)
        case let .customLLMModel(repo):
            return String(format: AppLocalization.localizedString("%@ %@: %@"), customLLMManager.displayTitle(for: repo), localized("LLM"), issue.message)
        case let .translationRemoteLLM(provider):
            return String(format: AppLocalization.localizedString("%@ %@: %@"), provider.title, localized("Translation"), issue.message)
        case let .rewriteRemoteLLM(provider):
            return String(format: AppLocalization.localizedString("%@ %@: %@"), provider.title, localized("Rewrite"), issue.message)
        case let .translationCustomLLM(repo):
            return String(format: AppLocalization.localizedString("%@ %@: %@"), customLLMManager.displayTitle(for: repo), localized("Translation"), issue.message)
        case let .rewriteCustomLLM(repo):
            return String(format: AppLocalization.localizedString("%@ %@: %@"), customLLMManager.displayTitle(for: repo), localized("Rewrite"), issue.message)
        }
    }

    @ViewBuilder
    private var tagFilterBar: some View {
        if !availableTags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(availableTagGroups.enumerated()), id: \.offset) { index, group in
                        HStack(spacing: 8) {
                            ForEach(group, id: \.self) { tag in
                                ModelTagChip(
                                    title: tag,
                                    isSelected: selectedTags.contains(tag),
                                    action: { toggleTag(tag) }
                                )
                            }
                        }

                        if index < availableTagGroups.count - 1 {
                            Rectangle()
                                .fill(SettingsUIStyle.subtleBorderColor.opacity(0.95))
                                .frame(width: 1, height: 20)
                                .padding(.horizontal, 4)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var modelCatalogContent: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if filteredEntries.isEmpty {
                    ModelEmptyStateView()
                } else {
                    ForEach(displayItems) { item in
                        modelCatalogItemView(item)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func modelCatalogItemView(_ item: ModelCatalogDisplayItem) -> some View {
        switch item {
        case let .row(entry):
            ModelCatalogRow(entry: entry)
        case let .group(group):
            ModelCatalogGroupCard(group: group, isExpanded: true, onToggle: {})
        }
    }

    private func toggleTag(_ tag: String) {
        selectedTags = ModelCatalogTag.toggledTags(current: selectedTags, tag: tag)
    }

    private func pruneSelectedTags() {
        selectedTags = selectedTags.intersection(Set(availableTags))
    }

    private func reloadCachedState() {
        cachedFeatureSettings = FeatureSettingsStore.load()
        missingConfigurationIssues = ModelConfigurationIssueResolver.missingIssues(customLLMManager: customLLMManager)
    }

    private func refreshCatalogSnapshot() {
        let entries = switch catalogTab {
        case .asr:
            catalogBuilder.asrEntries()
        case .llm:
            catalogBuilder.llmEntries()
        }

        catalogSnapshot = ModelSettingsCatalogSnapshotBuilder.build(
            entries: entries,
            selectedTags: selectedTags
        )
    }

    private func hasIssue(for scope: ModelConfigurationIssue.Scope) -> Bool {
        missingConfigurationIssues.contains(where: { $0.scope == scope })
    }

    private func remoteLLMBadgeText(for provider: RemoteLLMProvider) -> String? {
        let scopes: [ModelConfigurationIssue.Scope] = [
            .remoteLLMProvider(provider),
            .translationRemoteLLM(provider),
            .rewriteRemoteLLM(provider)
        ]
        return missingConfigurationIssues.contains(where: { scopes.contains($0.scope) }) ? AppLocalization.localizedString("Needs Setup") : nil
    }

    private func remoteASRStatusText(
        for provider: RemoteASRProvider,
        configuration: RemoteProviderConfiguration
    ) -> String {
        guard configuration.isConfigured else {
            return AppLocalization.localizedString("Not configured")
        }
        return ""
    }

    private func asrCredentialHint(for provider: RemoteASRProvider) -> String? {
        switch provider {
        case .doubaoASR:
            return localized("Doubao uses App ID + Access Token for streaming API.")
        case .aliyunBailianASR:
            return localized("Aliyun ASR in VoiceCore uses realtime WebSocket only: Qwen models use /api-ws/v1/realtime, Fun/Paraformer models use /api-ws/v1/inference.")
        case .xiaomiMiMoASR:
            return localized("Xiaomi MiMo ASR uses a MiMo API Key and the OpenAI-compatible chat completions audio endpoint.")
        case .openAIWhisper, .glmASR, .stepFunASR:
            return nil
        }
    }

    private func saveRemoteASRConfiguration(
        _ configuration: RemoteProviderConfiguration
    ) -> Result<Void, RemoteModelConfigurationStore.SaveError> {
        let result = RemoteModelConfigurationStore.saveConfiguration(
            configuration,
            updating: remoteASRProviderConfigurationsRaw
        )
        switch result {
        case .success(let raw):
            remoteASRProviderConfigurationsRaw = raw
            NotificationCenter.default.post(name: .voicecoreRemoteProviderConfigurationsDidChange, object: nil)
            reloadCachedState()
            refreshCatalogSnapshot()
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

    private func saveRemoteLLMConfiguration(
        _ configuration: RemoteProviderConfiguration
    ) -> Result<Void, RemoteModelConfigurationStore.SaveError> {
        let result = RemoteModelConfigurationStore.saveConfiguration(
            configuration,
            updating: remoteLLMProviderConfigurationsRaw
        )
        switch result {
        case .success(let raw):
            remoteLLMProviderConfigurationsRaw = raw
            NotificationCenter.default.post(name: .voicecoreRemoteProviderConfigurationsDidChange, object: nil)
            NotificationCenter.default.post(name: .voicecoreRemoteLLMProviderConfigurationsDidChange, object: nil)
            reloadCachedState()
            refreshCatalogSnapshot()
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

    private func showModelOperationToast(_ message: String, duration: Duration = .seconds(4)) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        modelOperationToastDismissTask?.cancel()
        modelOperationToastMessage = trimmed
        modelOperationToastDismissTask = Task { @MainActor in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            modelOperationToastMessage = ""
        }
    }

    private func dismissModelOperationToast() {
        modelOperationToastDismissTask?.cancel()
        modelOperationToastMessage = ""
    }
}
