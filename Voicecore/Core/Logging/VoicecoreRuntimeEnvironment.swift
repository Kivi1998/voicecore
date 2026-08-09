// VoiceCoreRuntimeEnvironment.swift
// Provides runtime environment checks for logging behavior.

import Foundation

enum VoiceCoreRuntimeEnvironment {
    nonisolated static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
