// RecordingStartPlanner.swift
// Provides Recording Start Planner for recording session routing.

import Foundation

enum RecordingStartDecision: Equatable {
    case start(TranscriptionEngine)
}

enum RecordingStartPlanner {
    static func resolve(selectedEngine: TranscriptionEngine) -> RecordingStartDecision {
        .start(selectedEngine)
    }
}
