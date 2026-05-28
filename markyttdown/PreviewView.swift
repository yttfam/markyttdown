import SwiftUI
import AppKit
import Markdown

struct PreviewView: View {
    let text: String
    @ObservedObject var sync: ScrollSync
    @StateObject private var bridge = PreviewScrollBridge()

    var body: some View {
        ScrollView(.vertical) {
            PreviewContent(text: text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .background(
            ScrollViewProbe { sv in
                bridge.attach(scrollView: sv, sync: sync)
            }
        )
        .onChange(of: sync.progress) { _, _ in
            bridge.applyExternalSync()
        }
    }
}

@MainActor
final class PreviewScrollBridge: ObservableObject {
    private weak var scrollView: NSScrollView?
    private weak var sync: ScrollSync?
    private var observer: NSObjectProtocol?
    private var suppress = false

    func attach(scrollView: NSScrollView, sync: ScrollSync) {
        guard self.scrollView !== scrollView else {
            self.sync = sync
            return
        }
        if let observer { NotificationCenter.default.removeObserver(observer) }
        self.scrollView = scrollView
        self.sync = sync
        scrollView.contentView.postsBoundsChangedNotifications = true
        observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.boundsChanged() }
        }
    }

    private func boundsChanged() {
        guard !suppress, let sv = scrollView, let sync else { return }
        let p = ScrollSyncHelper.progress(of: sv)
        sync.owner = ObjectIdentifier(self)
        sync.progress = p
    }

    func applyExternalSync() {
        guard let sv = scrollView, let sync else { return }
        if let owner = sync.owner, owner == ObjectIdentifier(self) { return }
        suppress = true
        ScrollSyncHelper.apply(progress: sync.progress, to: sv)
        Task { @MainActor [weak self] in self?.suppress = false }
    }
}

private struct ScrollViewProbe: NSViewRepresentable {
    let onFound: (NSScrollView) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        v.translatesAutoresizingMaskIntoConstraints = false
        DispatchQueue.main.async { resolve(v) }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { resolve(nsView) }
    }

    private func resolve(_ view: NSView) {
        if let sv = nearestScrollView(from: view) {
            onFound(sv)
        }
    }

    private func nearestScrollView(from view: NSView) -> NSScrollView? {
        var p: NSView? = view.superview
        while let cur = p {
            if let sv = cur as? NSScrollView { return sv }
            p = cur.superview
        }
        return nil
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
                        ProgressView()
                            .controlSize(.small)
                            .frame(height: 40)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else if let url, url.isFileURL, let nsi = NSImage(contentsOf: url) {
                Image(nsImage: nsi)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                placeholder
            }
        }
    }

    private var placeholder: some View {
        Text("🖼 " + (alt.isEmpty ? (url?.absoluteString ?? "image") : alt))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        case 4: return .system(size: 14, weight: .semibold)
        case 5: return .system(size: 14, weight: .semibold)
        default: return .system(size: 13, weight: .semibold)
        }
    }
}
