import SwiftUI
import AppKit

struct PreviewView: NSViewRepresentable {
    let text: String
    let baseURL: URL?
    @ObservedObject var sync: ScrollSync

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
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

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.contentView.postsBoundsChangedNotifications = true

        context.coordinator.scrollView = scroll
        context.coordinator.textView = tv

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.boundsChanged(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scroll.contentView
        )

        context.coordinator.applyContent(text: text, baseURL: baseURL)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.applyContent(text: text, baseURL: baseURL)
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
        private var inFlight: Set<URL> = []

        init(_ parent: PreviewView) { self.parent = parent }

        func applyContent(text: String, baseURL: URL?) {
            if lastSource == text && lastBaseURL == baseURL { return }
            lastSource = text
            lastBaseURL = baseURL
            guard let tv = textView, let storage = tv.textStorage else { return }
            let rendered = NSAttributedMarkdown.render(text, baseURL: baseURL)
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
