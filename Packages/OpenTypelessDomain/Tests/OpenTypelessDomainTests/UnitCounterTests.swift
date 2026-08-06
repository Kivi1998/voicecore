import XCTest
@testable import OpenTypelessDomain

/// 中英混合计数规则测试（CORE-006 验收：中文按字、英文按词、标点空白不计）。
final class UnitCounterTests: XCTestCase {
    func testChineseCountsPerCharacter() {
        XCTAssertEqual(UnitCounter.count("你好世界"), 4)
        XCTAssertEqual(UnitCounter.count("今天天气怎么样"), 7)
    }

    func testEnglishCountsPerWord() {
        XCTAssertEqual(UnitCounter.count("hello"), 1)
        XCTAssertEqual(UnitCounter.count("hello world"), 2)
        XCTAssertEqual(UnitCounter.count("open source software"), 3)
    }

    func testMixedChineseAndEnglish() {
        // 4 个汉字 + 1 个英文词。
        XCTAssertEqual(UnitCounter.count("你好世界hello"), 5)
        // 3 个汉字 + 2 个英文词。
        XCTAssertEqual(UnitCounter.count("使用 Xcode 开发 app"), 3 + 2)
    }

    func testNumbersCountAsWords() {
        XCTAssertEqual(UnitCounter.count("2026"), 1)
        XCTAssertEqual(UnitCounter.count("版本 3.5 发布"), 4) // 2 汉字 + "3" + "5"
    }

    func testPunctuationAndWhitespaceDoNotCount() {
        XCTAssertEqual(UnitCounter.count("，。！？、；："), 0)
        XCTAssertEqual(UnitCounter.count("   \n\t  "), 0)
        // 标点打断英文单词。
        XCTAssertEqual(UnitCounter.count("hello,world"), 2)
        XCTAssertEqual(UnitCounter.count("你好，世界。"), 4)
    }

    func testEmojiDoesNotCountAndBreaksWords() {
        XCTAssertEqual(UnitCounter.count("😀🎉"), 0)
        XCTAssertEqual(UnitCounter.count("你好😀world"), 3)
        XCTAssertEqual(UnitCounter.count("ab😀cd"), 2)
    }

    func testEmptyStringCountsZero() {
        XCTAssertEqual(UnitCounter.count(""), 0)
    }

    func testKanaAndHangulCountPerCharacter() {
        XCTAssertEqual(UnitCounter.count("こんにちは"), 5)
        XCTAssertEqual(UnitCounter.count("한국어"), 3)
    }
}
