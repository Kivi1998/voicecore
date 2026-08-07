import AppKit
import Foundation
import VoiceCoreDomain

/// NSPasteboard 剪贴板实现（PLAT-004 / CORE-005）。
///
/// - 快照覆盖全部条目与全部类型标识（文字、图片、文件等均可恢复）；
/// - 快照只驻留内存，绝不写入日志、数据库或网络；
/// - 恢复失败抛出可诊断错误，错误信息不包含剪贴板内容。
public final class SystemClipboardService: ClipboardService, @unchecked Sendable {
    private let lock = NSLock()

    public init() {}

    public func save() async -> ClipboardSnapshot {
        lock.withLock {
            let pasteboard = NSPasteboard.general
            guard let items = pasteboard.pasteboardItems else { return .empty }
            var snapshotItems: [ClipboardSnapshot.Item] = []
            for item in items {
                for type in item.types {
                    guard let data = item.data(forType: type) else { continue }
                    snapshotItems.append(ClipboardSnapshot.Item(
                        typeIdentifier: type.rawValue,
                        data: data
                    ))
                }
            }
            return ClipboardSnapshot(items: snapshotItems)
        }
    }

    public func writeText(_ text: String) async {
        lock.withLock {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
    }

    public func readText() async -> String? {
        lock.withLock {
            NSPasteboard.general.string(forType: .string)
        }
    }

    public func restore(_ snapshot: ClipboardSnapshot) async throws {
        try lock.withLock {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard !snapshot.items.isEmpty else { return }
            let item = NSPasteboardItem()
            for snapshotItem in snapshot.items {
                item.setData(snapshotItem.data, forType: NSPasteboard.PasteboardType(snapshotItem.typeIdentifier))
            }
            guard pasteboard.writeObjects([item]) else {
                throw DictationError(
                    category: .unknown,
                    userMessage: "恢复剪贴板失败，原内容可能已变更"
                )
            }
        }
    }
}
