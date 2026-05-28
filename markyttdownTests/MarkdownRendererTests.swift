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

    func testStandaloneImageBecomesImageBlock() {
        let blocks = MarkdownRenderer.renderBlocks("![cat](https://example.com/cat.png)")
        XCTAssertEqual(blocks.count, 1)
        guard case let .image(url, alt) = blocks[0].kind else {
            return XCTFail("expected image block")
        }
        XCTAssertEqual(url?.absoluteString, "https://example.com/cat.png")
        XCTAssertEqual(alt, "cat")
    }

    func testMixedParagraphSplitsAroundImage() {
        let blocks = MarkdownRenderer.renderBlocks("before ![alt](https://x/y.png) after")
        XCTAssertEqual(blocks.count, 3)
        if case let .text(s) = blocks[0].kind {
            XCTAssertTrue(String(s.characters).contains("before"))
        } else { XCTFail() }
        if case .image = blocks[1].kind {} else { XCTFail() }
        if case let .text(s) = blocks[2].kind {
            XCTAssertTrue(String(s.characters).contains("after"))
        } else { XCTFail() }
    }

    func testTextOnlyHasNoImageBlocks() {
        let blocks = MarkdownRenderer.renderBlocks("# Hi\n\nhello")
        XCTAssertTrue(blocks.allSatisfy {
            if case .text = $0.kind { return true } else { return false }
        })
    }
}
