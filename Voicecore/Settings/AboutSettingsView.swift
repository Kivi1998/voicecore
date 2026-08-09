// AboutSettingsView.swift
// Provides About Settings View for settings screens.

import SwiftUI

private func localized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

private func localizedKey(_ key: String) -> LocalizedStringKey {
    LocalizedStringKey(localized(key))
}

struct AboutSettingsView: View {
    let appUpdateManager: AppUpdateManager
    let navigationRequest: SettingsNavigationRequest?
    @AppStorage(AppPreferenceKey.betaUpdatesEnabled) private var betaUpdatesEnabled = false

    private var appVersionText: String {
        let bundle = Bundle.main
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        if let shortVersion, let buildVersion, !buildVersion.isEmpty {
            return "\(shortVersion) (\(buildVersion))"
        }
        if let shortVersion, !shortVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return shortVersion
        }
        if let buildVersion, !buildVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return buildVersion
        }
        return localized("Version metadata missing")
    }

    private var isBetaVersion: Bool {
        let bundle = Bundle.main
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let buildVersion = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let lowercasedVersionMetadata = "\(shortVersion) \(buildVersion)".lowercased()
        if lowercasedVersionMetadata.contains("beta") {
            return true
        }

        let versionComponents = shortVersion
            .split(separator: ".")
            .compactMap { Int($0) }
        guard versionComponents.count == 3,
              let major = versionComponents[safe: 0],
              let minor = versionComponents[safe: 1],
              let patch = versionComponents[safe: 2],
              let buildNumber = Int(buildVersion)
        else {
            return false
        }

        let releaseBuildBase = major * 100_000_000 + minor * 100_000 + patch * 100
        let releaseBuildSuffix = buildNumber - releaseBuildBase
        return (1...98).contains(releaseBuildSuffix)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(localizedKey("Version"))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary.opacity(0.92))
                        HStack(spacing: 8) {
                            Text(appVersionText)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)

                            if isBetaVersion {
                                Text(localizedKey("Beta"))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(Color.accentColor.opacity(0.11))
                                    )
                            }
                        }
                    }

                    Spacer(minLength: 0)

                    Button(localized("Check for Updates")) {
                            appUpdateManager.checkForUpdatesWithUserInterface()
                    }
                    .disabled(appUpdateManager.shouldDisableInteractiveUpdateTrigger)
                    .buttonStyle(SettingsPillButtonStyle())
                }

                GeneralToggleRow(
                    title: localizedKey("Beta Updates"),
                    description: localizedKey("Check beta appcast updates when VoiceCore checks for app updates."),
                    isOn: $betaUpdatesEnabled
                )
                .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingsNavigationAnchor(.aboutVoiceCore)
        }
        .onChange(of: betaUpdatesEnabled) { _, _ in
            appUpdateManager.betaUpdatesPreferenceDidChange()
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
