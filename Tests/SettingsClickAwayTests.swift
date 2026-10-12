import AppKit
import XCTest
@testable import Codenotch

/// A click outside the field being edited ends its editing; a click on it, or
/// on the few points of ring and bezel round it, must not.
@MainActor
final class SettingsClickAwayTests: XCTestCase {
    private let field = NSRect(x: 100, y: 100, width: 200, height: 24)

    func testAClickOnTheFieldKeepsEditing() {
        XCTAssertTrue(SettingsWindowController.isInside(NSPoint(x: 150, y: 110), fieldFrame: field))
        // On the focus ring, just outside the text area.
        XCTAssertTrue(SettingsWindowController.isInside(NSPoint(x: 98, y: 122), fieldFrame: field))
    }

    func testAClickElsewhereEndsIt() {
        XCTAssertFalse(SettingsWindowController.isInside(NSPoint(x: 350, y: 110), fieldFrame: field))
        XCTAssertFalse(SettingsWindowController.isInside(NSPoint(x: 150, y: 140), fieldFrame: field))
    }

    /// Settings opens with nothing being typed in: AppKit would otherwise hand
    /// the new key window to its first text field, caret and AutoFill with it.
    func testAWindowStartsWithNoFieldBeingEdited() {
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 300, height: 120),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let field = NSTextField(frame: NSRect(x: 20, y: 40, width: 200, height: 24))
        window.contentView?.addSubview(field)
        window.makeFirstResponder(field)
        XCTAssertTrue(window.firstResponder is NSText, "precondition: the field is being edited")

        SettingsWindowController.startUnfocused(window)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        XCTAssertFalse(window.firstResponder is NSText)
    }
}
