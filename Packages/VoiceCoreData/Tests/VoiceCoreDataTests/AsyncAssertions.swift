import XCTest

/// async 断言辅助（TEST-001）。
///
/// XCTest 自带断言的自动闭包不支持 concurrency，异步表达式（如
/// `await store.get(...)`）不能直接作为断言参数。以下辅助提供
/// async 自动闭包版本；命名在 XCTest 原断言后加 `Async` 后缀。
func XCTAssertEqualAsync<T: Equatable>(
    _ expression: @autoclosure () async throws -> T,
    _ expected: @autoclosure () async throws -> T,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        let actual = try await expression()
        let expectedValue = try await expected()
        XCTAssertEqual(actual, expectedValue, message, file: file, line: line)
    } catch {
        XCTFail("断言取值抛出错误：\(error)", file: file, line: line)
    }
}

func XCTAssertNilAsync(
    _ expression: @autoclosure () async throws -> (some Any)?,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        let actual = try await expression()
        XCTAssertNil(actual, message, file: file, line: line)
    } catch {
        XCTFail("断言取值抛出错误：\(error)", file: file, line: line)
    }
}

func XCTAssertNotNilAsync(
    _ expression: @autoclosure () async throws -> (some Any)?,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        let actual = try await expression()
        XCTAssertNotNil(actual, message, file: file, line: line)
    } catch {
        XCTFail("断言取值抛出错误：\(error)", file: file, line: line)
    }
}

func XCTAssertTrueAsync(
    _ expression: @autoclosure () async throws -> Bool,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        let actual = try await expression()
        XCTAssertTrue(actual, message, file: file, line: line)
    } catch {
        XCTFail("断言取值抛出错误：\(error)", file: file, line: line)
    }
}

func XCTAssertFalseAsync(
    _ expression: @autoclosure () async throws -> Bool,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        let actual = try await expression()
        XCTAssertFalse(actual, message, file: file, line: line)
    } catch {
        XCTFail("断言取值抛出错误：\(error)", file: file, line: line)
    }
}

func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> some Any,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (_ error: any Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail(message.isEmpty ? "预期抛出错误但未抛出" : message, file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
