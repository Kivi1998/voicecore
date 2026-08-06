import Foundation
import GRDB

/// 数据库迁移注册。
///
/// 规则（`docs/DATA_MODEL.md` §8）：
/// - 迁移标识为 `v0001_initial`、`v0002_add_xxx` 单调递增；
/// - 已发布迁移闭包不可修改，只能追加新迁移；
/// - 每个迁移在事务中执行；
/// - `publishedMigrationIdentifiers` 由快照测试锁定，防止已发布迁移被
///   重命名、删除或改变顺序。
public enum Migrations {
    /// 已发布迁移标识清单（快照测试基准）。
    public static let publishedMigrationIdentifiers: [String] = [
        "v0001_initial",
    ]

    /// 向迁移器注册全部迁移。
    public static func registerAll(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v0001_initial") { db in
            // 模型配置（docs/DATA_MODEL.md §4.3）。
            // timeout_seconds 来自 KIMI_PROMPT.md §2.5“模型配置至少包括…超时”
            // 的要求，专项数据文档未列出该列，按优先级规则补充。
            try db.create(table: "provider_profiles") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("purpose", .text).notNull()
                t.column("protocol", .text).notNull()
                t.column("base_url", .text).notNull()
                t.column("model_name", .text).notNull()
                // 首版明文保存；仅数据层专用写入方法可更新。
                t.column("api_key", .text)
                t.column("custom_headers_json", .text).notNull().defaults(to: "{}")
                t.column("options_json", .text).notNull().defaults(to: "{}")
                t.column("timeout_seconds", .double).notNull().defaults(to: 60)
                t.column("is_enabled", .integer).notNull().defaults(to: 1)
                t.column("is_default", .integer).notNull().defaults(to: 0)
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }
            try db.create(index: "idx_provider_profiles_purpose", on: "provider_profiles", columns: ["purpose"])

            // 口述记录（docs/DATA_MODEL.md §4.1）。
            try db.create(table: "dictation_records") { t in
                t.column("id", .text).primaryKey()
                t.column("status", .text).notNull()
                t.column("started_at", .text).notNull()
                t.column("stopped_at", .text)
                t.column("completed_at", .text)
                t.column("duration_ms", .integer).notNull().defaults(to: 0)
                // 相对录音根目录路径，不保存平台绝对路径。
                t.column("audio_rel_path", .text)
                t.column("audio_mime_type", .text)
                t.column("audio_size_bytes", .integer)
                t.column("audio_sha256", .text)
                t.column("raw_transcript", .text)
                t.column("final_text", .text)
                t.column("count_units", .integer).notNull().defaults(to: 0)
                t.column("detected_language", .text)
                t.column("is_favorite", .integer).notNull().defaults(to: 0)
                t.column("speech_profile_id", .text)
                    .references("provider_profiles", column: "id", onDelete: .setNull)
                t.column("rewrite_profile_id", .text)
                    .references("provider_profiles", column: "id", onDelete: .setNull)
                // 脱敏快照，不含密钥与鉴权头。
                t.column("speech_snapshot_json", .text).notNull()
                t.column("rewrite_snapshot_json", .text)
                t.column("last_error_category", .text)
                t.column("last_error_message", .text)
                t.column("retry_count", .integer).notNull().defaults(to: 0)
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }
            try db.create(index: "idx_records_started_at", on: "dictation_records", columns: ["started_at"])
            try db.create(index: "idx_records_status_started", on: "dictation_records", columns: ["status", "started_at"])
            try db.create(index: "idx_records_favorite_started", on: "dictation_records", columns: ["is_favorite", "started_at"])
            try db.create(index: "idx_records_speech_profile", on: "dictation_records", columns: ["speech_profile_id"])
            try db.create(index: "idx_records_rewrite_profile", on: "dictation_records", columns: ["rewrite_profile_id"])

            // 转录/改写/输入尝试（docs/DATA_MODEL.md §4.2）。
            try db.create(table: "record_attempts") { t in
                t.column("id", .text).primaryKey()
                t.column("record_id", .text).notNull()
                    .references("dictation_records", column: "id", onDelete: .cascade)
                t.column("stage", .text).notNull()
                t.column("attempt_no", .integer).notNull()
                t.column("provider_kind", .text)
                t.column("model_name", .text)
                t.column("started_at", .text).notNull()
                t.column("finished_at", .text)
                t.column("success", .integer)
                t.column("http_status", .integer)
                t.column("provider_request_id", .text)
                t.column("error_category", .text)
                t.column("error_message", .text)
                t.column("latency_ms", .integer)
            }
            try db.create(index: "idx_attempts_record", on: "record_attempts", columns: ["record_id", "stage", "attempt_no"])

            // 词典（docs/DATA_MODEL.md §4.4）。
            try db.create(table: "dictionary_terms") { t in
                t.column("id", .text).primaryKey()
                t.column("term", .text).notNull()
                t.column("normalized_term", .text).notNull()
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }
            try db.create(
                index: "idx_dictionary_terms_normalized",
                on: "dictionary_terms",
                columns: ["normalized_term"],
                unique: true
            )

            // 应用设置键值（docs/DATA_MODEL.md §4.5）；不保存秘密。
            try db.create(table: "app_settings") { t in
                t.column("key", .text).primaryKey()
                t.column("value_json", .text).notNull()
                t.column("updated_at", .text).notNull()
            }
        }
    }
}
