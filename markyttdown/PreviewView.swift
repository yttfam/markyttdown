import SwiftUI
import AppKit
import Markdown

struct PreviewView: NSViewRepresentable {
    let text: String
    @ObservedObject var sync: ScrollSync

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.contentView.postsBoundsChangedNotifications = true

        let host = NSHostingView(rootView: PreviewContent(text: text))
        host.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = host
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            host.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
        ])

        context.coordinator.scrollView = scroll
        context.coordinator.host = host
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.boundsChanged(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scroll.contentView
        )
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.host?.rootView = PreviewContent(text: text)
        context.coordinator.applyExternalSync()
    }

    @MainActor
    final class Coordinator: NSObject {
        let parent: PreviewView
        weak var scrollView: NSScrollView?
        weak var host: NSHostingView<PreviewContent>?
        private var suppressNotification = false

        init(_ parent: PreviewView) { self.parent = parent }

        @objc func boundsChanged(_ note: Notification) {
            guard !suppressNotification, let sv = scrollView else { return }
            let p = ScrollSyncHelper.progress(of: sv)
            parent.sync.owner = ObjectIdentifier(self)
            parent.sync.progress = p
        }

        func applyExternalSync() {
            guard let sv = scrollView else { return }
            if let owner = parent.sync.owner, owner == ObjectIdentifier(self) { return }
            suppressNotification = true
            ScrollSyncHelper.apply(progress: parent.sync.progress, to: sv)
            DispatchQueue.main.async { [weak self] in self?.suppressNotification = false }
        }
    }
}

struct PreviewContent: View {
    let text: String

    var body: some View {
        let blocks = MarkdownRenderer.renderBlocks(text)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks) { block in
                switch block.kind {
                case .text(let s):
                    Text(s)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .image(let url, let alt):
                    ImageBlock(url: url, alt: alt)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }
}

private struct ImageBlock: View {
    let url: URL?
    let alt: String

    var body: some View {
        Group {
            if let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().controlSize(.small)
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else if let url, url.isFileURL, let nsi = NSImage(contentsOf: url) {
                Image(nsImage: nsi)
                    .resizable()
                    .scaledToFit()
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var placeholder: some View {
        Text("🖼 " + (alt.isEmpty ? (url?.absoluteString ?? "image") : alt))
            .foregroundColor(.secondary)
    }
}

struct PreviewBlock: Identifiable {
    let id: Int
    let kind: Kind
    enum Kind {
        case text(AttributedString)
        case image(url: URL?, alt: String)
    }
}

enum MarkdownRenderer {
    /// Flat AttributedString (text-only; images become "🖼 alt"). Kept for tests
    /// and any future plain-text consumer.
    static func render(_ source: String) -> AttributedString {
        var out = AttributedString()
        for block in renderBlocks(source) {
            if !out.characters.isEmpty { out.append(AttributedString("\n\n")) }
            switch block.kind {
            case .text(let s):
                out.append(s)
            case .image(_, let alt):
                var s = AttributedString("🖼 " + alt)
                s.foregroundColor = .secondary
                out.append(s)
            }
        }
        return out
    }

    /// Sequence of renderable blocks (interleaved text and images). Used by the
    /// preview view.
    static func renderBlocks(_ source: String) -> [PreviewBlock] {
        let document = Document(parsing: source)
        var blocks: [PreviewBlock] = []
        var counter = 0

        func emitText(_ s: AttributedString) {
            guard !s.characters.isEmpty else { return }
            blocks.append(PreviewBlock(id: counter, kind: .text(s)))
            counter += 1
        }

        func emitImage(_ img: Markdown.Image) {
            let url = img.source.flatMap { URL(string: $0) }
            blocks.append(PreviewBlock(id: counter, kind: .image(url: url, alt: img.plainText)))
            counter += 1
        }

        for child in document.children {
            if let para = child as? Paragraph,
               para.children.contains(where: { $0 is Markdown.Image }) {
                // Split paragraph around images.
                var current = AttributedString()
                for inline in para.children {
                    if let img = inline as? Markdown.Image {
                        emitText(current)
                        current = AttributedString()
                        emitImage(img)
                    } else {
                        renderInlineNode(inline, into: &current, baseFont: .body, bold: false)
                    }
                }
                emitText(current)
            } else {
                var s = AttributedString()
                renderBlock(child, into: &s)
                emitText(s)
            }
        }
        return blocks
    }

    // MARK: - Text-only block rendering

    private static func renderBlock(_ node: any Markup, into out: inout AttributedString) {
        switch node {
        case let h as Heading:
            appendBlock(renderInlines(h, baseFont: headingFont(level: h.level), bold: true), into: &out)
        case let p as Paragraph:
            appendBlock(renderInlines(p), into: &out)
        case let code as CodeBlock:
            var s = AttributedString(code.code)
            s.font = .system(.body, design: .monospaced)
            s.backgroundColor = .secondary.opacity(0.15)
            appendBlock(s, into: &out)
        case let q as BlockQuote:
            var inner = AttributedString()
            for child in q.children { renderBlock(child, into: &inner) }
            inner.foregroundColor = .secondary
            appendBlock(inner, into: &out)
        case let list as UnorderedList:
            appendBlock(renderList(list, ordered: false), into: &out)
        case let list as OrderedList:
            appendBlock(renderList(list, ordered: true), into: &out)
        case is ThematicBreak:
            var s = AttributedString("────────────────")
            s.foregroundColor = .secondary
            appendBlock(s, into: &out)
        default:
            for child in node.children { renderBlock(child, into: &out) }
        }
    }

    private static func appendBlock(_ s: AttributedString, into out: inout AttributedString) {
        if !out.characters.isEmpty { out.append(AttributedString("\n\n")) }
        out.append(s)
    }

    private static func renderList(_ list: any ListItemContainer, ordered: Bool) -> AttributedString {
        var out = AttributedString()
        var idx = 1
        for item in list.listItems {
            let bullet = ordered ? "\(idx). " : "•  "
            var line = AttributedString(bullet)
            for child in item.children {
                if let p = child as? Paragraph {
                    line.append(renderInlines(p))
                } else {
                    var sub = AttributedString()
                    renderBlock(child, into: &sub)
                    line.append(sub)
                }
            }
            if !out.characters.isEmpty { out.append(AttributedString("\n")) }
            out.append(line)
            idx += 1
        }
        return out
    }

    private static func renderInlines(_ container: any Markup, baseFont: Font = .body, bold: Bool = false) -> AttributedString {
        var out = AttributedString()
        for child in container.children {
            renderInlineNode(child, into: &out, baseFont: baseFont, bold: bold)
        }
        return out
    }

    private static func renderInlineNode(
        _ node: any Markup,
        into out: inout AttributedString,
        baseFont: Font,
        bold: Bool,
        italic: Bool = false,
        link: String? = nil
    ) {
        switch node {
        case let t as Markdown.Text:
            var s = AttributedString(t.string)
            var font = baseFont
            if bold { font = font.bold() }
            if italic { font = font.italic() }
            s.font = font
            if let link, let url = URL(string: link) {
                s.link = url
                s.foregroundColor = .accentColor
                s.underlineStyle = .single
            }
            out.append(s)
        case let s as Strong:
            for c in s.children {
                renderInlineNode(c, into: &out, baseFont: baseFont, bold: true, italic: italic, link: link)
            }
        case let e as Emphasis:
            for c in e.children {
                renderInlineNode(c, into: &out, baseFont: baseFont, bold: bold, italic: true, link: link)
            }
        case let ic as InlineCode:
            var s = AttributedString(ic.code)
            s.font = .system(.body, design: .monospaced)
            s.backgroundColor = .secondary.opacity(0.15)
            if let link, let url = URL(string: link) { s.link = url }
            out.append(s)
        case let lk as Markdown.Link:
            for c in lk.children {
                renderInlineNode(c, into: &out, baseFont: baseFont, bold: bold, italic: italic, link: lk.destination)
            }
        case is SoftBreak:
            out.append(AttributedString(" "))
        case is LineBreak:
            out.append(AttributedString("\n"))
        case let img as Markdown.Image:
            // Inline-positioned image (inside a non-pure-image paragraph): keep
            // a textual placeholder. Block-level images are handled in
            // renderBlocks via emitImage.
            var s = AttributedString("🖼 " + (img.plainText.isEmpty ? (img.source ?? "image") : img.plainText))
            s.foregroundColor = .secondary
            out.append(s)
        default:
            for c in node.children {
                renderInlineNode(c, into: &out, baseFont: baseFont, bold: bold, italic: italic, link: link)
            }
        }
    }

    private static func headingFont(level: Int) -> Font {
        switch level {
        case 1: return .system(size: 28, weight: .bold)
        case 2: return .system(size: 22, weight: .bold)
        case 3: return .system(size: 18, weight: .semibold)
        case 4: return .system(size: 16, weight: .semibold)
        case 5: return .system(size: 14, weight: .semibold)
        default: return .system(size: 13, weight: .semibold)
        }
    }
}
