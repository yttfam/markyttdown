import Foundation
import AppKit
import Markdown

/// Renders markdown source into an NSAttributedString with AppKit-native
/// attributes. Used by the preview NSTextView so links/selection/scrolling
/// all work natively, and by the printer.
///
/// Block-level images become NSTextAttachment runs. http(s) image URLs are
/// returned as placeholder attachments; callers wire up async fetching via
/// `asyncImageRequests(in:baseURL:)` and `replace(attachmentForURL:image:in:)`.
enum NSAttributedMarkdown {
    /// Synchronous render. Local file images load inline; remote (http/https)
    /// images appear as a "Loading…" placeholder attachment carrying their URL
    /// in `.markyttdownImageURL` so a follow-up pass can swap them in.
    static func render(_ source: String, baseURL: URL? = nil) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let doc = Document(parsing: source)
        let ctx = RenderContext(baseURL: baseURL)
        for child in doc.children {
            renderBlock(child, into: out, ctx: ctx)
        }
        return out
    }

    /// Collect the remote URLs whose images still need to be fetched. Caller
    /// can dispatch fetches and feed results back via `replace(...)`.
    static func remoteImageURLs(in attr: NSAttributedString) -> [URL] {
        var urls: [URL] = []
        attr.enumerateAttribute(.markyttdownImageURL,
                                in: NSRange(location: 0, length: attr.length)) { value, _, _ in
            if let url = value as? URL,
               let scheme = url.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                urls.append(url)
            }
        }
        return urls
    }

    /// Replace every attachment carrying `.markyttdownImageURL == url` with one
    /// holding the supplied image. No-op if the URL isn't present.
    static func replace(attachmentForURL url: URL,
                        with image: NSImage,
                        in storage: NSTextStorage) {
        let ranges = collectAttachmentRanges(forURL: url, in: storage)
        guard !ranges.isEmpty else { return }
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(origin: .zero, size: scaledSize(image.size, maxWidth: 600))
        let replacement = NSMutableAttributedString(attachment: attachment)
        replacement.addAttribute(.markyttdownImageURL, value: url,
                                 range: NSRange(location: 0, length: replacement.length))
        for range in ranges.reversed() {
            storage.replaceCharacters(in: range, with: replacement)
        }
    }

    private static func collectAttachmentRanges(forURL url: URL,
                                                in attr: NSAttributedString) -> [NSRange] {
        var ranges: [NSRange] = []
        attr.enumerateAttribute(.markyttdownImageURL,
                                in: NSRange(location: 0, length: attr.length)) { value, range, _ in
            if let stored = value as? URL, stored == url {
                ranges.append(range)
            }
        }
        return ranges
    }

    // MARK: - Internal

    private struct RenderContext {
        let baseURL: URL?
    }

    private static func renderBlock(_ node: any Markup,
                                    into out: NSMutableAttributedString,
                                    ctx: RenderContext) {
        switch node {
        case let h as Heading:
            let line = renderInlines(h,
                                     baseFont: headingFont(level: h.level),
                                     bold: true,
                                     ctx: ctx)
            appendBlock(line, into: out)
        case let p as Paragraph:
            if p.children.contains(where: { $0 is Markdown.Image }) {
                renderImageParagraph(p, into: out, ctx: ctx)
            } else {
                appendBlock(renderInlines(p, ctx: ctx), into: out)
            }
        case let code as CodeBlock:
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                .backgroundColor: NSColor.controlBackgroundColor,
                .foregroundColor: NSColor.labelColor,
            ]
            appendBlock(NSAttributedString(string: code.code, attributes: attrs), into: out)
        case let q as BlockQuote:
            let inner = NSMutableAttributedString()
            for child in q.children { renderBlock(child, into: inner, ctx: ctx) }
            inner.addAttribute(.foregroundColor,
                               value: NSColor.secondaryLabelColor,
                               range: NSRange(location: 0, length: inner.length))
            appendBlock(inner, into: out)
        case let list as UnorderedList:
            appendBlock(renderList(list, ordered: false, ctx: ctx), into: out)
        case let list as OrderedList:
            appendBlock(renderList(list, ordered: true, ctx: ctx), into: out)
        case is ThematicBreak:
            let rule = NSAttributedString(
                string: "────────────────",
                attributes: [.foregroundColor: NSColor.tertiaryLabelColor]
            )
            appendBlock(rule, into: out)
        default:
            for child in node.children { renderBlock(child, into: out, ctx: ctx) }
        }
    }

    private static func appendBlock(_ s: NSAttributedString,
                                    into out: NSMutableAttributedString) {
        if out.length > 0 {
            out.append(NSAttributedString(string: "\n\n"))
        }
        out.append(s)
    }

    private static func renderList(_ list: any ListItemContainer,
                                   ordered: Bool,
                                   ctx: RenderContext) -> NSAttributedString {
        let out = NSMutableAttributedString()
        var idx = 1
        for item in list.listItems {
            let bullet = ordered ? "\(idx). " : "•  "
            let line = NSMutableAttributedString(
                string: bullet,
                attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]
            )
            for child in item.children {
                if let p = child as? Paragraph {
                    line.append(renderInlines(p, ctx: ctx))
                } else {
                    let sub = NSMutableAttributedString()
                    renderBlock(child, into: sub, ctx: ctx)
                    line.append(sub)
                }
            }
            if out.length > 0 { out.append(NSAttributedString(string: "\n")) }
            out.append(line)
            idx += 1
        }
        return out
    }

    private static func renderInlines(_ container: any Markup,
                                      baseFont: NSFont = .systemFont(ofSize: NSFont.systemFontSize),
                                      bold: Bool = false,
                                      ctx: RenderContext) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for child in container.children {
            renderInline(child, into: out,
                         baseFont: baseFont, bold: bold, italic: false,
                         link: nil, ctx: ctx)
        }
        return out
    }

    private static func renderInline(_ node: any Markup,
                                     into out: NSMutableAttributedString,
                                     baseFont: NSFont,
                                     bold: Bool,
                                     italic: Bool,
                                     link: String?,
                                     ctx: RenderContext) {
        switch node {
        case let t as Markdown.Text:
            var attrs: [NSAttributedString.Key: Any] = [
                .font: styledFont(baseFont, bold: bold, italic: italic),
                .foregroundColor: NSColor.labelColor,
            ]
            if let link, let url = resolveURL(link, base: ctx.baseURL) {
                attrs[.link] = url
            }
            out.append(NSAttributedString(string: t.string, attributes: attrs))
        case let s as Strong:
            for c in s.children {
                renderInline(c, into: out,
                             baseFont: baseFont, bold: true, italic: italic,
                             link: link, ctx: ctx)
            }
        case let e as Emphasis:
            for c in e.children {
                renderInline(c, into: out,
                             baseFont: baseFont, bold: bold, italic: true,
                             link: link, ctx: ctx)
            }
        case let ic as InlineCode:
            var attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                .backgroundColor: NSColor.controlBackgroundColor,
                .foregroundColor: NSColor.labelColor,
            ]
            if let link, let url = resolveURL(link, base: ctx.baseURL) {
                attrs[.link] = url
            }
            out.append(NSAttributedString(string: ic.code, attributes: attrs))
        case let lk as Markdown.Link:
            for c in lk.children {
                renderInline(c, into: out,
                             baseFont: baseFont, bold: bold, italic: italic,
                             link: lk.destination, ctx: ctx)
            }
        case is SoftBreak:
            out.append(NSAttributedString(string: " "))
        case is LineBreak:
            out.append(NSAttributedString(string: "\n"))
        case let img as Markdown.Image:
            // Inline (non-pure-image paragraph) image fallback: textual placeholder.
            let alt = img.plainText.isEmpty ? (img.source ?? "image") : img.plainText
            out.append(NSAttributedString(
                string: "🖼 \(alt)",
                attributes: [.foregroundColor: NSColor.secondaryLabelColor]
            ))
        default:
            for c in node.children {
                renderInline(c, into: out,
                             baseFont: baseFont, bold: bold, italic: italic,
                             link: link, ctx: ctx)
            }
        }
    }

    private static func renderImageParagraph(_ p: Paragraph,
                                             into out: NSMutableAttributedString,
                                             ctx: RenderContext) {
        let scratch = NSMutableAttributedString()
        for inline in p.children {
            if let img = inline as? Markdown.Image {
                if scratch.length > 0 {
                    appendBlock(scratch.copy() as! NSAttributedString, into: out)
                    scratch.deleteCharacters(in: NSRange(location: 0, length: scratch.length))
                }
                appendBlock(imageAttachment(img, ctx: ctx), into: out)
            } else {
                renderInline(inline, into: scratch,
                             baseFont: .systemFont(ofSize: NSFont.systemFontSize),
                             bold: false, italic: false, link: nil, ctx: ctx)
            }
        }
        if scratch.length > 0 {
            appendBlock(scratch.copy() as! NSAttributedString, into: out)
        }
    }

    private static func imageAttachment(_ img: Markdown.Image,
                                        ctx: RenderContext) -> NSAttributedString {
        guard let src = img.source, !src.isEmpty else {
            return NSAttributedString(
                string: "🖼 \(img.plainText)",
                attributes: [.foregroundColor: NSColor.secondaryLabelColor]
            )
        }
        let url = resolveURL(src, base: ctx.baseURL)
        let attachment = NSTextAttachment()

        if let url, url.isFileURL, let nsi = NSImage(contentsOf: url) {
            attachment.image = nsi
            attachment.bounds = CGRect(origin: .zero,
                                       size: scaledSize(nsi.size, maxWidth: 600))
            let result = NSMutableAttributedString(attachment: attachment)
            result.addAttribute(.markyttdownImageURL, value: url,
                                range: NSRange(location: 0, length: result.length))
            return result
        } else if let url,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" {
            attachment.image = placeholderImage(text: "Loading \(img.plainText.isEmpty ? src : img.plainText)…")
            attachment.bounds = CGRect(x: 0, y: 0, width: 200, height: 24)
            let result = NSMutableAttributedString(attachment: attachment)
            result.addAttribute(.markyttdownImageURL, value: url,
                                range: NSRange(location: 0, length: result.length))
            return result
        } else {
            let alt = img.plainText.isEmpty ? src : img.plainText
            return NSAttributedString(
                string: "🖼 \(alt)",
                attributes: [.foregroundColor: NSColor.secondaryLabelColor]
            )
        }
    }

    private static func scaledSize(_ original: NSSize, maxWidth: CGFloat) -> NSSize {
        guard original.width > 0, original.height > 0 else {
            return NSSize(width: max(maxWidth, 1), height: 24)
        }
        if original.width <= maxWidth { return original }
        let ratio = maxWidth / original.width
        return NSSize(width: maxWidth, height: original.height * ratio)
    }

    private static func placeholderImage(text: String) -> NSImage {
        let size = NSSize(width: max(120, text.count * 7), height: 24)
        let img = NSImage(size: size)
        img.lockFocus()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        text.draw(at: NSPoint(x: 4, y: 4), withAttributes: attrs)
        img.unlockFocus()
        return img
    }

    private static func styledFont(_ base: NSFont, bold: Bool, italic: Bool) -> NSFont {
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        if traits.isEmpty { return base }
        return NSFontManager.shared.convert(base, toHaveTrait: traits)
    }

    private static func headingFont(level: Int) -> NSFont {
        let size: CGFloat
        switch level {
        case 1: size = 28
        case 2: size = 22
        case 3: size = 18
        case 4: size = 16
        case 5: size = 14
        default: size = 13
        }
        return NSFont.systemFont(ofSize: size, weight: .bold)
    }

    static func resolveURL(_ src: String, base: URL?) -> URL? {
        if let url = URL(string: src), url.scheme != nil { return url }
        guard let base else { return URL(string: src) }
        let dir = base.deletingLastPathComponent()
        return URL(fileURLWithPath: src, relativeTo: dir).standardizedFileURL
    }
}

extension NSAttributedString.Key {
    /// Attached to image runs so async loaders can find and replace them.
    static let markyttdownImageURL = NSAttributedString.Key("markyttdown.image.url")
}
