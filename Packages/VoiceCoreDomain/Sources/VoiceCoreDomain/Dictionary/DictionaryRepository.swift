import Foundation

/// 词典仓储协议。
///
/// 首版仅允许单个非空词语的手动增删查；不做自动学习、批量导入和替换规则。
public protocol DictionaryRepository: Sendable {
    /// 添加词语；输入经过去首尾空白与归一化，重复（归一化后相同）抛出错误。
    /// - Returns: 新词语标识。
    func add(term: String) async throws -> UUID

    /// 列出词语，按创建时间倒序；可选搜索（匹配原始词与归一化词）。
    func list(searchText: String?) async throws -> [DictionaryTerm]

    /// 删除词语。
    func delete(id: UUID) async throws

    /// 全部词语文本（用于语音提示与改写纠错上下文注入）。
    func allTermStrings() async throws -> [String]
}
