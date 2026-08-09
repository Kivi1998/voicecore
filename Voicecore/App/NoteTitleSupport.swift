// NoteTitleSupport.swift
// Provides Note Title Support for app lifecycle and routing.

import Foundation
import AppKit

private enum VoiceCoreNoteTitleModel {
    case appleIntelligence
    case customLLM(repo: String)
    case remoteLLM(provider: RemoteLLMProvider, configuration: RemoteProviderConfiguration)
}

extension AppDelegate {
    @discardableResult
    func appendVoiceCoreNote(
        text: String,
        sessionID: UUID,
        source: VoiceCoreNoteSource = .transcription
    ) -> Bool {
        let fallbackTitle = VoiceCoreNoteTitleSupport.fallbackTitle(from: text)
        let resolvedTitleModel = resolvedVoiceCoreNoteTitleModel()
        let shouldEnhanceText = source == .transcription && enhancementMode != .off
        let initialState: NoteTitleGenerationState = resolvedTitleModel == nil && !shouldEnhanceText
            ? .fallback
            : .pending

        guard let item = noteStore.append(
            sessionID: sessionID,
            text: text,
            title: fallbackTitle,
            titleGenerationState: initialState,
            source: source
        ) else {
            return false
        }

        noteWindowManager.show()

        if shouldEnhanceText {
            Task { @MainActor [weak self] in
                await self?.enhanceVoiceCoreNoteAndGenerateTitle(
                    for: item.id,
                    rawText: item.text,
                    titleModel: resolvedTitleModel
                )
            }
            return true
        }

        guard let resolvedTitleModel else { return true }
        Task { @MainActor [weak self] in
            await self?.generateVoiceCoreNoteTitle(
                for: item.id,
                text: item.text,
                fallbackTitle: fallbackTitle,
                model: resolvedTitleModel
            )
        }
        return true
    }

    private func enhanceVoiceCoreNoteAndGenerateTitle(
        for noteID: UUID,
        rawText: String,
        titleModel: VoiceCoreNoteTitleModel?
    ) async {
        let resolvedText: String
        do {
            let enhancedText = try await enhanceTextForCurrentMode(rawText)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            resolvedText = enhancedText.isEmpty ? rawText : enhancedText
            VoiceCoreLog.history(
                "VoiceCore note enhancement completed. noteID=\(noteID.uuidString), inputChars=\(rawText.count), outputChars=\(resolvedText.count)"
            )
        } catch {
            resolvedText = rawText
            VoiceCoreLog.historyWarning(
                "VoiceCore note enhancement failed; preserving raw text. noteID=\(noteID.uuidString), error=\(error.localizedDescription)"
            )
        }

        guard let currentItem = noteStore.updateText(
            resolvedText,
            ifUnchangedFrom: rawText,
            for: noteID
        ) else { return }

        let finalText = currentItem.text
        let fallbackTitle = VoiceCoreNoteTitleSupport.fallbackTitle(from: finalText)
        guard let titleModel else {
            _ = noteStore.updateTitle(fallbackTitle, state: .fallback, for: noteID)
            return
        }
        await generateVoiceCoreNoteTitle(
            for: noteID,
            text: finalText,
            fallbackTitle: fallbackTitle,
            model: titleModel
        )
    }

    private func generateVoiceCoreNoteTitle(
        for noteID: UUID,
        text: String,
        fallbackTitle: String,
        model: VoiceCoreNoteTitleModel
    ) async {
        do {
            let generatedTitle = try await runVoiceCoreNoteTitlePrompt(
                voicecoreNoteTitlePrompt(for: text),
                model: model
            )
            let normalizedTitle = VoiceCoreNoteTitleSupport.normalizedGeneratedTitle(generatedTitle)
            let resolvedTitle = normalizedTitle.isEmpty ? fallbackTitle : normalizedTitle
            let resolvedState: NoteTitleGenerationState = normalizedTitle.isEmpty ? .fallback : .generated
            _ = noteStore.updateTitle(resolvedTitle, state: resolvedState, for: noteID)
            VoiceCoreLog.history(
                "VoiceCore note title generated. noteID=\(noteID.uuidString), state=\(resolvedState.rawValue), titleChars=\(resolvedTitle.count)"
            )
        } catch {
            _ = noteStore.updateTitle(fallbackTitle, state: .fallback, for: noteID)
            VoiceCoreLog.historyWarning("VoiceCore note title generation failed. noteID=\(noteID.uuidString), error=\(error.localizedDescription)")
        }
    }

    private func resolvedVoiceCoreNoteTitleModel() -> VoiceCoreNoteTitleModel? {
        switch noteFeatureSettings.titleModelSelectionID.textSelection {
        case .appleIntelligence:
            guard let enhancer else { return nil }
            if #available(macOS 26.0, *) {
                guard TextEnhancer.isAvailable else { return nil }
                _ = enhancer
                return .appleIntelligence
            }
            return nil
        case .localLLM(let repo):
            guard customLLMManager.isModelDownloaded(repo: repo) else { return nil }
            return .customLLM(repo: repo)
        case .remoteLLM(let provider):
            guard RemoteModelConfigurationStore.isStoredLLMConfigurationConfigured(
                provider: provider,
                stored: remoteLLMConfigurations
            ) else {
                return nil
            }
            let configuration = RemoteModelConfigurationStore.resolvedLLMConfiguration(
                provider: provider,
                stored: remoteLLMConfigurations
            )
            return .remoteLLM(provider: provider, configuration: configuration)
        case .none:
            return nil
        }
    }

    private func runVoiceCoreNoteTitlePrompt(
        _ prompt: String,
        model: VoiceCoreNoteTitleModel
    ) async throws -> String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return "" }

        switch model {
        case .appleIntelligence:
            guard let enhancer else {
                throw NSError(
                    domain: "VoiceCore.NoteTitle",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Apple Intelligence is unavailable.")]
                )
            }
            if #available(macOS 26.0, *) {
                return try await enhancer.enhance(userPrompt: trimmedPrompt)
            }
            throw NSError(
                domain: "VoiceCore.NoteTitle",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Apple Intelligence requires macOS 26 or later.")]
            )
        case .customLLM(let repo):
            return try await customLLMManager.enhance(userPrompt: trimmedPrompt, repo: repo)
        case .remoteLLM(let provider, let configuration):
            return try await RemoteLLMRuntimeClient().enhance(
                userPrompt: trimmedPrompt,
                provider: provider,
                configuration: configuration
            )
        }
    }

    private func voicecoreNoteTitlePrompt(for text: String) -> String {
        """
        You are VoiceCore's note title generator.

        Generate a very short plain-text title for the note below.

        Rules:
        1. Reply in the user's main language.
        2. Return one line only.
        3. Keep it concise and specific.
        4. Avoid quotes, numbering, markdown, or extra explanation.
        5. Prefer 4-8 words, or under 20 Chinese characters.

        User main language: \(userMainLanguagePromptValue)

        Note text:
        \(text)
        """
    }
}
