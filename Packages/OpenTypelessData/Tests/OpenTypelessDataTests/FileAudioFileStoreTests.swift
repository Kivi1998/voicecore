import Foundation
import XCTest

@testable import OpenTypelessData
import OpenTypelessDomain

final class FileAudioFileStoreTests: XCTestCase {
    private var tempDirectory: URL!
    private var store: FileAudioFileStore!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("opentypeless-audio-tests-\(UUID().uuidString)", isDirectory: true)
        store = FileAudioFileStore(recordingsRoot: tempDirectory.appendingPathComponent("recordings"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    private func makeDestination(id: UUID = UUID()) throws -> String {
        try store.prepareDestination(
            recordID: id,
            startedAt: Date(timeIntervalSince1970: 1_786_003_200),
            fileExtension: "m4a"
        )
    }

    func testPrepareDestinationUsesDatePartitionedUUIDPath() throws {
        let id = UUID()
        let path = try makeDestination(id: id)
        XCTAssertTrue(path.hasPrefix("2026/08/06/"))
        XCTAssertTrue(path.contains(id.uuidString.lowercased()))
        XCTAssertTrue(path.hasSuffix(".m4a"))
        XCTAssertFalse(path.contains("口述"), "文件名不得包含口述内容")
    }

    func testWriteFinalizeAndInfo() async throws {
        let path = try makeDestination()
        let writer = try store.openForWriting(relativePath: path)
        try writer.append(Data([0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70]))
        try writer.append(Data(repeating: 0xAB, count: 100))
        try writer.close()
        // close 幂等
        try writer.close()

        // finalize 前正式文件不存在，半成品存在。
        XCTAssertTrue(store.hasPartial(relativePath: path))
        XCTAssertFalse(try store.info(relativePath: path).exists)

        let info = try store.finalize(relativePath: path)
        XCTAssertTrue(info.exists)
        XCTAssertEqual(info.sizeBytes, 108)
        XCTAssertFalse(store.hasPartial(relativePath: path))
    }

    func testCrashLeavesPartialThatCanBeAdopted() throws {
        // 模拟异常退出：写入半成品但未 finalize。
        let path = try makeDestination()
        let writer = try store.openForWriting(relativePath: path)
        try writer.append(Data(repeating: 0x01, count: 64))
        try writer.close()

        XCTAssertTrue(store.hasPartial(relativePath: path))
        // 恢复：finalize 收养半成品。
        let info = try store.finalize(relativePath: path)
        XCTAssertTrue(info.exists)
        XCTAssertEqual(info.sizeBytes, 64)
    }

    func testFinalizeRejectsMissingFile() throws {
        let path = try makeDestination()
        XCTAssertThrowsError(try store.finalize(relativePath: path)) { error in
            guard let dictationError = error as? DictationError else {
                return XCTFail("应为 DictationError")
            }
            XCTAssertEqual(dictationError.category, .audioInvalid)
        }
    }

    func testDeleteRemovesBothFinalAndPartial() throws {
        let path = try makeDestination()
        let writer = try store.openForWriting(relativePath: path)
        try writer.append(Data(repeating: 0x02, count: 32))
        try writer.close()
        _ = try store.finalize(relativePath: path)

        XCTAssertTrue(try store.delete(relativePath: path))
        XCTAssertFalse(try store.info(relativePath: path).exists)
        // 重复删除视为成功（缺失由调用方记日志）。
        XCTAssertFalse(try store.delete(relativePath: path))
    }

    func testRejectsTraversalPaths() throws {
        XCTAssertThrowsError(try store.openForWriting(relativePath: "../evil.m4a"))
        XCTAssertThrowsError(try store.delete(relativePath: "/etc/passwd"))
        XCTAssertThrowsError(try store.info(relativePath: "..%2Fsecret"))
        XCTAssertFalse(store.hasPartial(relativePath: "../evil.m4a"))
    }

    func testListAndTotalSize() throws {
        let pathA = try makeDestination()
        let writerA = try store.openForWriting(relativePath: pathA)
        try writerA.append(Data(repeating: 0x03, count: 10))
        try writerA.close()
        _ = try store.finalize(relativePath: pathA)

        let pathB = try store.prepareDestination(
            recordID: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_786_089_600),
            fileExtension: "m4a"
        )
        let writerB = try store.openForWriting(relativePath: pathB)
        try writerB.append(Data(repeating: 0x04, count: 20))
        try writerB.close()
        // pathB 保持半成品状态。

        let listed = try store.listRecordingRelativePaths()
        XCTAssertEqual(listed, [pathA], "半成品不得出现在正式录音列表")
        XCTAssertEqual(try store.totalSizeBytes(), 30, "占用统计包含半成品")
    }

    func testAppendAfterCloseThrows() throws {
        let path = try makeDestination()
        let writer = try store.openForWriting(relativePath: path)
        try writer.close()
        XCTAssertThrowsError(try writer.append(Data([0x00])))
    }

    func testReopenDiscardsStalePartial() throws {
        let path = try makeDestination()
        let first = try store.openForWriting(relativePath: path)
        try first.append(Data(repeating: 0x05, count: 50))
        try first.close()
        // 同记录重新开始：旧半成品被清理，不追加到旧内容。
        let second = try store.openForWriting(relativePath: path)
        try second.append(Data(repeating: 0x06, count: 8))
        try second.close()
        let info = try store.finalize(relativePath: path)
        XCTAssertEqual(info.sizeBytes, 8)
    }
}
