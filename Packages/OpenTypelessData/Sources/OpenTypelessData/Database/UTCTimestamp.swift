import Foundation

/// UTC 时间编码。
///
/// 数据库存储使用 UTC RFC 3339 文本（含毫秒），展示层按本地时区格式化，
/// 与 `docs/DATA_MODEL.md` §1 一致。
public enum UTCTimestamp {
    /// 每次调用创建格式化器：ISO8601DateFormatter 非 Sendable，
    /// 不能以共享静态变量存在于 Swift 6 严格并发检查下。
    private static func makeFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }

    /// 编码为 UTC RFC 3339 字符串。
    public static func string(from date: Date) -> String {
        makeFormatter().string(from: date)
    }

    /// 解析 UTC RFC 3339 字符串；失败返回 nil。
    public static func date(from string: String) -> Date? {
        makeFormatter().date(from: string)
    }

    /// 当前 UTC 时间字符串。
    public static func now() -> String {
        string(from: Date())
    }
}
