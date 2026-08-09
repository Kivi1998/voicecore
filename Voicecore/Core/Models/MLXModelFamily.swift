// MLXModelFamily.swift
// Classifies MLX ASR model repos into families for the (now unused) model catalog.

import Foundation

nonisolated enum MLXModelFamily: String, CaseIterable, Codable, Identifiable, Sendable {
    case whisper
    case qwen3ASR
    case graniteSpeech
    case senseVoice
    case cohereTranscribe
    case nemotronASR
    case voxtralRealtime
    case mossTranscribeDiarize
    case canary
    case moonshine
    case wav2vec2CTC
    case mmsCTC
    case parakeet
    case lasrCTC
    case generic

    var id: String { rawValue }

    static func family(for repo: String) -> MLXModelFamily {
        MLXModelCatalog.capability(for: repo).family
    }

    var title: String {
        switch self {
        case .whisper:
            return AppLocalization.localizedString("Whisper")
        case .qwen3ASR:
            return AppLocalization.localizedString("Qwen3")
        case .graniteSpeech:
            return AppLocalization.localizedString("Granite")
        case .senseVoice:
            return AppLocalization.localizedString("SenseVoice")
        case .cohereTranscribe:
            return AppLocalization.localizedString("Cohere")
        case .nemotronASR:
            return AppLocalization.localizedString("Nemotron")
        case .voxtralRealtime:
            return AppLocalization.localizedString("Voxtral")
        case .mossTranscribeDiarize:
            return AppLocalization.localizedString("MOSS")
        case .canary:
            return AppLocalization.localizedString("Canary")
        case .moonshine:
            return AppLocalization.localizedString("Moonshine")
        case .wav2vec2CTC:
            return AppLocalization.localizedString("Wav2Vec2")
        case .mmsCTC:
            return AppLocalization.localizedString("MMS")
        case .parakeet:
            return AppLocalization.localizedString("Parakeet")
        case .lasrCTC:
            return AppLocalization.localizedString("LASR")
        case .generic:
            return AppLocalization.localizedString("General MLX ASR")
        }
    }
}
