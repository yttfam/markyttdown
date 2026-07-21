import SwiftUI
import AppKit

@MainActor
private func makeTK1TextView() -> NSTextView {
    // On macOS 14+ this initializer explicitly opts out of TextKit 2.
    if #available(macOS 14.0, *) {
        return NSTextView(usingTextLayoutManager: false)
    }
    // Fallback: construct the full TK1 stack by hand.
    let storage = NSTextStorage()
    let layout = NSLayoutManager()
    storage.addLayoutManager(layout)
    let container = NSTextContainer(
        containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
    )
    container.widthTracksTextView = true
    layout.addTextContainer(container)
    return NSTextView(frame: .zero, textContainer: container)
}

struct PreviewView: NSViewRepresentable {
    let text: String
    let baseURL: URL?
    @ObservedObject var sync: ScrollSync
    @ObservedObject var zoom: Zoom

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // Build a TextKit 1 stack explicitly. Since macOS 14 the default text
        // view uses TextKit 2, whose typesetter runs a per-cell statistical
        // BIDI pass on NSTextTable — pathologically slow (30–60 s beachball
        // on the corp Mac for a 10 kB doc with one table). TextKit 1's
        // NSLayoutManager handles tables in single-digit ms and supports
        // non-contiguous layout so only the visible portion is laid out
        // synchronously.
        let tv = makeTK1TextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isRichText = true
        tv.usesFontPanel = false
        tv.usesFindBar = true
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false
        tv.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
        tv.textContainerInset = NSSize(width: 16, height: 16)
        tv.drawsBackground = false
        tv.allowsDocumentBackgroundColorChange = false
        tv.delegate = context.coordinator
        tv.layoutManager?.allowsNonContiguousLayout = true
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.documentView = tv
        scroll.contentView.postsBoundsChangedNotifications = true

        context.coordinator.scrollView = scroll
        context.coordinator.textView = tv

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.boundsChanged(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scroll.contentView
        )

        context.coordinator.applyContent(text: text, baseURL: baseURL, fontScale: zoom.level)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.applyContent(text: text, baseURL: baseURL, fontScale: zoom.level)
        context.coordinator.applyExternalSync()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: PreviewView
        weak var scrollView: NSScrollView?
        weak var textView: NSTextView?
        private var suppressNotification = false
        private var lastSource: String?
        private var lastBaseURL: URL?
        private var lastFontScale: Double = 0
        private var inFlight: Set<URL> = []

        init(_ parent: PreviewView) { self.parent = parent }

        func applyContent(text: String, baseURL: URL?, fontScale: Double) {
            if lastSource == text && lastBaseURL == baseURL && lastFontScale == fontScale { return }
            lastSource = text
            lastBaseURL = baseURL
            lastFontScale = fontScale
            guard let tv = textView, let storage = tv.textStorage else { return }
            let rendered = NSAttributedMarkdown.render(text, baseURL: baseURL, fontScale: fontScale)
            storage.beginEditing()
            storage.setAttributedString(rendered)
            storage.endEditing()
            scheduleRemoteImageFetches()
        }

        private func scheduleRemoteImageFetches() {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let urls = NSAttributedMarkdown.remoteImageURLs(in: storage)
            for url in urls where !inFlight.contains(url) {
                inFlight.insert(url)
                URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                    guard let data, let image = NSImage(data: data) else {
                        Task { @MainActor [weak self] in self?.inFlight.remove(url) }
                        return
                    }
                    Task { @MainActor [weak self] in
                        guard let self, let storage = self.textView?.textStorage else { return }
                        NSAttributedMarkdown.replace(attachmentForURL: url, with: image, in: storage)
                        self.inFlight.remove(url)
                    }
                }.resume()
            }
        }

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
            Task { @MainActor [weak self] in self?.suppressNotification = false }
        }

        // Open clicked links ourselves so .md sibling links route through our
        // own NSDocumentController instead of whichever app owns .md by default.
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let url: URL?
            if let u = link as? URL { url = u }
            else if let s = link as? String, let u = URL(string: s) { url = u }
            else { url = nil }
            guard let url else { return false }

            if url.isFileURL {
                let ext = url.pathExtension.lowercased()
                if ext == "md" || ext == "markdown" || ext == "mdown" {
                    NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
                    return true
                }
            }
            NSWorkspace.shared.open(url)
            return true
        }
    }
}
