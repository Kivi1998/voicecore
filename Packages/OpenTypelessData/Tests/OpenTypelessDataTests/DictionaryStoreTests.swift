import Foundation
@testable import OpenTypelessData
import OpenTypelessDomain
import XCTest

final class DictionaryStoreTests: XCTestCase {
    // XCTest 夹具属性的隐式解包可选值是 XCTest 官方惯例（setUpWithError 赋值）。
    // swiftlint:disable implicitly_unwrapped_optional
    private var tempDirectory: URL!
    private var store: DictionaryStore!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("opentypeless-dict-tests-\(UUID().uuidString)", isDirectory: true)
        let manager = try DatabaseManager(path: tempDirectory.appendingPathComponent("app.sqlite3").path)
        store = DictionaryStore(pool: manager.pool)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testAddTrimsWhitespace() async throws {
        let id = try await store.add(term: "  通义千问  ")
        let list = try await store.list(searchText: nil)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.id, id)
        XCTAssertEqual(list.first?.term, "通义千问")
    }

    func testDuplicateRejectedCaseInsensitive() async throws {
        _ = try await store.add(term: "OpenAI")
        do {
            _ = try await store.add(term: "  openai  ")
            XCTFail("归一化重复必须被拒绝")
        } catch let error as DictationError {
            XCTAssertEqual(error.userMessage, "词语已存在")
        }
    }

    func testEmptyAndTooLongRejected() async throws {
        await XCTAssertThrowsErrorAsync(try await store.add(term: "   "))
        let long = String(repeating: "字", count: DictionaryTerm.maxTermLength + 1)
        await XCTAssertThrowsErrorAsync(try await store.add(term: long))
    }

    func testSearchMatchesTermAndNormalized() async throws {
        _ = try await store.add(term: "DeepSeek")
        _ = try await store.add(term: "豆包")
        await XCTAssertEqualAsync(try await store.list(searchText: "deep").count, 1)
        await XCTAssertEqualAsync(try await store.list(searchText: "豆").count, 1)
        await XCTAssertEqualAsync(try await store.list(searchText: "不存在").count, 0)
        await XCTAssertEqualAsync(try await store.list(searchText: "  ").count, 2)
    }

    func testSearchEscapesWildcards() async throws {
        _ = try await store.add(term: "100%覆盖")
        _ = try await store.add(term: "100X普通")
        await XCTAssertEqualAsync(try await store.list(searchText: "100%").count, 1)
    }

    func testDelete() async throws {
        let id = try await store.add(term: "临时词")
        try await store.delete(id: id)
        await XCTAssertEqualAsync(try await store.list(searchText: nil).count, 0)
        // 删除不存在词语视为成功。
        try await store.delete(id: UUID())
    }

    func testAllTermStringsForPromptInjection() async throws {
        _ = try await store.add(term: "通义千问")
        _ = try await store.add(term: "Kimi")
        let terms = try await store.allTermStrings()
        XCTAssertEqual(Set(terms), ["通义千问", "Kimi"])
    }

    func testListOrderedByCreatedDesc() async throws {
        _ = try await store.add(term: "第一")
        try await Task.sleep(for: .milliseconds(5))
        _ = try await store.add(term: "第二")
        let list = try await store.list(searchText: nil)
        XCTAssertEqual(list.map(\.term), ["第二", "第一"])
    }
}
