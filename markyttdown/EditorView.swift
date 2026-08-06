import SwiftUI
import AppKit

struct EditorView: NSViewRepresentable {
    @Binding var text: String
    @ObservedObject var sync: ScrollSync
    @ObservedObject var zoom: Zoom

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = .monospacedSystemFont(
            ofSize: NSFont.systemFontSize * CGFloat(zoom.level),
            weight: .regular
        )
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.delegate = context.coordinator
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.string = text
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.scrollView = scroll
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.boundsChanged(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scroll.contentView
        )
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.string != text { tv.string = text }
        let desired = NSFont.monospacedSystemFont(
            ofSize: NSFont.systemFontSize * CGFloat(zoom.level),
            weight: .regular
        )
        if tv.font?.pointSize != desired.pointSize {
            tv.font = desired
        }
        context.coordinator.applyExternalSync()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: EditorView
        weak var scrollView: NSScrollView?
        private var suppressNotification = false

        init(_ parent: EditorView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
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
    }
}
