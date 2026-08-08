// HistoryCorrectionPresentationTests.swift
// Provides History Correction Presentation Tests for Voicecore test coverage.

import XCTest
@testable import Voicecore

final class HistoryCorrectionPresentationTests: XCTestCase {
    func testCorrectedTextReturnsFinalVisibleText() {
        let text = "我们创建了新的APP，名字叫Voicecore，支持语音转文本。"
        let corrected = HistoryCorrectionPresentation.correctedText(
            for: text,
            snapshots: [
                DictionaryCorrectionSnapshot(
                    originalText: "Waxed",
                    correctedText: "Voicecore",
                    finalLocation: (text as NSString).range(of: "Voicecore").location,
                    finalLength: ("Voicecore" as NSString).length
                )
            ]
        )

        XCTAssertEqual(corrected, text)
    }

    func testSegmentsInlineSingleCorrection() {
        let text = "我们创建了新的APP，名字叫Voicecore，支持语音转文本。"
        let segments = HistoryCorrectionPresentation.segments(
            for: text,
            snapshots: [
                DictionaryCorrectionSnapshot(
                    originalText: "Waxed",
                    correctedText: "Voicecore",
                    finalLocation: (text as NSString).range(of: "Voicecore").location,
                    finalLength: ("Voicecore" as NSString).length
                )
            ]
        )

        XCTAssertEqual(
            segments,
            [
                .plain("我们创建了新的APP，名字叫"),
                .original("Waxed"),
                .corrected("Voicecore"),
                .plain("，支持语音转文本。")
            ]
        )
    }

    func testSegmentsPreserveMultipleCorrectionsInOrder() {
        let text = "OpenAI 和 Voicecore 都支持语音。"
        let nsText = text as NSString
        let segments = HistoryCorrectionPresentation.segments(
            for: text,
            snapshots: [
                DictionaryCorrectionSnapshot(
                    originalText: "Open Ai",
                    correctedText: "OpenAI",
                    finalLocation: nsText.range(of: "OpenAI").location,
                    finalLength: 6
                ),
                DictionaryCorrectionSnapshot(
                    originalText: "Waxed",
                    correctedText: "Voicecore",
                    finalLocation: nsText.range(of: "Voicecore").location,
                    finalLength: ("Voicecore" as NSString).length
                )
            ]
        )

        XCTAssertEqual(
            segments,
            [
                .original("Open Ai"),
                .corrected("OpenAI"),
                .plain(" 和 "),
                .original("Waxed"),
                .corrected("Voicecore"),
                .plain(" 都支持语音。")
            ]
        )
    }

    func testSegmentsIgnoreInvalidSnapshots() {
        let segments = HistoryCorrectionPresentation.segments(
            for: "Voicecore",
            snapshots: [
                DictionaryCorrectionSnapshot(
                    originalText: "Waxed",
                    correctedText: "Voicecore",
                    finalLocation: 99,
                    finalLength: 4
                )
            ]
        )

        XCTAssertEqual(segments, [.plain("Voicecore")])
    }
}
