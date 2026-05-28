import XCTest
@testable import markyttdown

final class MarkdownRendererTests: XCTestCase {
    func testEmptyRendersEmpty() {
        XCTAssertTrue(MarkdownRenderer.render("").characters.isEmpty)
    }

    func testParagraphRendersText() {
        let s = MarkdownRenderer.render("hello world")
        XCTAssertEqual(String(s.characters), "hello world")
    }

    func testHeadingRendersText() {
        let s = MarkdownRenderer.render("# Title")
        XCTAssertEqual(String(s.characters), "Title")
    }

    func testListRendersBullets() {
        let s = MarkdownRenderer.render("- one\n- two")
        let plain = String(s.characters)
        XCTAssertTrue(plain.contains("one"))
        XCTAssertTrue(plain.contains("two"))
        XCTAssertTrue(plain.contains("•"))
    }
}
