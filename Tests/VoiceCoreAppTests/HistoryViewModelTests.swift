import Foundation
@testable import VoiceCoreApp
import VoiceCoreDomain
import XCTest

/// TEST-002：历史页面视图模型的加载、筛选、收藏和删除路径。
final class HistoryViewModelTests: XCTestCase {
    @MainActor
    func testReloadLoadsRecordsAndGroupsThemByDay() async throws {
        let fixture = try Fixture()
        defer { fixture.removeData() }
        let first = makeRecord(text: "第一条", startedAt: Date(timeIntervalSince1970: 1_786_080_000))
        let second = makeRecord(text: "第二条", startedAt: first.startedAt.addingTimeInterval(-86400))
        try await fixture.composition.records.create(first)
        try await fixture.composition.records.create(second)

        let viewModel = HistoryViewModel(composition: fixture.composition)
        await viewModel.reload()

        XCTAssertEqual(viewModel.records.map(\.id), [first.id, second.id])
        XCTAssertEqual(viewModel.groupedByDay.count, 2)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testReloadAppliesSearchAndStatusFilters() async throws {
        let fixture = try Fixture()
        defer { fixture.removeData() }
        let completed = makeRecord(text: "命中关键词", status: .completed)
        let failed = makeRecord(text: "其他文字", status: .rewriteFailed)
        try await fixture.composition.records.create(completed)
        try await fixture.composition.records.create(failed)

        let viewModel = HistoryViewModel(composition: fixture.composition)
        viewModel.searchText = "关键词"
        viewModel.statusFilter = .success
        await viewModel.reload()

        XCTAssertEqual(viewModel.records.map(\.id), [completed.id])
        XCTAssertFalse(viewModel.hasMore)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testFavoriteThenDeleteUpdatesPublishedStateAndRepository() async throws {
        let fixture = try Fixture()
        defer { fixture.removeData() }
        let record = makeRecord(text: "待操作记录")
        try await fixture.composition.records.create(record)

        let viewModel = HistoryViewModel(composition: fixture.composition)
        await viewModel.reload()
        await viewModel.toggleFavorite(record)

        XCTAssertEqual(viewModel.records.first?.isFavorite, true)
        XCTAssertEqual(viewModel.toastMessage?.text, L10n.Action.favorited)
        let storedAfterFavorite = try await fixture.composition.records.get(id: record.id)
        XCTAssertEqual(storedAfterFavorite?.isFavorite, true)

        guard let updated = viewModel.records.first else {
            return XCTFail("收藏后记录不应消失")
        }
        viewModel.confirmDeletion(updated)
        XCTAssertEqual(viewModel.recordPendingDeletion?.id, record.id)
        await viewModel.deletePending()

        XCTAssertTrue(viewModel.records.isEmpty)
        XCTAssertNil(viewModel.recordPendingDeletion)
        let storedAfterDeletion = try await fixture.composition.records.get(id: record.id)
        XCTAssertNil(storedAfterDeletion)
    }

    @MainActor
    private func makeRecord(
        text: String,
        status: DictationStatus = .completed,
        startedAt: Date = Date(timeIntervalSince1970: 1_786_080_000)
    ) -> DictationRecord {
        let snapshot = ProviderProfileSnapshot(
            profileID: nil,
            name: "测试模型",
            protocolKind: .openAIAudioTranscription,
            baseURL: "https://example.invalid/v1",
            modelName: "test-model"
        )
        return DictationRecord(
            id: UUID(),
            status: status,
            startedAt: startedAt,
            stoppedAt: startedAt.addingTimeInterval(1),
            completedAt: status == .completed ? startedAt.addingTimeInterval(2) : nil,
            rawTranscript: text,
            finalText: status == .completed ? text : nil,
            countUnits: Int64(text.count),
            speechSnapshot: snapshot,
            lastErrorMessage: status == .rewriteFailed ? "模拟失败" : nil,
            createdAt: startedAt,
            updatedAt: startedAt
        )
    }
}

@MainActor
private final class Fixture {
    let composition: AppComposition
    private let dataRoot: URL

    init() throws {
        composition = try AppComposition(bundleIdentifier: "dev.voicecore.app.tests.\(UUID().uuidString)")
        dataRoot = composition.paths.dataRoot
    }

    func removeData() {
        try? FileManager.default.removeItem(at: dataRoot)
    }
}
