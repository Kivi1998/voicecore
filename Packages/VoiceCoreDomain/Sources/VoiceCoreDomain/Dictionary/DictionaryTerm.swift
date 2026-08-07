import Foundation

/// 词典词语。
///
/// 对应 `docs/DATA_MODEL.md` §4.4。`normalizedTerm` 为去除首尾空白并做
/// 大小写归一的结果，数据库对其建唯一索引；首版仅允许单个非空词语。
public struct DictionaryTerm: Identifiable, Codable, Sendable, Equatable {
    /// 单个词语最大长度（字符数）。
    public static let maxTermLength = 64

    public var id: UUID
    /// 原始词语（已去除首尾空白）。
    public var term: String
    /// 归一化结果，用于去重。
    public var normalizedTerm: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID, term: String, createdAt: Date, updatedAt: Date) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id
        self.term = trimmed
        normalizedTerm = DictionaryTerm.normalize(trimmed)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 输入规范化：去除首尾空白并做小写归一。
    public static func normalize(_ term: String) -> String {
        term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// 校验用户输入；返回 nil 表示合法，否则返回用户可读的拒绝原因。
    public static func validationError(for input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "词语不能为空"
        }
        if trimmed.count > maxTermLength {
            return "词语过长，最多 \(maxTermLength) 个字符"
        }
        return nil
    }
}
