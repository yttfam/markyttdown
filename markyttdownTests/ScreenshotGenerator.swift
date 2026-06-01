import XCTest
import AppKit
@testable import markyttdown

/// Renders demo PNGs of the live preview / editor / split view into
/// ../docs/screenshots/. Uses NSTextView (the same view the app ships with),
/// then bitmap-snapshots it offscreen — so the snapshot matches the runtime
/// pixel-for-pixel.
@MainActor
final class ScreenshotGenerator: XCTestCase {
    func testGenerateScreenshots() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // markyttdownTests/
            .deletingLastPathComponent() // repo root
        let outDir = projectRoot.appendingPathComponent("docs/screenshots")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        try writePNG(
            snapshot: previewSnapshot(width: 720),
            to: outDir.appendingPathComponent("preview.png")
        )

        try writePNG(
            snapshot: editorSnapshot(width: 720),
            to: outDir.appendingPathComponent("editor.png")
        )

        try writePNG(
            snapshot: splitSnapshot(width: 921, editorWidth: 460, previewWidth: 460),
            to: outDir.appendingPathComponent("split.png")
        )
    }

    // MARK: - Snapshots

    private func previewSnapshot(width: CGFloat) -> NSImage {
        let tv = configuredPreviewTextView(width: width)
        return renderToImage(tv)
    }

    private func editorSnapshot(width: CGFloat) -> NSImage {
        let tv = configuredEditorTextView(width: width)
        return renderToImage(tv)
    }

    private func splitSnapshot(width: CGFloat,
                               editorWidth: CGFloat,
                               previewWidth: CGFloat) -> NSImage {
        let editor = configuredEditorTextView(width: editorWidth)
        let preview = configuredPreviewTextView(width: previewWidth)
        let editorImage = renderToImage(editor)
        let previewImage = renderToImage(preview)
        let height = max(editorImage.size.height, previewImage.size.height)
        let composed = NSImage(size: NSSize(width: width, height: height))
        composed.lockFocus()
        NSColor.textBackgroundColor.setFill()
        NSRect(origin: .zero, size: composed.size).fill()
        editorImage.draw(at: .zero,
                         from: NSRect(origin: .zero, size: editorImage.size),
                         operation: .sourceOver,
                         fraction: 1)
        previewImage.draw(at: NSPoint(x: width - previewWidth, y: 0),
                          from: NSRect(origin: .zero, size: previewImage.size),
                          operation: .sourceOver,
                          fraction: 1)
        NSColor.separatorColor.setFill()
        NSRect(x: editorWidth, y: 0, width: 1, height: height).fill()
        composed.unlockFocus()
        return composed
    }

    private func configuredPreviewTextView(width: CGFloat) -> NSTextView {
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        tv.isEditable = false
        tv.isSelectable = false
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = true
        tv.textContainerInset = NSSize(width: 16, height: 16)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.size = NSSize(width: width, height: .greatestFiniteMagnitude)
        let attr = NSAttributedMarkdown.render(sampleMarkdown, baseURL: nil)
        tv.textStorage?.setAttributedString(attr)
        sizeToFit(tv, width: width)
        return tv
    }

    private func configuredEditorTextView(width: CGFloat) -> NSTextView {
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        tv.isEditable = false
        tv.isSelectable = false
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = true
        tv.textContainerInset = NSSize(width: 16, height: 16)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.size = NSSize(width: width, height: .greatestFiniteMagnitude)
        tv.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        tv.string = sampleMarkdown
        sizeToFit(tv, width: width)
        return tv
    }

    /// NSTextView needs to be in a window for the layout manager to actually
    /// run glyph generation. Park it in an offscreen window long enough to
    /// measure used rect, then detach.
    private func sizeToFit(_ tv: NSTextView, width: CGFloat) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 2000),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        window.contentView = tv
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
        let used = tv.layoutManager?.usedRect(for: tv.textContainer!).height ?? 0
        let inset = tv.textContainerInset.height * 2
        tv.frame = NSRect(x: 0, y: 0, width: width, height: used + inset)
        tv.removeFromSuperview()
        _ = window
    }

    private func renderToImage(_ view: NSView) -> NSImage {
        let bounds = view.bounds
        let rep = view.bitmapImageRepForCachingDisplay(in: bounds)!
        view.cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    private func writePNG(snapshot: NSImage, to url: URL) throws {
        guard let tiff = snapshot.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            XCTFail("Failed to encode PNG for \(url.lastPathComponent)")
            return
        }
        try png.write(to: url)
    }
}

private let sampleMarkdown = """
# markyttdown

A tiny native macOS markdown editor. Part of the **YTT family**.

## Features

- Edit / Preview / Side-by-side layouts
- **Proportional scroll sync** between panes
- Inline image rendering (`https://` *and* local `./images/…`)
- Print the rendered preview via ⌘P
- Auto-update against GitHub Releases

> "It's just a markdown editor — and that's the point."

### Code

```
let app = Markyttdown()
app.run()
```

### Lists

1. First item
2. Second item
3. Third item

### Links

See [yttfam/markyttdown](https://github.com/yttfam/markyttdown) for source.
"""
