// ModelSettingsCatalogBuilder.swift
// Provides Model Settings Catalog Builder for model settings (remote providers only).

import SwiftUI

private func localizedModelCatalog(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

@MainActor
struct ModelCatalogBuilder {
    struct CatalogDecoration {
        let filterTags: [String]
        let displayTags: [String]
        let usageLocations: [String]
    }

    let remoteASRConfigurations: [String: RemoteProviderConfiguration]
    let remoteLLMConfigurations: [String: RemoteProviderConfiguration]
    let featureSettings: FeatureSettings
    let hasIssue: (ModelConfigurationIssue.Scope) -> Bool
    let remoteASRStatusText: (RemoteASRProvider, RemoteProviderConfiguration) -> String
    let remoteLLMBadgeText: (RemoteLLMProvider) -> String?
    let primaryUserLanguageCode: String?
    let configureASRProvider: (RemoteASRProvider) -> Void
    let configureLLMProvider: (RemoteLLMProvider) -> Void

    func asrEntries() -> [ModelCatalogEntry] {
        RemoteASRProvider.allCases.map { provider in
            let selectionID = FeatureModelSelectionID.remoteASR(provider)
            let configuration = RemoteModelConfigurationStore.resolvedASRConfiguration(
                provider: provider,
                stored: remoteASRConfigurations
            )
            let configured = configuration.isConfigured
            let needsSetup = hasIssue(.remoteASRProvider(provider))
            let decoration = catalogDecoration(
                base: [localizedModelCatalog("Remote")] + remoteASRCatalogTags(for: provider, configuration: configuration),
                requiresConfiguration: true,
                configured: configured,
                selectionID: selectionID
            )

            return ModelCatalogEntry(
                id: "remote-asr:\(provider.rawValue)",
                title: provider.title,
                engine: localizedModelCatalog("Remote"),
                sizeText: configuration.hasUsableModel ? configuration.model : localizedModelCatalog("Cloud"),
                ratingText: provider == .openAIWhisper ? "4.6" : "4.4",
                filterTags: decoration.filterTags,
                displayTags: decoration.displayTags,
                statusText: remoteASRStatusText(provider, configuration),
                usageLocations: decoration.usageLocations,
                badgeText: needsSetup
                    ? localizedModelCatalog("Needs Setup")
                    : ModelCatalogBadgeSupport.recommendedBadgeText(forRemoteASRProvider: provider),
                primaryAction: ModelTableAction(title: localizedModelCatalog("Configure")) {
                    configureASRProvider(provider)
                },
                secondaryActions: []
            )
        }
    }

    func llmEntries() -> [ModelCatalogEntry] {
        RemoteLLMProvider.allCases.map { provider in
            let selectionID = FeatureModelSelectionID.remoteLLM(provider)
            let configured = RemoteModelConfigurationStore.isStoredLLMConfigurationConfigured(
                provider: provider,
                stored: remoteLLMConfigurations
            )
            let configuration = RemoteModelConfigurationStore.resolvedLLMConfiguration(
                provider: provider,
                stored: remoteLLMConfigurations
            )
            let status = configured ? "" : localizedModelCatalog("Not configured")
            let decoration = catalogDecoration(
                base: [localizedModelCatalog("Remote")] + remoteLLMCatalogTags(for: provider),
                requiresConfiguration: true,
                configured: configured,
                selectionID: selectionID
            )

            return ModelCatalogEntry(
                id: "remote-llm:\(provider.rawValue)",
                title: provider.title,
                engine: localizedModelCatalog("Remote LLM"),
                sizeText: configured ? configuration.model : localizedModelCatalog("Cloud"),
                ratingText: "4.5",
                filterTags: decoration.filterTags,
                displayTags: decoration.displayTags,
                statusText: status,
                usageLocations: decoration.usageLocations,
                badgeText: remoteLLMBadgeText(provider)
                    ?? ModelCatalogBadgeSupport.recommendedBadgeText(forRemoteLLMProvider: provider),
                primaryAction: ModelTableAction(title: localizedModelCatalog("Configure")) {
                    configureLLMProvider(provider)
                },
                secondaryActions: []
            )
        }
    }

    func usageLocations(for selectionID: FeatureModelSelectionID) -> [String] {
        var labels = [String]()
        if featureSettings.transcription.asrSelectionID == selectionID ||
            (featureSettings.transcription.llmEnabled && featureSettings.transcription.llmSelectionID == selectionID)
        {
            labels.append(localizedModelCatalog("Transcription"))
        }
        if featureSettings.translation.asrSelectionID == selectionID ||
            featureSettings.translation.modelSelectionID == selectionID
        {
            labels.append(localizedModelCatalog("Translation"))
        }
        if featureSettings.rewrite.asrSelectionID == selectionID ||
            featureSettings.rewrite.llmSelectionID == selectionID
        {
            labels.append(localizedModelCatalog("Rewrite"))
        }
        return labels
    }

    private func catalogDecoration(
        base: [String],
        requiresConfiguration: Bool,
        configured: Bool,
        selectionID: FeatureModelSelectionID
    ) -> CatalogDecoration {
        let usageLocations = usageLocations(for: selectionID)
        var filterTags = base
        if requiresConfiguration && configured {
            filterTags.append(localizedModelCatalog("Configured"))
        }
        if !usageLocations.isEmpty {
            filterTags.append(localizedModelCatalog("In Use"))
        }

        var displayTags = base.filter { $0 != localizedModelCatalog("Multilingual") }
        if let languageSupportTag = primaryLanguageSupportTag(for: selectionID) {
            displayTags.append(languageSupportTag)
        }
        if requiresConfiguration && configured {
            displayTags.append(localizedModelCatalog("Configured"))
        }
        if !usageLocations.isEmpty {
            displayTags.append(localizedModelCatalog("In Use"))
        }

        return CatalogDecoration(
            filterTags: deduplicatedTags(filterTags),
            displayTags: deduplicatedTags(displayTags),
            usageLocations: usageLocations
        )
    }

    private func remoteASRCatalogTags(
        for provider: RemoteASRProvider,
        configuration: RemoteProviderConfiguration
    ) -> [String] {
        var tags = [String]()
        switch provider {
        case .openAIWhisper:
            tags.append(localizedModelCatalog("Multilingual"))
        case .doubaoASR:
            tags.append(contentsOf: [localizedModelCatalog("Realtime"), localizedModelCatalog("Multilingual")])
        case .glmASR:
            tags.append(contentsOf: [localizedModelCatalog("Accurate"), localizedModelCatalog("Multilingual")])
        case .aliyunBailianASR:
            tags.append(localizedModelCatalog("Multilingual"))
            if RemoteASRRealtimeSupport.isAliyunRealtimeModel(configuration.model) {
                tags.append(localizedModelCatalog("Realtime"))
            }
        case .stepFunASR:
            if RemoteASRRealtimeSupport.isStepFunRealtimeModel(configuration.model) {
                tags.append(localizedModelCatalog("Realtime"))
            }
            tags.append(contentsOf: [localizedModelCatalog("Accurate"), localizedModelCatalog("Multilingual")])
        case .xiaomiMiMoASR:
            tags.append(contentsOf: [localizedModelCatalog("Accurate"), localizedModelCatalog("Multilingual")])
        }
        return deduplicatedTags(tags)
    }

    private func remoteLLMCatalogTags(for provider: RemoteLLMProvider) -> [String] {
        switch provider {
        case .lmStudio, .ollama, .omlx:
            return []
        default:
            return [localizedModelCatalog("Accurate")]
        }
    }

    private func primaryLanguageSupportTag(for selectionID: FeatureModelSelectionID) -> String? {
        guard let support = supportsPrimaryLanguage(for: selectionID) else { return nil }
        return localizedModelCatalog(support ? "Supports Primary Language" : "Does Not Support Primary Language")
    }

    private func supportsPrimaryLanguage(for selectionID: FeatureModelSelectionID) -> Bool? {
        guard resolvedPrimaryLanguageOption() != nil else { return nil }

        switch selectionID.asrSelection {
        case .dictation, .remote:
            return true
        case .mlx, .sherpaOnnx, .none:
            return nil
        }
    }

    private func resolvedPrimaryLanguageOption() -> UserMainLanguageOption? {
        guard let primaryUserLanguageCode else { return nil }
        return UserMainLanguageOption.option(for: primaryUserLanguageCode)
    }

    private func deduplicatedTags(_ tags: [String]) -> [String] {
        Array(NSOrderedSet(array: tags)) as? [String] ?? tags
    }
}
