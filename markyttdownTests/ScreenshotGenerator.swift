import XCTest
import SwiftUI
import AppKit
@testable import markyttdown

/// Renders demo PNGs of the live preview into ../docs/screenshots/ via
/// SwiftUI's offscreen ImageRenderer. Run explicitly to refresh README
/// assets; ignored by the default test suite via the `GENERATE_SCREENSHOTS`
/// env var.
///
/// Usage:
///   GENERATE_SCREENSHOTS=1 xcodebuild ... test -only-testing:markyttdownTests/ScreenshotGenerator
@MainActor
final class ScreenshotGenerator: XCTestCase {
    /// Runs as part of the normal test suite. Always (re)writes PNG snapshots
    /// into ../docs/screenshots/ relative to this source file.
    func testGenerateScreenshots() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // markyttdownTests/
            .deletingLastPathComponent() // repo root
        let outDir = projectRoot.appendingPathComponent("docs/screenshots")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let sample = sampleMarkdown

        try writePNG(
            view: PreviewContent(text: sample, baseURL: nil)
                .frame(width: 720)
                .padding(.vertical, 8)
                .background(Color(NSColor.textBackgroundColor)),
            width: 720,
            to: outDir.appendingPathComponent("preview.png")
        )

        try writePNG(
            view: EditorMockup(text: sample)
                .frame(width: 720)
                .background(Color(NSColor.textBackgroundColor)),
            width: 720,
            to: outDir.appendingPathComponent("editor.png")
        )

        try writePNG(
            view: HStack(spacing: 1) {
                EditorMockup(text: sample)
                    .frame(width: 460)
                    .background(Color(NSColor.textBackgroundColor))
                Color(NSColor.separatorColor).frame(width: 1)
                PreviewContent(text: sample, baseURL: nil)
                    .frame(width: 460)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.textBackgroundColor))
            }
            .frame(width: 921),
            width: 921,
            to: outDir.appendingPathComponent("split.png")
        )
    }

    private func writePNG<V: View>(view: V, width: CGFloat, to url: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2 // retina
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            XCTFail("Failed to render \(url.lastPathComponent)")
            return
        }
        try png.write(to: url)
    }
}

private struct EditorMockup: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
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

```swift
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
