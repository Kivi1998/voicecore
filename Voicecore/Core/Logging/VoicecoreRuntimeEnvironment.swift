// VoicecoreRuntimeEnvironment.swift
// Provides runtime environment checks for logging behavior.

import Foundation

enum VoicecoreRuntimeEnvironment {
    nonisolated static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
