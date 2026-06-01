import XCTest
import AppKit

/// End-to-end UI smoke tests for the markyttdown macOS app. These exercise
/// the launched binary, not the in-process code, and therefore prove that
/// menus, commands, layout switching and document plumbing all wire up
/// correctly through SwiftUI / AppKit.
@MainActor
final class MarkyttdownUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["MARKYTTDOWN_UI_TEST"] = "1"
        app.launch()
        return app
    }

    func testAppLaunchesAndShowsADocumentWindow() {
        let app = launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10),
                      "Expected a document window after launch")
    }

    func testAppMenuExposesCheckForUpdates() {
        let app = launch()
        let appMenu = app.menuBarItems["markyttdown"]
        XCTAssertTrue(appMenu.waitForExistence(timeout: 5))
        appMenu.click()
        XCTAssertTrue(app.menuItems["Check for Updates…"].waitForExistence(timeout: 3),
                      "Expected an auto-update menu item")
        // Dismiss the menu by pressing Escape.
        XCUIApplication().typeKey(.escape, modifierFlags: [])
    }

    func testFileMenuHasPrint() {
        let app = launch()
        let fileMenu = app.menuBarItems["File"]
        XCTAssertTrue(fileMenu.waitForExistence(timeout: 5))
        fileMenu.click()
        XCTAssertTrue(app.menuItems["Print…"].waitForExistence(timeout: 3),
                      "Expected a Print menu item under File")
        XCUIApplication().typeKey(.escape, modifierFlags: [])
    }

    func testLayoutCommandsPresent() {
        let app = launch()
        let viewMenu = app.menuBarItems["View"]
        XCTAssertTrue(viewMenu.waitForExistence(timeout: 5))
        viewMenu.click()
        // LayoutCommands ships a segmented picker plus two pane buttons.
        XCTAssertTrue(app.menuItems["Editor"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.menuItems["Preview"].exists)
        XCUIApplication().typeKey(.escape, modifierFlags: [])
    }

    func testTypingPropagatesToEditor() {
        let app = launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))

        // Click into the window's content area to focus the editor without
        // relying on the editor exposing a specific accessibility element type
        // (which varies across Xcode releases for SwiftUI-wrapped NSTextView).
        window.click()
        let sample = "ui-test-marker-\(UUID().uuidString.prefix(8))"
        app.typeText(String(sample))

        // Round-trip via the system pasteboard: ⌘A → ⌘C → read.
        let pb = NSPasteboard.general
        pb.clearContents()
        app.typeKey("a", modifierFlags: .command)
        app.typeKey("c", modifierFlags: .command)

        let exp = expectation(description: "pasteboard reflects typed input")
        let deadline = Date().addingTimeInterval(3)
        DispatchQueue.global().async {
            while Date() < deadline {
                if let s = pb.string(forType: .string), s.contains(String(sample)) {
                    exp.fulfill(); return
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        wait(for: [exp], timeout: 5)
    }

    func testPreviewPaneSwitchKeyboardShortcut() {
        let app = launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))

        // ⌘2 → preview pane. With no document, both views still render; the
        // shortcut just shouldn't crash anything.
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.windows.firstMatch.exists,
                      "Window should survive a preview-pane shortcut")

        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.windows.firstMatch.exists)
    }
}
