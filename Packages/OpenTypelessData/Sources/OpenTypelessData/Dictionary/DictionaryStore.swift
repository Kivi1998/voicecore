import Foundation
import GRDB
import OpenTypelessDomain

/// `dictionary_terms` 行映射。
struct DBDictionaryTerm: Codable, TableRecord, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "dictionary_terms"

    var id: String
    var term: String
    var normalizedTerm: String
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, term
        case normalizedTerm = "normalized_term"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

extension DBDictionaryTerm {
    init(domain term: DictionaryTerm) {
        id = term.id.uuidString.lowercased()
        self.term = term.term
        normalizedTerm = term.normalizedTerm
        createdAt = UTCTimestamp.string(from: term.createdAt)
        updatedAt = UTCTimestamp.string(from: term.updatedAt)
    }

    func toDomain() throws -> DictionaryTerm {
        guard let termID = UUID(uuidString: id),
              let created = UTCTimestamp.date(from: createdAt),
              let updated = UTCTimestamp.date(from: updatedAt)
        else {
            throw DictationError(category: .unknown, userMessage: "词典数据损坏", isRetryable: false)
        }
        return DictionaryTerm(id: termID, term: term, createdAt: created, updatedAt: updated)
    }
}

/// 词典仓储的 GRDB 实现。
public struct DictionaryStore: DictionaryRepository {
    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    public func add(term: String) async throws -> UUID {
        if let message = DictionaryTerm.validationError(for: term) {
            throw DictationError(
                category: .configurationInvalid,
                userMessage: message,
                isRetryable: false
            )
        }
        let now = Date()
        let term2 = DictionaryTerm(id: UUID(), term: term, createdAt: now, updatedAt: now)
        let row = DBDictionaryTerm(domain: term2)
        do {
            try await pool.write { db in
                // 先查重给出友好提示，再依赖唯一索引兜底并发场景。
                let exists = try DBDictionaryTerm
                    .filter(Column("normalized_term") == row.normalizedTerm)
                    .fetchCount(db) > 0
                if exists {
                    throw DictationError(
                        category: .configurationInvalid,
                        userMessage: "词语已存在",
                        isRetryable: false
                    )
                }
                try row.insert(db)
            }
        } catch let error as DatabaseError {
            // 并发下唯一索引兜底。
            if error.resultCode == .SQLITE_CONSTRAINT {
                throw DictationError(
                    category: .configurationInvalid,
                    userMessage: "词语已存在",
                    isRetryable: false
                )
            }
            throw error
        }
        return term2.id
    }

    public func list(searchText: String?) async throws -> [DictionaryTerm] {
        try await pool.read { db in
            var request = DBDictionaryTerm.all()
            if let search = searchText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !search.isEmpty
            {
                let pattern = "%\(DictationRecordStore.escapeLike(search))%"
                request = request.filter(
                    Column("term").like(pattern, escape: "\\")
                        || Column("normalized_term").like(pattern, escape: "\\")
                )
            }
            return try request
                .order(Column("created_at").desc, Column("id").desc)
                .fetchAll(db)
                .map { try $0.toDomain() }
        }
    }

    public func delete(id: UUID) async throws {
        let key = id.uuidString.lowercased()
        try await pool.write { db in
            _ = try DBDictionaryTerm.deleteOne(db, key: key)
        }
    }

    public func allTermStrings() async throws -> [String] {
        try await pool.read { db in
            try DBDictionaryTerm
                .order(Column("created_at"))
                .fetchAll(db)
                .map(\.term)
        }
    }
}
