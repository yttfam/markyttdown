import SwiftUI
import Markdown

struct PreviewView: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(MarkdownRenderer.render(text))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
    }
}

enum MarkdownRenderer {
    static func render(_ source: String) -> AttributedString {
        let document = Document(parsing: source)
        var out = AttributedString()
        for child in document.children {
            renderBlock(child, into: &out)
        }
        return out
    }

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
            for child in q.children {
                renderBlock(child, into: &inner)
            }
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
            for child in node.children {
                renderBlock(child, into: &out)
            }
        }
    }

    private static func appendBlock(_ s: AttributedString, into out: inout AttributedString) {
        if !out.characters.isEmpty {
            out.append(AttributedString("\n\n"))
        }
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
        renderInlineChildren(container, into: &out, baseFont: baseFont, bold: bold)
        return out
    }

    private static func renderInlineChildren(
        _ container: any Markup,
        into out: inout AttributedString,
        baseFont: Font,
        bold: Bool,
        italic: Bool = false,
        link: String? = nil
    ) {
        for child in container.children {
            switch child {
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
                renderInlineChildren(s, into: &out, baseFont: baseFont, bold: true, italic: italic, link: link)
            case let e as Emphasis:
                renderInlineChildren(e, into: &out, baseFont: baseFont, bold: bold, italic: true, link: link)
            case let ic as InlineCode:
                var s = AttributedString(ic.code)
                s.font = .system(.body, design: .monospaced)
                s.backgroundColor = .secondary.opacity(0.15)
                if let link, let url = URL(string: link) { s.link = url }
                out.append(s)
            case let lk as Markdown.Link:
                renderInlineChildren(lk, into: &out, baseFont: baseFont, bold: bold, italic: italic, link: lk.destination)
            case is SoftBreak:
                out.append(AttributedString(" "))
            case is LineBreak:
                out.append(AttributedString("\n"))
            case let img as Markdown.Image:
                var s = AttributedString("🖼 " + (img.plainText.isEmpty ? (img.source ?? "image") : img.plainText))
                s.foregroundColor = .secondary
                out.append(s)
            default:
                renderInlineChildren(child, into: &out, baseFont: baseFont, bold: bold, italic: italic, link: link)
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
