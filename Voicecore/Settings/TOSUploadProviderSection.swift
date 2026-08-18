// TOSUploadProviderSection.swift
// Provides TOS Upload Provider Section for settings screens.

import SwiftUI

struct RemoteProviderTOSUploadSection: View {
    @Binding var bucket: String
    @Binding var region: String
    @Binding var endpoint: String
    var accessKeyInput: Binding<String>
    var secretKeyInput: Binding<String>
    let showsAccessKeyClear: Bool
    let showsSecretKeyClear: Bool
    let onClearAccessKey: () -> Void
    let onClearSecretKey: () -> Void

    @State private var isTesting = false
    @State private var resultMessage: String?
    @State private var resultIsSuccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLocalization.localizedString("TOS Upload Settings"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(AppLocalization.localizedString("Doubao's servers can't read a file straight off your Mac, so the non-realtime 2.0 model needs a link to fetch the audio from. This app uploads each recording to a Volcengine TOS (object storage) bucket that you own, hands Doubao a temporary link to it, and lets the file expire from TOS on its own afterward. Fill in your own bucket's details below; if you'd rather not set this up, switch the non-realtime model above to 1.0, which doesn't need TOS."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.localizedString("Bucket Name"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField(AppLocalization.localizedString("e.g. voicecore-asr-audio"), text: $bucket)
                    .textFieldStyle(.plain)
                    .settingsFieldSurface(minHeight: 34)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.localizedString("Region"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("cn-beijing", text: $region)
                    .textFieldStyle(.plain)
                    .settingsFieldSurface(minHeight: 34)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.localizedString("Endpoint"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("tos-cn-beijing.volces.com", text: $endpoint)
                    .textFieldStyle(.plain)
                    .settingsFieldSurface(minHeight: 34)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.localizedString("Access Key"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    SecureField(AppLocalization.localizedString("Paste access key"), text: accessKeyInput)
                        .textFieldStyle(.plain)
                        .settingsFieldSurface(minHeight: 34)
                    if showsAccessKeyClear {
                        Button(AppLocalization.localizedString("Clear"), action: onClearAccessKey)
                            .buttonStyle(SettingsPillButtonStyle(horizontalPadding: 10, height: 30))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.localizedString("Secret Key"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    SecureField(AppLocalization.localizedString("Paste secret key"), text: secretKeyInput)
                        .textFieldStyle(.plain)
                        .settingsFieldSurface(minHeight: 34)
                    if showsSecretKeyClear {
                        Button(AppLocalization.localizedString("Clear"), action: onClearSecretKey)
                            .buttonStyle(SettingsPillButtonStyle(horizontalPadding: 10, height: 30))
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    runTest()
                } label: {
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(AppLocalization.localizedString("Test"))
                    }
                }
                .buttonStyle(SettingsPillButtonStyle(horizontalPadding: 14, height: 30))
                .disabled(isTesting)

                Spacer()
            }

            if let resultMessage, !resultMessage.isEmpty {
                Text(resultMessage)
                    .font(.caption)
                    .foregroundStyle(resultIsSuccess ? .green : .orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func runTest() {
        isTesting = true
        resultMessage = nil
        let bucketValue = bucket
        let regionValue = region
        let accessKeyValue = accessKeyInput.wrappedValue
        let secretKeyValue = secretKeyInput.wrappedValue
        Task {
            do {
                let message = try await TOSUploadConnectivityTester.test(
                    bucket: bucketValue,
                    region: regionValue,
                    accessKey: accessKeyValue,
                    secretKey: secretKeyValue
                )
                await MainActor.run {
                    isTesting = false
                    resultIsSuccess = true
                    resultMessage = message
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    resultIsSuccess = false
                    resultMessage = error.localizedDescription
                }
            }
        }
    }
}
