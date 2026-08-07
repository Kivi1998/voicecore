@testable import OpenTypelessDomain
import XCTest

final class RecordingRelativePathTests: XCTestCase {
    func testValidPaths() {
        XCTAssertTrue(RecordingRelativePath.isValid("2026/08/06/abc.m4a"))
        XCTAssertTrue(RecordingRelativePath.isValid("a.m4a"))
    }

    func testRejectsTraversal() {
        XCTAssertFalse(RecordingRelativePath.isValid("../secret.m4a"))
        XCTAssertFalse(RecordingRelativePath.isValid("2026/../../etc/passwd"))
        XCTAssertFalse(RecordingRelativePath.isValid("./x.m4a"))
    }

    func testRejectsAbsoluteAndEmpty() {
        XCTAssertFalse(RecordingRelativePath.isValid("/tmp/x.m4a"))
        XCTAssertFalse(RecordingRelativePath.isValid("~/x.m4a"))
        XCTAssertFalse(RecordingRelativePath.isValid(""))
        XCTAssertFalse(RecordingRelativePath.isValid("2026//x.m4a"))
        XCTAssertFalse(RecordingRelativePath.isValid("2026/"))
    }

    func testMakeProducesDatePartitionedPath() throws {
        // 2026-08-06 UTC
        let date = Date(timeIntervalSince1970: 1_786_003_200)
        let id = try XCTUnwrap(UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"))
        let path = RecordingRelativePath.make(recordID: id, startedAt: date, fileExtension: "m4a")
        XCTAssertEqual(path, "2026/08/06/a1b2c3d4-e5f6-7890-abcd-ef1234567890.m4a")
        XCTAssertTrue(RecordingRelativePath.isValid(path))
    }
}

/// 验证平台协议可被纯 Swift 测试替身实现（PLAT-001 验收：
/// 协议可由测试替身及未来 iOS 实现，Core 不导入 AppKit/AVFoundation）。
final class PlatformContractTests: XCTestCase {
    struct FakePathService: PathService {
        var dataRoot: URL {
            URL(fileURLWithPath: "/tmp/opentypeless-test")
        }

        var recordingsRoot: URL {
            dataRoot.appendingPathComponent("recordings")
        }

        var tempRoot: URL {
            dataRoot.appendingPathComponent("temp")
        }

        var logsRoot: URL {
            dataRoot.appendingPathComponent("logs")
        }

        var backupsRoot: URL {
            dataRoot.appendingPathComponent("backups")
        }
    }

    final class FakeAudioCapture: AudioCapture, @unchecked Sendable {
        var events: AsyncStream<AudioCaptureEvent> {
            AsyncStream { $0.finish() }
        }

        private(set) var startedPath: String?
        func listInputDevices() async throws -> [AudioInputDevice] {
            [AudioInputDevice(id: "default", name: "内置麦克风", isSystemDefault: true)]
        }

        func start(deviceID _: String?, writingTo relativePath: String) async throws {
            startedPath = relativePath
        }

        func stop() async throws -> AudioCaptureResult {
            AudioCaptureResult(relativePath: startedPath ?? "", mimeType: "audio/mp4", durationMs: 100, sizeBytes: 1024)
        }

        func cancel() async {}
    }

    struct FakeShortcut: GlobalShortcut {
        var events: AsyncStream<Void> {
            AsyncStream { $0.finish() }
        }

        func register(_: ShortcutDescriptor) async throws {}
        func unregister() async {}
        func conflicts(with _: ShortcutDescriptor) async -> Bool {
            false
        }
    }

    struct FakeInjector: TextInjector {
        func insert(_: String) async throws {}
    }

    final class FakeClipboard: ClipboardService, @unchecked Sendable {
        private var text: String?
        func save() async -> ClipboardSnapshot {
            ClipboardSnapshot.empty
        }

        func writeText(_ text: String) async {
            self.text = text
        }

        func readText() async -> String? {
            text
        }

        func restore(_: ClipboardSnapshot) async throws {}
    }

    struct FakePermissions: PermissionService {
        func state(of _: PermissionKind) async -> PermissionState {
            .granted
        }

        func request(_: PermissionKind) async -> PermissionState {
            .granted
        }
    }

    struct FakeAutostart: AutostartService {
        func isEnabled() async -> Bool {
            false
        }

        func setEnabled(_: Bool) async throws {}
    }

    struct FakeMenuBar: MenuBarService {
        func update(_: MenuBarState) async {}
    }

    func testResolveRecordingUsesDefaultImplementation() throws {
        let service = FakePathService()
        let url = try service.resolveRecording(relativePath: "2026/08/06/a.m4a")
        XCTAssertEqual(url.path, "/tmp/opentypeless-test/recordings/2026/08/06/a.m4a")
    }

    func testResolveRecordingRejectsTraversal() {
        let service = FakePathService()
        XCTAssertThrowsError(try service.resolveRecording(relativePath: "../evil.m4a")) { error in
            guard let dictationError = error as? DictationError else {
                return XCTFail("应为 DictationError")
            }
            XCTAssertEqual(dictationError.category, .audioInvalid)
        }
    }

    func testDoublesAreUsable() async throws {
        let audio = FakeAudioCapture()
        _ = try await audio.listInputDevices()
        try await audio.start(deviceID: nil, writingTo: "2026/08/06/a.m4a")
        let result = try await audio.stop()
        XCTAssertEqual(result.durationMs, 100)

        let clipboard = FakeClipboard()
        await clipboard.writeText("文字")
        let text = await clipboard.readText()
        XCTAssertEqual(text, "文字")

        _ = await FakePermissions().state(of: .microphone)
        await FakeMenuBar().update(.idle)
        XCTAssertFalse(MenuBarState.idle.hasActiveSession)
    }
}
