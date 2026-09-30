import Carbon.HIToolbox
import XCTest
@testable import SharexMac

final class HotkeyTests: XCTestCase {
    func testCaptureHotkeysUseControlOptionShift() {
        let expected = UInt32(controlKey | optionKey | shiftKey)
        for hotkey in [Hotkey.fullscreen, .region, .activeWindow] {
            XCTAssertEqual(hotkey.carbonModifiers, expected)
        }
    }

    func testCaptureHotkeysAreDistinct() {
        let keyCodes = [Hotkey.fullscreen, .region, .activeWindow].map(\.keyCode)
        XCTAssertEqual(Set(keyCodes).count, keyCodes.count)
    }

    func testCommandMapsToCmdKey() {
        let hotkey = Hotkey(keyCode: kVK_ANSI_A, keyEquivalent: "a", modifiers: [.command])
        XCTAssertEqual(hotkey.carbonModifiers, UInt32(cmdKey))
    }
}
