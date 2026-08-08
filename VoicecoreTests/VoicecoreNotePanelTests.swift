// VoicecoreNotePanelTests.swift
// Covers the note panel geometry and corner hover state machine.

import XCTest
import UniformTypeIdentifiers
@testable import Voicecore

final class VoicecoreNoteDragPayloadTests: XCTestCase {
    func testDragPayloadExportsPlainTextAcceptedByTextInputs() {
        let provider = VoicecoreNoteDragPayload(text: "  Paste this note  ").itemProvider()
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.text.identifier))
        XCTAssertTrue(provider.canLoadObject(ofClass: NSString.self))

        let loaded = expectation(description: "Plain-text note drag representation loads")
        provider.loadDataRepresentation(
            forTypeIdentifier: UTType.utf8PlainText.identifier
        ) { data, error in
            XCTAssertNil(error)
            XCTAssertEqual(data, Data("Paste this note".utf8))
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 1)
    }

    func testDragPayloadCarriesNoteIdentityForInternalReordering() {
        let noteID = UUID()
        let provider = VoicecoreNoteDragPayload(text: "Reorder me", noteID: noteID).itemProvider()

        XCTAssertEqual(provider.suggestedName, noteID.uuidString)
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier))
    }
}

final class VoicecoreNoteCompletedPaginationTests: XCTestCase {
    func testCompletedItemsStartAtFiveAndLoadTenAtATime() {
        XCTAssertEqual(VoicecoreNoteCompletedPagination.initialLimit, 5)
        XCTAssertEqual(VoicecoreNoteCompletedPagination.visibleCount(totalCount: 35, limit: 5), 5)
        XCTAssertEqual(VoicecoreNoteCompletedPagination.nextLimit(currentLimit: 5, totalCount: 35), 15)
        XCTAssertEqual(VoicecoreNoteCompletedPagination.nextLimit(currentLimit: 15, totalCount: 35), 25)
        XCTAssertEqual(VoicecoreNoteCompletedPagination.nextLimit(currentLimit: 25, totalCount: 35), 35)
    }

    func testCompletedPaginationDoesNotExceedAvailableItems() {
        XCTAssertEqual(VoicecoreNoteCompletedPagination.nextLimit(currentLimit: 5, totalCount: 11), 11)
        XCTAssertEqual(VoicecoreNoteCompletedPagination.nextLimit(currentLimit: 15, totalCount: 11), 15)
        XCTAssertEqual(VoicecoreNoteCompletedPagination.visibleCount(totalCount: 4, limit: 11), 4)
    }
}

final class VoicecoreNotePanelGeometryTests: XCTestCase {
    func testHotspotsOccupyExactScreenCorners() {
        let frame = CGRect(x: -1_440, y: 0, width: 1_440, height: 900)

        XCTAssertEqual(
            VoicecoreNotePanelGeometry.hotspot(in: frame, corner: .topLeft),
            CGRect(x: -1_440, y: 884, width: 16, height: 16)
        )
        XCTAssertEqual(
            VoicecoreNotePanelGeometry.hotspot(in: frame, corner: .bottomRight),
            CGRect(x: -16, y: 0, width: 16, height: 16)
        )
    }

    func testPanelAnchorsInsideVisibleFrame() {
        let frame = CGRect(x: 0, y: 25, width: 1_920, height: 1_030)
        let size = CGSize(width: 332, height: 400)

        XCTAssertEqual(
            VoicecoreNotePanelGeometry.panelFrame(in: frame, size: size, corner: .topRight),
            CGRect(x: 1_576, y: 643, width: 332, height: 400)
        )
        XCTAssertEqual(
            VoicecoreNotePanelGeometry.panelFrame(in: frame, size: size, corner: .bottomLeft),
            CGRect(x: 12, y: 37, width: 332, height: 400)
        )
    }

    func testPreferredHeightIsClamped() {
        XCTAssertEqual(
            VoicecoreNotePanelGeometry.preferredHeight(itemCount: 0, sectionCount: 0),
            VoicecoreNotePanelGeometry.minimumHeight
        )
        XCTAssertEqual(
            VoicecoreNotePanelGeometry.preferredHeight(itemCount: 100, sectionCount: 3),
            VoicecoreNotePanelGeometry.maximumHeight
        )
    }
}

final class VoicecoreNoteCornerHoverStateMachineTests: XCTestCase {
    func testRevealAndHideRespectConfiguredDelays() {
        var machine = VoicecoreNoteCornerHoverStateMachine()

        XCTAssertEqual(machine.update(
            at: 10,
            isInHotspot: true,
            isInPanel: false,
            isInteractionLocked: false,
            revealDelay: 0.5,
            hideDelay: 0.3
        ), .none)
        XCTAssertEqual(machine.update(
            at: 10.5,
            isInHotspot: true,
            isInPanel: false,
            isInteractionLocked: false,
            revealDelay: 0.5,
            hideDelay: 0.3
        ), .reveal)
        XCTAssertEqual(machine.update(
            at: 11.31,
            isInHotspot: false,
            isInPanel: false,
            isInteractionLocked: false,
            revealDelay: 0.5,
            hideDelay: 0.3
        ), .none)
        XCTAssertEqual(machine.update(
            at: 11.62,
            isInHotspot: false,
            isInPanel: false,
            isInteractionLocked: false,
            revealDelay: 0.5,
            hideDelay: 0.3
        ), .hide)
    }

    func testInteractionLockKeepsPanelVisible() {
        var machine = VoicecoreNoteCornerHoverStateMachine()
        machine.forceVisible(at: 0, grace: 0)

        XCTAssertEqual(machine.update(
            at: 5,
            isInHotspot: false,
            isInPanel: false,
            isInteractionLocked: true,
            revealDelay: 0.2,
            hideDelay: 0.3
        ), .none)
        XCTAssertTrue(machine.isVisible)
    }

    func testStateMachineExposesOnlyPendingTransitionDeadlines() {
        var machine = VoicecoreNoteCornerHoverStateMachine()
        XCTAssertNil(machine.nextEvaluationDelay(at: 1, revealDelay: 0.2, hideDelay: 0.3))

        _ = machine.update(
            at: 1,
            isInHotspot: true,
            isInPanel: false,
            isInteractionLocked: false,
            revealDelay: 0.2,
            hideDelay: 0.3
        )
        XCTAssertEqual(machine.nextEvaluationDelay(at: 1.05, revealDelay: 0.2, hideDelay: 0.3) ?? -1, 0.15, accuracy: 0.001)

        _ = machine.update(
            at: 1.21,
            isInHotspot: true,
            isInPanel: false,
            isInteractionLocked: false,
            revealDelay: 0.2,
            hideDelay: 0.3
        )
        XCTAssertEqual(machine.nextEvaluationDelay(at: 1.41, revealDelay: 0.2, hideDelay: 0.3) ?? -1, 0.6, accuracy: 0.001)
    }
}
