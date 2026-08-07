import AppKit
import Carbon.HIToolbox
@testable import VoiceCoreApp
import XCTest

final class ShortcutDescriptorBuilderTests: XCTestCase {
    func testBuildsOptionSpaceDescriptor() {
        let descriptor = ShortcutDescriptorBuilder.make(
            keyCode: UInt16(kVK_Space),
            modifiers: [.option],
            charactersIgnoringModifiers: " "
        )

        XCTAssertEqual(descriptor?.keyCode, UInt32(kVK_Space))
        XCTAssertEqual(descriptor?.modifiers, UInt32(optionKey))
        XCTAssertEqual(descriptor?.displayString, "⌥Space")
    }

    func testBuildsStandaloneFunctionKeyDescriptor() {
        let descriptor = ShortcutDescriptorBuilder.make(
            keyCode: UInt16(kVK_Function),
            modifiers: [.function],
            charactersIgnoringModifiers: nil
        )

        XCTAssertEqual(descriptor?.keyCode, UInt32(kVK_Function))
        XCTAssertEqual(descriptor?.modifiers, 0)
        XCTAssertEqual(descriptor?.displayString, "Fn")
    }

    func testNormalizesModifierOrderAndUppercasesCharacter() {
        let descriptor = ShortcutDescriptorBuilder.make(
            keyCode: UInt16(kVK_ANSI_K),
            modifiers: [.command, .shift, .capsLock],
            charactersIgnoringModifiers: "k"
        )

        XCTAssertEqual(descriptor?.modifiers, UInt32(shiftKey | cmdKey))
        XCTAssertEqual(descriptor?.displayString, "⇧⌘K")
    }

    func testRejectsUnmodifiedAndEscapeKeys() {
        XCTAssertNil(ShortcutDescriptorBuilder.make(
            keyCode: UInt16(kVK_ANSI_A),
            modifiers: [],
            charactersIgnoringModifiers: "a"
        ))
        XCTAssertNil(ShortcutDescriptorBuilder.make(
            keyCode: UInt16(kVK_Escape),
            modifiers: [.command],
            charactersIgnoringModifiers: nil
        ))
    }

    func testFormatsArrowKey() {
        let descriptor = ShortcutDescriptorBuilder.make(
            keyCode: UInt16(kVK_LeftArrow),
            modifiers: [.control, .option],
            charactersIgnoringModifiers: nil
        )

        XCTAssertEqual(descriptor?.displayString, "⌃⌥←")
    }
}
