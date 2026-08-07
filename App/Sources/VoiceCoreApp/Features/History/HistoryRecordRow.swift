import SwiftUI
import VoiceCoreDomain

/// 历史记录行：摘要＋展开详情与操作（HIST-003/004）。
struct HistoryRecordRow: View {
    let record: DictationRecord
    let isExpanded: Bool
    let onToggle: () -> Void
    let actions: HistoryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Button(action: onToggle) {
                HStack(alignment: .firstTextBaseline) {
                    Text(record.startedAt, format: .dateTime.hour().minute())
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .leading)
                    Text(record.finalText ?? record.rawTranscript ?? "（无文字）")
                        .lineLimit(isExpanded ? nil : 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if record.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .accessibilityLabel(L10n.Action.favorited)
                    }
                    RecordStatusBadge(status: record.status)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("history.record.toggle.\(record.id.uuidString)")

            if isExpanded {
                detail
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
        .accessibilityElement(children: .contain)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            if let failureStage = RecordStatusText.failureStageText(for: record.status) {
                Label(
                    "\(failureStage)失败：\(record.lastErrorMessage ?? "未知原因")",
                    systemImage: "exclamationmark.circle"
                )
                .font(DesignTokens.Font.callout)
                .foregroundStyle(DesignTokens.Color.failure)
            }
            if let raw = record.rawTranscript, raw != record.finalText {
                LabeledContent("原始文字") {
                    Text(raw).textSelection(.enabled)
                }
            }
            if let final = record.finalText {
                LabeledContent("最终文字") {
                    Text(final).textSelection(.enabled)
                }
            }
            LabeledContent("语音模型", value: record.speechSnapshot.name)
            if let rewrite = record.rewriteSnapshot {
                LabeledContent("改写模型", value: rewrite.name)
            }
            if record.durationMs > 0 {
                LabeledContent("时长", value: String(format: "%.1f 秒", Double(record.durationMs) / 1000))
            }

            actionBar
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 56)
    }

    private var actionBar: some View {
        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(minimum: 104),
                    spacing: DesignTokens.Spacing.md,
                    alignment: .leading
                )
            ],
            alignment: .leading,
            spacing: DesignTokens.Spacing.sm
        ) {
            Button {
                Task { await actions.copyText(record) }
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            .disabled(record.finalText == nil && record.rawTranscript == nil)

            Button {
                actions.playAudio(record)
            } label: {
                Label("播放", systemImage: "play.circle")
            }
            .disabled(record.audioRelativePath == nil)

            Button {
                Task { await actions.downloadAudio(record) }
            } label: {
                Label("下载", systemImage: "arrow.down.circle")
            }
            .disabled(record.audioRelativePath == nil)

            Button {
                Task { await actions.toggleFavorite(record) }
            } label: {
                Label(
                    record.isFavorite ? "取消收藏" : "收藏",
                    systemImage: record.isFavorite ? "star.fill" : "star"
                )
            }

            if let retryTitle {
                Button {
                    Task { await actions.retry(record) }
                } label: {
                    Label(retryTitle, systemImage: "arrow.clockwise")
                }
            }

            Button(role: .destructive) {
                actions.confirmDeletion(record)
            } label: {
                Label(L10n.Common.delete, systemImage: "trash")
            }
            .accessibilityIdentifier("history.record.delete.\(record.id.uuidString)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(DesignTokens.Font.callout)
        .buttonStyle(.borderless)
    }

    /// 失败阶段的就近重试文案（HIST-004：改写失败不重复上传音频）。
    private var retryTitle: String? {
        switch record.status {
        case .transcriptionFailed: L10n.Action.retryTranscription
        case .rewriteFailed: L10n.Action.retryRewriteOnly
        case .injectionFailed: L10n.Action.retryInjection
        default: nil
        }
    }
}
