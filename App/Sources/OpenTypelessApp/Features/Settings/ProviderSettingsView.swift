import OpenTypelessDomain
import SwiftUI

/// 模型配置页（SET-002/SET-003）：语音与改写两组配置，
/// 新增/编辑/启用/设为默认/测试连接/删除。
struct ProviderSettingsView: View {
    @StateObject private var viewModel: ProviderSettingsViewModel

    init(composition: AppComposition) {
        _viewModel = StateObject(wrappedValue: ProviderSettingsViewModel(composition: composition))
    }

    var body: some View {
        Form {
            speechSection
            rewriteSection
        }
        .formStyle(.grouped)
        .task {
            await viewModel.load()
        }
        .sheet(item: $viewModel.editingDraft) { draft in
            ProfileEditorSheet(draft: draft, viewModel: viewModel)
        }
    }

    private var speechSection: some View {
        Section {
            ForEach(viewModel.speechProfiles) { profile in
                profileRow(profile)
            }
            Button("新增语音模型…") {
                viewModel.beginAdd(purpose: .speech)
            }
        } header: {
            Text("语音识别")
        } footer: {
            Text("首版支持 OpenAI 兼容协议；千问也可通过 OpenAI 兼容方式配置，原生协议将在后续版本提供。")
                .font(DesignTokens.Font.caption)
        }
    }

    private var rewriteSection: some View {
        Section {
            Toggle("启用文字改写", isOn: Binding(
                get: { viewModel.rewriteEnabled },
                set: { value in Task { await viewModel.setRewriteEnabled(value) } }
            ))
            if viewModel.rewriteEnabled {
                ForEach(viewModel.rewriteProfiles) { profile in
                    profileRow(profile)
                }
                Button("新增改写模型…") {
                    viewModel.beginAdd(purpose: .rewrite)
                }
            }
        } header: {
            Text("文字改写")
        } footer: {
            Text("关闭改写时，语音识别原文将直接作为最终文字。")
                .font(DesignTokens.Font.caption)
        }
    }

    private func profileRow(_ profile: ProviderProfile) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text(profile.name)
                    if profile.isDefault {
                        Text("默认")
                            .font(DesignTokens.Font.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text("\(profile.modelName) · \(profile.baseURL)")
                    .font(DesignTokens.Font.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if !profile.isDefault {
                Button("设为默认") {
                    Task { await viewModel.setDefault(profile) }
                }
                .buttonStyle(.borderless)
            }
            Button(L10n.Common.edit) {
                viewModel.beginEdit(profile)
            }
            .buttonStyle(.borderless)
            Button(L10n.Common.delete, role: .destructive) {
                Task { await viewModel.delete(profile) }
            }
            .buttonStyle(.borderless)
        }
        .accessibilityElement(children: .contain)
    }
}

/// 配置编辑弹窗（密钥默认遮罩；留空保持原值）。
struct ProfileEditorSheet: View {
    @State var draft: ProfileDraft
    let viewModel: ProviderSettingsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            Text(draft.editingID == nil ? "新增配置" : "编辑配置")
                .font(DesignTokens.Font.headline)

            Form {
                TextField("名称", text: $draft.name, prompt: Text("例如：OpenAI Whisper"))
                protocolPicker
                TextField("基础地址", text: $draft.baseURL, prompt: Text("https://api.example.com/v1"))
                TextField("模型名", text: $draft.modelName, prompt: Text("例如：whisper-1"))
                SecureField("API 密钥", text: $draft.apiKeyInput, prompt: Text(secretPrompt))
                LabeledContent("超时（秒）", value: "\(Int(draft.timeoutSeconds))")
                Slider(value: $draft.timeoutSeconds, in: 10 ... 300, step: 10)
            }
            .formStyle(.grouped)

            if let result = viewModel.testResult {
                Label(result, systemImage: result.contains("成功") ? "checkmark.circle" : "exclamationmark.circle")
                    .font(DesignTokens.Font.callout)
                    .foregroundStyle(result.contains("成功") ? DesignTokens.Color.success : DesignTokens.Color.failure)
            }
            if let message = viewModel.statusMessage {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(DesignTokens.Font.callout)
                    .foregroundStyle(DesignTokens.Color.failure)
            }

            HStack {
                Button {
                    Task { await viewModel.testConnection() }
                } label: {
                    if viewModel.testingProfileID != nil {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("测试连接")
                    }
                }
                .disabled(viewModel.testingProfileID != nil)
                Spacer()
                Button(L10n.Common.cancel, role: .cancel) {
                    dismiss()
                }
                Button(L10n.Common.save) {
                    Task {
                        await viewModel.saveDraft()
                        if viewModel.statusMessage == nil {
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty
                    || draft.baseURL.trimmingCharacters(in: .whitespaces).isEmpty
                    || draft.modelName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(DesignTokens.Spacing.xxl)
        .frame(width: 480)
    }

    private var secretPrompt: String {
        draft.editingID == nil ? "粘贴密钥，保存后仅显示遮罩" : "留空保持原密钥不变"
    }

    @ViewBuilder
    private var protocolPicker: some View {
        if draft.purpose == .speech {
            LabeledContent("协议", value: "OpenAI 兼容音频转录")
        } else {
            Picker("协议", selection: $draft.protocolKind) {
                Text("OpenAI 兼容对话").tag(ProviderProtocolKind.openAIChat)
                Text("Anthropic Messages").tag(ProviderProtocolKind.anthropicMessages)
            }
        }
    }
}
