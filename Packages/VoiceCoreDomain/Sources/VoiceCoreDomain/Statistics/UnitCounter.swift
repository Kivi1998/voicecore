import Foundation

/// 统计计数规则（`docs/DATA_MODEL.md` §6）。
///
/// - 中文、日文、韩文字符逐字计数；
/// - 连续的拉丁字母或数字组成一个词，计一个单位；
/// - Emoji、纯标点、空白不计。
public enum UnitCounter {
    /// 统计给定文字的单位数。
    public static func count(_ text: String) -> Int64 {
        var units: Int64 = 0
        var inLatinWord = false

        for scalar in text.unicodeScalars {
            if isCJK(scalar) {
                units += 1
                inLatinWord = false
            } else if isLatinWordScalar(scalar) {
                if !inLatinWord {
                    units += 1
                    inLatinWord = true
                }
            } else {
                // 空白、标点、Emoji 与其他符号：不计数并打断英文单词。
                inLatinWord = false
            }
        }
        return units
    }

    /// 中日韩表意文字与音节文字范围。
    static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x4E00 ... 0x9FFF, // CJK 统一表意文字
             0x3400 ... 0x4DBF, // 扩展 A
             0x20000 ... 0x2A6DF, // 扩展 B
             0x2A700 ... 0x2EBEF, // 扩展 C–F
             0xF900 ... 0xFAFF, // 兼容表意文字
             0x3040 ... 0x309F, // 平假名
             0x30A0 ... 0x30FF, // 片假名
             0xAC00 ... 0xD7AF: // 韩文音节
            true
        default:
            false
        }
    }

    /// 拉丁字母或数字（含带附加符号的拉丁字母）。
    static func isLatinWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x30 ... 0x39, // 0-9
             0x41 ... 0x5A, // A-Z
             0x61 ... 0x7A, // a-z
             0xC0 ... 0x24F, // 拉丁字母扩展
             0x1E00 ... 0x1EFF: // 拉丁字母扩展附加
            true
        default:
            false
        }
    }
}
