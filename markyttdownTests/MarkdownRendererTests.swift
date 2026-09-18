import XCTest
import AppKit
@testable import markyttdown

@MainActor
final class NSAttributedMarkdownTests: XCTestCase {
    func testEmptyRendersEmpty() {
        XCTAssertEqual(NSAttributedMarkdown.render("").attributed.length, 0)
    }

    func testParagraphRendersText() {
        let s = NSAttributedMarkdown.render("hello world").attributed
        XCTAssertEqual(s.string, "hello world")
    }

    func testHeadingRendersText() {
        let s = NSAttributedMarkdown.render("# Title").attributed
        XCTAssertEqual(s.string, "Title")
    }

    func testHeadingIsBoldAndLarger() {
        let s = NSAttributedMarkdown.render("# Big").attributed
        let font = s.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(font)
        XCTAssertGreaterThan(font!.pointSize, NSFont.systemFontSize)
        XCTAssertTrue(NSFontManager.shared.traits(of: font!).contains(.boldFontMask))
    }

    func testBoldAndItalic() {
        let s = NSAttributedMarkdown.render("**bold** *italic*").attributed
        XCTAssertTrue(s.string.contains("bold"))
        XCTAssertTrue(s.string.contains("italic"))
    }

    func testInlineCode() {
        let s = NSAttributedMarkdown.render("a `code` b").attributed
        let codeRange = (s.string as NSString).range(of: "code")
        let font = s.attribute(.font, at: codeRange.location, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(font)
        XCTAssertTrue(font!.fontName.lowercased().contains("mono"))
    }

    func testFencedCodeBlock() {
        let src = """
        ```
        let x = 1
        ```
        """
        let s = NSAttributedMarkdown.render(src).attributed
        XCTAssertTrue(s.string.contains("let x = 1"))
    }

    func testListRendersBullets() {
        let s = NSAttributedMarkdown.render("- one\n- two").attributed
        XCTAssertTrue(s.string.contains("•"))
        XCTAssertTrue(s.string.contains("one"))
        XCTAssertTrue(s.string.contains("two"))
    }

    func testOrderedListRendersNumbers() {
        let s = NSAttributedMarkdown.render("1. first\n2. second").attributed
        XCTAssertTrue(s.string.contains("1."))
        XCTAssertTrue(s.string.contains("2."))
    }

    func testLinkAttributeSet() {
        let s = NSAttributedMarkdown.render("[click](https://example.com)").attributed
        let range = (s.string as NSString).range(of: "click")
        XCTAssertGreaterThan(range.length, 0)
        let link = s.attribute(.link, at: range.location, effectiveRange: nil)
        XCTAssertEqual((link as? URL)?.absoluteString, "https://example.com")
    }

    func testRelativeLinkResolvedAgainstBaseURL() {
        let base = URL(fileURLWithPath: "/tmp/notes/index.md")
        let s = NSAttributedMarkdown.render("[next](./chapter2.md)", baseURL: base).attributed
        let range = (s.string as NSString).range(of: "next")
        let link = s.attribute(.link, at: range.location, effectiveRange: nil) as? URL
        XCTAssertNotNil(link)
        XCTAssertTrue(link!.path.hasSuffix("/tmp/notes/chapter2.md"))
    }

    func testRelativeImageBecomesFileURLAttachment() throws {
        let tmp = NSTemporaryDirectory() + "markyttdown_test_img"
        try? FileManager.default.removeItem(atPath: tmp)
        try FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        let imgPath = tmp + "/cat.png"
        // 1x1 transparent PNG
        let data = Data([
            0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A, 0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
            0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01, 0x08,0x06,0x00,0x00,0x00,0x1F,0x15,0xC4,
            0x89,0x00,0x00,0x00,0x0D,0x49,0x44,0x41, 0x54,0x78,0x9C,0x63,0x00,0x01,0x00,0x00,
            0x05,0x00,0x01,0x0D,0x0A,0x2D,0xB4,0x00, 0x00,0x00,0x00,0x49,0x45,0x4E,0x44,0xAE,
            0x42,0x60,0x82,
        ])
        try data.write(to: URL(fileURLWithPath: imgPath))

        let doc = URL(fileURLWithPath: tmp + "/note.md")
        let s = NSAttributedMarkdown.render("![cat](./cat.png)", baseURL: doc).attributed
        var found = false
        s.enumerateAttribute(.attachment, in: NSRange(location: 0, length: s.length)) { value, _, _ in
            if value is NSTextAttachment { found = true }
        }
        XCTAssertTrue(found, "expected NSTextAttachment for local image")
    }

    func testRemoteImageRecorded() {
        let s = NSAttributedMarkdown.render("![cat](https://example.com/cat.png)").attributed
        let urls = NSAttributedMarkdown.remoteImageURLs(in: s)
        XCTAssertEqual(urls.first?.absoluteString, "https://example.com/cat.png")
    }

    func testTextOnlyMarkdownHasNoAttachment() {
        let s = NSAttributedMarkdown.render("# Hi\n\nhello").attributed
        var found = false
        s.enumerateAttribute(.attachment, in: NSRange(location: 0, length: s.length)) { value, _, _ in
            if value is NSTextAttachment { found = true }
        }
        XCTAssertFalse(found)
    }

    func testMixedParagraphKeepsTextAndImageSeparate() {
        let s = NSAttributedMarkdown.render(
            "before ![alt](https://x/y.png) after"
        ).attributed
        XCTAssertTrue(s.string.contains("before"))
        XCTAssertTrue(s.string.contains("after"))
        let urls = NSAttributedMarkdown.remoteImageURLs(in: s)
        XCTAssertEqual(urls.count, 1)
    }

    func testTableRendersHeadAndBody() {
        let src = """
        | a | b | c |
        |---|---|---|
        | 1 | 2 | 3 |
        | 4 | 5 | 6 |
        """
        let s = NSAttributedMarkdown.render(src).attributed
        let str = s.string
        XCTAssertTrue(str.contains("a"))
        XCTAssertTrue(str.contains("b"))
        XCTAssertTrue(str.contains("c"))
        XCTAssertTrue(str.contains("1"))
        XCTAssertTrue(str.contains("6"))
    }

    func testTableAttachesNSTextBlockParagraphStyles() {
        let src = """
        | a | b |
        |---|---|
        | 1 | 2 |
        """
        let s = NSAttributedMarkdown.render(src).attributed
        var blockCount = 0
        s.enumerateAttribute(.paragraphStyle,
                             in: NSRange(location: 0, length: s.length)) { value, _, _ in
            if let style = value as? NSParagraphStyle, !style.textBlocks.isEmpty {
                blockCount += 1
            }
        }
        // 2 cols × 2 rows (head + 1 body) = 4 cell paragraphs.
        XCTAssertEqual(blockCount, 4)
    }

    func testTableHeaderRowIsSemibold() {
        let src = """
        | head |
        |------|
        | body |
        """
        let s = NSAttributedMarkdown.render(src).attributed
        let headRange = (s.string as NSString).range(of: "head")
        XCTAssertGreaterThan(headRange.length, 0)
        let font = s.attribute(.font, at: headRange.location, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(font)
        XCTAssertTrue(NSFontManager.shared.weight(of: font!) >= 6,
                      "Expected header weight ≥ semibold; got \(NSFontManager.shared.weight(of: font!))")
    }

    // MARK: - Line anchors (scroll sync)

    func testAnchorsRecordEachTopLevelBlock() {
        let src = """
        # Title

        First paragraph.

        Second paragraph.

        ## Subhead

        More text.
        """
        let r = NSAttributedMarkdown.render(src)
        // 4 top-level blocks: title, para 1, para 2, subhead, para 3 = 5
        XCTAssertEqual(r.anchors.count, 5)
        // Anchors should be sorted ascending by source line and by attr offset.
        for (a, b) in zip(r.anchors, r.anchors.dropFirst()) {
            XCTAssertLessThan(a.sourceLine, b.sourceLine)
            XCTAssertLessThan(a.attrOffset, b.attrOffset)
        }
        // First anchor always at line 1 → attr offset 0.
        XCTAssertEqual(r.anchors.first?.sourceLine, 1)
        XCTAssertEqual(r.anchors.first?.attrOffset, 0)
    }

    func testAttrOffsetLookupUsesGreatestAnchorAtOrBelowLine() {
        let src = """
        # A

        # B

        # C
        """
        let r = NSAttributedMarkdown.render(src)
        // Lines: 1=A, 3=B, 5=C. Ask for line 4 → get B's offset (line 3).
        let offsetForLine4 = r.attrOffset(forSourceLine: 4)
        let offsetForLine3 = r.attrOffset(forSourceLine: 3)
        XCTAssertEqual(offsetForLine4, offsetForLine3)
    }

    func testSourceLineReverseLookup() {
        let src = "# A\n\n# B\n\n# C"
        let r = NSAttributedMarkdown.render(src)
        // Character 0 → line 1.
        XCTAssertEqual(r.sourceLine(forAttrOffset: 0), 1)
        // Offset past the last anchor still returns the last anchor's line.
        let last = r.anchors.last!
        XCTAssertEqual(r.sourceLine(forAttrOffset: last.attrOffset + 100),
                       last.sourceLine)
    }

    func testReplaceAttachment() {
        let storage = NSTextStorage(attributedString: NSAttributedMarkdown.render(
            "![cat](https://example.com/cat.png)"
        ).attributed)
        let url = URL(string: "https://example.com/cat.png")!
        XCTAssertEqual(NSAttributedMarkdown.remoteImageURLs(in: storage), [url])

        let img = NSImage(size: NSSize(width: 10, height: 10))
        img.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 10, height: 10).fill()
        img.unlockFocus()

        NSAttributedMarkdown.replace(attachmentForURL: url, with: img, in: storage)

        var foundImage: NSImage?
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if let a = value as? NSTextAttachment { foundImage = a.image }
        }
        XCTAssertNotNil(foundImage)
        XCTAssertEqual(foundImage?.size, NSSize(width: 10, height: 10))
    }
}
